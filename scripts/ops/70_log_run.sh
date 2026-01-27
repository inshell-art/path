#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

require_env OPS_NETWORK

log_dir="$WORKBOOK_DIR"
mkdir -p "$log_dir"

log_file="$log_dir/${OPS_NETWORK}-run-$(date -u +%Y%m%d).md"

cat >> "$log_file" <<EOF2

## Run $(utc_now)

- Build log: workbook/artifacts/${OPS_NETWORK}/build/build.log
- Declare output: workbook/artifacts/${OPS_NETWORK}/declare/classes.json
- Deploy output: workbook/artifacts/${OPS_NETWORK}/deploy/addresses.json
- Wire log: workbook/artifacts/${OPS_NETWORK}/wire/wire.log
- Handoff intents: workbook/artifacts/${OPS_NETWORK}/intents/handoff.json
- Verify log: workbook/artifacts/${OPS_NETWORK}/verify/verify.log

Notes:
- Record class hashes, contract addresses, tx hashes, and final owner/admin values here.
- Ensure deployer is fully de-privileged after handoff.
EOF2

log "Run log appended: $log_file"
