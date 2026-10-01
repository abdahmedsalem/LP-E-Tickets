#!/usr/bin/env bash
# LP E-Tickets — Lanceur Web macOS pour Safari / Chrome / Firefox
# Usage : ./scripts/run_web.sh

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ENV_DIR="${ROOT}/scripts/env"
ENV_LOCAL="${ENV_DIR}/flutter.mobile.env"
ENV_LOCAL_OVERRIDE="${ENV_DIR}/flutter.mobile.local.env"
DEFAULT_ODOO_URL="http://127.0.0.1:8069"
DEFAULT_DB="lp-e-tickets-local"
PORT="${PORT:-8091}"

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

ODOO_BACKEND_URL="${ODOO_JSONRPC_BASE_URL:-$DEFAULT_ODOO_URL}"
ODOO_DB="${ODOO_DATABASE:-$DEFAULT_DB}"

echo "==========================================="
echo " LP E-Tickets — Lancement Web (Safari/Mac)"
echo " Odoo Backend Réel : $ODOO_BACKEND_URL"
echo " Base de données   : $ODOO_DB"
echo " Serveur Local     : http://127.0.0.1:$PORT"
echo "==========================================="

# Pour le navigateur, l'URL de base de l'app pointe vers le serveur local (même origine)
# afin d'éviter tout blocage de sécurité CORS dans Safari/Chrome.
# Le serveur local relaie ensuite les appels vers le backend Odoo.
WEB_CLIENT_BASE_URL="http://127.0.0.1:${PORT}"

echo "→ 1. Compilation du build Web Flutter..."
flutter build web \
  --dart-define="ODOO_JSONRPC_BASE_URL=${WEB_CLIENT_BASE_URL}" \
  --dart-define="ODOO_DATABASE=${ODOO_DB}" \
  --dart-define="ODOO_USE_ACPEC_AUTH=true" \
  --dart-define="ODOO_FUEL_ENABLED=true"

export PORT="$PORT"
export ODOO_ORIGIN="$ODOO_BACKEND_URL"

echo ""
echo "→ 2. Ouverture de Safari sur http://127.0.0.1:${PORT} ..."
open -a Safari "http://127.0.0.1:${PORT}" 2>/dev/null || open "http://127.0.0.1:${PORT}" || true

echo ""
echo "→ 3. Serveur Web & Proxy actif !"
echo "     - URL de l'application : http://127.0.0.1:${PORT}"
echo "     - Proxy API actif vers : ${ODOO_BACKEND_URL}"
echo "     (Appuyez sur Ctrl+C pour arrêter le serveur)"
echo ""
exec python3 "${ROOT}/tool/web_proxy_server.py"
