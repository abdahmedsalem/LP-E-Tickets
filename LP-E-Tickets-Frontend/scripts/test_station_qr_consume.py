#!/usr/bin/env python3
"""Test E2E consommation QR station (Odoo ACPEC).

Usage:
  export STATION_IDENTIFIER='votre@station.mr'
  export STATION_SECRET='123456'
  export QR_PUBLIC_CODE='QR-...'   # optionnel : premier QR actif si absent
  python3 scripts/test_station_qr_consume.py

Variables optionnelles:
  BASE_URL          (défaut: http://57.128.181.183:8199)
  CLIENT_IDENTIFIER / CLIENT_SECRET — pour vérifier l'état via mobile/qr/detail
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
import uuid

BASE = os.environ.get("BASE_URL", "http://57.128.181.183:8199").rstrip("/")
STATION_ID = os.environ.get("STATION_IDENTIFIER", "").strip()
STATION_SECRET = os.environ.get("STATION_SECRET", "").strip()
QR_CODE = os.environ.get("QR_PUBLIC_CODE", "").strip()
CLIENT_ID = os.environ.get("CLIENT_IDENTIFIER", "test@example.com").strip()
CLIENT_SECRET = os.environ.get("CLIENT_SECRET", "123456").strip()


def post(route: str, params: dict, token: str | None = None) -> dict:
    body = json.dumps(
        {"jsonrpc": "2.0", "method": "call", "params": params, "id": 1}
    ).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(
        f"{BASE}{route}", data=body, headers=headers, method="POST"
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def login(identifier: str, secret: str) -> tuple[str, dict]:
    raw = post("/api/acpec/mobile_auth/v1/login", {
        "identifier": identifier,
        "secret_code": secret,
    })
    res = raw.get("result") or raw
    data = res.get("data") if isinstance(res.get("data"), dict) else res
    token = data.get("access_token") or data.get("token")
    if not token:
        raise RuntimeError(f"Login failed for {identifier!r}: {res}")
    return token, data


def pick_state(payload: dict) -> str:
    for key in ("qr_state", "state", "status"):
        v = payload.get(key)
        if v and str(v).lower() not in ("success", "ok", "true"):
            return str(v)
    qr = payload.get("qr")
    if isinstance(qr, dict):
        return pick_state(qr)
    return str(payload.get("state") or "?")


def main() -> int:
    if not STATION_ID or not STATION_SECRET:
        print(
            "Définissez STATION_IDENTIFIER et STATION_SECRET (compte profile=station).",
            file=sys.stderr,
        )
        return 2

    print(f"Base: {BASE}")
    print("--- Login station ---")
    station_token, station_profile = login(STATION_ID, STATION_SECRET)
    print(
        f"OK station: profile={station_profile.get('profile')} "
        f"name={station_profile.get('name')}"
    )

    public_code = QR_CODE
    if not public_code:
        print("--- QR actif (liste client) ---")
        client_token, _ = login(CLIENT_ID, CLIENT_SECRET)
        listed = post(
            "/api/acpec/fueltoken/v1/mobile/qr/list",
            {"state": "active", "limit": 5, "offset": 0},
            client_token,
        )
        items = (listed.get("result") or {}).get("data") or []
        if isinstance(items, dict):
            items = items.get("items") or items.get("qrs") or []
        if not items:
            print("Aucun QR actif trouvé. Définissez QR_PUBLIC_CODE.", file=sys.stderr)
            return 3
        public_code = items[0].get("public_code") or items[0].get("publicCode")
        print(f"Utilisation du premier QR actif: {public_code}")

    print(f"\n--- État client AVANT (qr/detail) ---")
    client_token, _ = login(CLIENT_ID, CLIENT_SECRET)
    before = post(
        "/api/acpec/fueltoken/v1/mobile/qr/detail",
        {"public_code": public_code},
        client_token,
    )
    before_data = (before.get("result") or {}).get("data") or before.get("result") or {}
    print(f"state = {pick_state(before_data)}")

    print(f"\n--- station/qr/check ---")
    check = post(
        "/api/acpec/fueltoken/v1/station/qr/check",
        {"public_code": public_code},
        station_token,
    )
    check_res = check.get("result") or check
    check_data = check_res.get("data") if isinstance(check_res.get("data"), dict) else check_res
    can = check_data.get("can_consume") or check_data.get("canConsume")
    print(f"can_consume={can} reason={check_data.get('reason')}")
    if can is False:
        print("QR non consommable — arrêt.", file=sys.stderr)
        return 4

    print(f"\n--- station/qr/use ---")
    use = post(
        "/api/acpec/fueltoken/v1/station/qr/use",
        {
            "public_code": public_code,
            "idempotency_key": f"cli-test-{uuid.uuid4()}",
        },
        station_token,
    )
    use_res = use.get("result") or use
    use_data = use_res.get("data") if isinstance(use_res.get("data"), dict) else use_res
    print(f"ok={use_res.get('ok')} state={pick_state(use_data)}")
    print(json.dumps(use_data, indent=2, ensure_ascii=False)[:1200])

    print(f"\n--- État client APRÈS (qr/detail) ---")
    after = post(
        "/api/acpec/fueltoken/v1/mobile/qr/detail",
        {"public_code": public_code},
        client_token,
    )
    after_data = (after.get("result") or {}).get("data") or after.get("result") or {}
    after_state = pick_state(after_data)
    print(f"state = {after_state}")

    print(f"\n--- station/qr/check (re-scan) ---")
    recheck = post(
        "/api/acpec/fueltoken/v1/station/qr/check",
        {"public_code": public_code},
        station_token,
    )
    rc = recheck.get("result") or recheck
    rc_data = rc.get("data") if isinstance(rc.get("data"), dict) else rc
    print(f"can_consume={rc_data.get('can_consume')} reason={rc_data.get('reason')}")

    consumed = "consum" in after_state.lower() or "consom" in after_state.lower()
    if consumed and rc_data.get("can_consume") is False:
        print("\n✓ QR bien passé en consommé côté API.")
        return 0
    print("\n⚠ Vérifiez manuellement la réponse (état ou droits).", file=sys.stderr)
    return 5


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code}: {e.read().decode()[:500]}", file=sys.stderr)
        raise SystemExit(1)
    except Exception as e:
        print(f"Erreur: {e}", file=sys.stderr)
        raise SystemExit(1)
