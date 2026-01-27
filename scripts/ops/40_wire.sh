#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

require_env OPS_NETWORK RPC ACCOUNT ACCOUNTS_FILE OPS_WIRE_CMD

CONTRACTS_DIR="${OPS_CONTRACTS_DIR:-$REPO_ROOT}"

wire_dir="$(artifact_dir wire)"
log_file="$wire_dir/wire.log"

log "Wiring contracts (logs: $log_file)"
run_cmd_logged "$OPS_WIRE_CMD" "$log_file" "$CONTRACTS_DIR"

cat > "$wire_dir/wire.json" <<EOF2
{
  "network": "${OPS_NETWORK}",
  "ran_at": "$(utc_now)",
  "log": "wire.log"
}
EOF2

log "Wire complete."
