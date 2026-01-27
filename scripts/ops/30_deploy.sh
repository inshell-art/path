#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

require_env OPS_NETWORK RPC ACCOUNT ACCOUNTS_FILE OPS_DEPLOY_CMD

CONTRACTS_DIR="${OPS_CONTRACTS_DIR:-$REPO_ROOT}"
OUTPUT_PATH="${OPS_DEPLOY_OUTPUT:-$REPO_ROOT/output/addresses.${OPS_NETWORK}.json}"

deploy_dir="$(artifact_dir deploy)"
log_file="$deploy_dir/deploy.log"

log "Deploying contracts (logs: $log_file)"
run_cmd_logged "$OPS_DEPLOY_CMD" "$log_file" "$CONTRACTS_DIR"

if [[ ! -f "$OUTPUT_PATH" ]]; then
  die "Deploy output not found at $OUTPUT_PATH"
fi

cp "$OUTPUT_PATH" "$deploy_dir/addresses.json"

cat > "$deploy_dir/deploy.json" <<EOF2
{
  "network": "${OPS_NETWORK}",
  "ran_at": "$(utc_now)",
  "output": "addresses.json",
  "log": "deploy.log"
}
EOF2

log "Deploy complete."
