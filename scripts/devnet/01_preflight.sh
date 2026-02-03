#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/devnet/00_env.sh"

need() { command -v "$1" >/dev/null 2>&1 || {
  echo "Missing dependency: $1" >&2
  exit 1
}; }

need curl
need jq
need python3
need sncast
need scarb

if [ ! -f "$ACCOUNTS_FILE" ]; then
  echo "Accounts file missing: $ACCOUNTS_FILE" >&2
  exit 1
fi

RPC_BASE="${RPC%/rpc}"
if ! curl -sSf "$RPC_BASE/is_alive" >/dev/null 2>&1; then
  echo "Devnet not responding at $RPC (expected /is_alive)" >&2
  exit 1
fi

# Validate JSON artifact files
jq -e '.' "$ADDR_FILE" >/dev/null 2>&1 || {
  echo "Invalid JSON in $ADDR_FILE" >&2
  exit 1
}
jq -e '.' "$TX_FILE" >/dev/null 2>&1 || {
  echo "Invalid JSON in $TX_FILE" >&2
  exit 1
}

# Ensure artifact dirs exist
mkdir -p "$ARTIFACTS_DIR" "$SVG_DIR" "$META_DIR"

cat <<INFO
==> Preflight OK
RPC=$RPC
ACCOUNT=$ACCOUNT
ACCOUNTS_FILE=$ACCOUNTS_FILE
WORKBOOK_DIR=$WORKBOOK_DIR
ARTIFACTS_DIR=$ARTIFACTS_DIR
PATH_REPO=${PATH_REPO:-<unset>}
INFO
