#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

require_env OPS_NETWORK RPC OPS_VERIFY_CMD

CONTRACTS_DIR="${OPS_CONTRACTS_DIR:-$REPO_ROOT}"

verify_dir="$(artifact_dir verify)"
log_file="$verify_dir/verify.log"

log "Verifying deployment (logs: $log_file)"
run_cmd_logged "$OPS_VERIFY_CMD" "$log_file" "$CONTRACTS_DIR"

cat > "$verify_dir/verify.json" <<EOF2
{
  "network": "${OPS_NETWORK}",
  "ran_at": "$(utc_now)",
  "log": "verify.log"
}
EOF2

log "Verify complete."
