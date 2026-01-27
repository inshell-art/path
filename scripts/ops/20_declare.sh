#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

require_env OPS_NETWORK RPC ACCOUNT ACCOUNTS_FILE OPS_DECLARE_CMD

CONTRACTS_DIR="${OPS_CONTRACTS_DIR:-$REPO_ROOT}"
OUTPUT_PATH="${OPS_DECLARE_OUTPUT:-$REPO_ROOT/output/classes.${OPS_NETWORK}.json}"

declare_dir="$(artifact_dir declare)"
log_file="$declare_dir/declare.log"

log "Declaring contracts (logs: $log_file)"
run_cmd_logged "$OPS_DECLARE_CMD" "$log_file" "$CONTRACTS_DIR"

if [[ ! -f "$OUTPUT_PATH" ]]; then
  die "Declare output not found at $OUTPUT_PATH"
fi

cp "$OUTPUT_PATH" "$declare_dir/classes.json"

cat > "$declare_dir/declare.json" <<EOF2
{
  "network": "${OPS_NETWORK}",
  "ran_at": "$(utc_now)",
  "output": "classes.json",
  "log": "declare.log"
}
EOF2

log "Declare complete."
