#!/usr/bin/env bash
# FuelToken — point d’entrée pour `flutter run` et `flutter build` avec Odoo ACPEC.
#
# 1) Copier scripts/env/flutter.mobile.example.env → scripts/env/flutter.mobile.env
#    et y mettre au minimum ODOO_JSONRPC_BASE_URL=http(s)://hôte:port
# 2) Développement : ./scripts/run.sh   (args → flutter run, ex. -d chrome)
#    Release APK    : ./scripts/run.sh build apk --release
#
# Optionnel : exporter les variables dans le shell au lieu du fichier .env.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ENV_DIR="${ROOT}/scripts/env"
ENV_LOCAL="${ENV_DIR}/flutter.mobile.env"
ENV_EXAMPLE="${ENV_DIR}/flutter.mobile.example.env"
ENV_LOCAL_OVERRIDE="${ENV_DIR}/flutter.mobile.local.env"
TEAM_ODOO_URL="${ODOO_JSONRPC_BASE_URL:-http://127.0.0.1:8069}"

mkdir -p "$ENV_DIR"

if [[ ! -f "$ENV_LOCAL" && -f "$ENV_EXAMPLE" ]]; then
  cp "$ENV_EXAMPLE" "$ENV_LOCAL"
  echo "→ Créé scripts/env/flutter.mobile.env depuis flutter.mobile.example.env" >&2
elif [[ ! -f "$ENV_LOCAL" && ! -f "$ENV_EXAMPLE" ]]; then
  cat >"$ENV_LOCAL" <<EOF
# Généré par scripts/run.sh — faites git pull puis vérifiez scripts/env/
ODOO_JSONRPC_BASE_URL=${TEAM_ODOO_URL}
ODOO_USE_ACPEC_AUTH=true
ODOO_FUEL_ENABLED=true
EOF
  echo "→ Fichiers env absents : créé scripts/env/flutter.mobile.env (URL équipe par défaut)" >&2
  echo "  Si besoin : git pull  puis  ls scripts/env/" >&2
fi

_load_env_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  set -a
  # shellcheck disable=SC1090
  source "$f"
  set +a
}

_load_env_file "$ENV_LOCAL"
_load_env_file "$ENV_LOCAL_OVERRIDE"

export ODOO_JSONRPC_BASE_URL="${ODOO_JSONRPC_BASE_URL:-}"
export ODOO_DATABASE="${ODOO_DATABASE:-}"
export ODOO_USE_ACPEC_AUTH="${ODOO_USE_ACPEC_AUTH:-true}"
export ODOO_FUEL_ENABLED="${ODOO_FUEL_ENABLED:-true}"

if [[ -z "${ODOO_JSONRPC_BASE_URL}" ]]; then
  export ODOO_JSONRPC_BASE_URL="${TEAM_ODOO_URL}"
  echo "ODOO_JSONRPC_BASE_URL vide — utilisation : ${ODOO_JSONRPC_BASE_URL}" >&2
  echo "  Vérifiez : git pull && ls scripts/env/" >&2
fi

echo "Odoo → ${ODOO_JSONRPC_BASE_URL}" >&2

DEFINES=(
  "--dart-define=ODOO_JSONRPC_BASE_URL=${ODOO_JSONRPC_BASE_URL}"
  "--dart-define=ODOO_USE_ACPEC_AUTH=${ODOO_USE_ACPEC_AUTH}"
)

if [[ -n "${API_BASE_URL:-}" ]]; then
  DEFINES+=("--dart-define=API_BASE_URL=${API_BASE_URL}")
fi

if [[ "${ODOO_FUEL_ENABLED:-}" == "true" ]] || [[ "${ODOO_FUEL_ENABLED:-}" == "1" ]]; then
  DEFINES+=("--dart-define=ODOO_FUEL_ENABLED=true")
fi

if [[ -n "${ODOO_DATABASE}" ]]; then
  DEFINES+=("--dart-define=ODOO_DATABASE=${ODOO_DATABASE}")
fi

if [[ -n "${ODOO_JSONRPC_CONTROLLER_PATH:-}" ]]; then
  DEFINES+=("--dart-define=ODOO_JSONRPC_CONTROLLER_PATH=${ODOO_JSONRPC_CONTROLLER_PATH}")
fi

for key in \
  ACPEC_ADMIN_EMAILS \
  ACPEC_STATION_EMAILS \
  ODOO_RPC_LOGIN_METHOD \
  ODOO_RPC_SESSION_ME_METHOD \
  ODOO_RPC_LOGOUT_METHOD \
  ODOO_RPC_COMPLETE_REGISTRATION_METHOD \
  ODOO_RPC_LOGIN_PATH \
  ODOO_RPC_SESSION_PATH \
  ODOO_RPC_LOGOUT_PATH \
  ODOO_RPC_SIGNUP_PATH \
  ODOO_SIGNUP_COMPANY_ID \
  ODOO_ACPEC_VERSION_PATH \
  ODOO_ACPEC_SIGNUP_COMPANIES_PATH \
  ODOO_ACPEC_ADMIN_ACCOUNT_REQUESTS_PATH \
  ODOO_RPC_FUEL_WALLET_PATH \
  ODOO_RPC_FUEL_PURCHASES_CREATE_PATH \
  ODOO_RPC_FUEL_PURCHASES_LIST_PATH \
  ODOO_RPC_FUEL_FACES_PATH \
  ODOO_RPC_FUEL_QR_ISSUE_PATH \
  ODOO_RPC_FUEL_QR_LIST_PATH \
  ODOO_RPC_FUEL_QR_DETAIL_PATH \
  ODOO_RPC_FUEL_QR_SPLIT_PATH \
  ODOO_RPC_FUEL_QR_RETIRER_PATH \
  ODOO_RPC_FUEL_QR_SEPARER_PATH \
  ODOO_RPC_FUEL_CARNETS_TRANSFER_PATH \
  ODOO_RPC_FUEL_STATION_QR_USE_PATH
do
  val="${!key:-}"
  if [[ -n "$val" ]]; then
    DEFINES+=("--dart-define=${key}=${val}")
  fi
done

if [[ "${1:-}" == "build" ]]; then
  shift
  build_args=("$@")
  is_release=false
  for arg in "${build_args[@]}"; do
    if [[ "$arg" == "--release" ]]; then
      is_release=true
      break
    fi
  done
  if [[ "$is_release" == true ]]; then
    url_lower="$(printf '%s' "${ODOO_JSONRPC_BASE_URL}" | tr '[:upper:]' '[:lower:]')"
    if [[ "$url_lower" == http://* ]]; then
      echo "Erreur : build release avec ODOO_JSONRPC_BASE_URL en HTTP." >&2
      echo "  Les stores exigent HTTPS. Utilisez https://… dans flutter.mobile.env" >&2
      exit 1
    fi
    if [[ -n "${API_BASE_URL:-}" ]]; then
      api_lower="$(printf '%s' "${API_BASE_URL}" | tr '[:upper:]' '[:lower:]')"
      if [[ "$api_lower" == http://* ]]; then
        echo "Erreur : build release avec API_BASE_URL en HTTP." >&2
        exit 1
      fi
    fi
  fi
  exec flutter build "${build_args[@]}" "${DEFINES[@]}"
fi

exec flutter run "${DEFINES[@]}" "$@"
