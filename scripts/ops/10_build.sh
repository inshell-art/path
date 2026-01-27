#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

require_env OPS_NETWORK

CONTRACTS_DIR="${OPS_CONTRACTS_DIR:-$REPO_ROOT}"
BUILD_CMD="${OPS_BUILD_CMD:-}"

if [[ -z "$BUILD_CMD" ]]; then
  if command -v scarb >/dev/null 2>&1; then
    BUILD_CMD="scarb build"
  else
    die "Set OPS_BUILD_CMD (or install scarb)"
  fi
fi

build_dir="$(artifact_dir build)"
log_file="$build_dir/build.log"

log "Building contracts (logs: $log_file)"
run_cmd_logged "$BUILD_CMD" "$log_file" "$CONTRACTS_DIR"

cat > "$build_dir/build.json" <<EOF2
{
  "network": "${OPS_NETWORK}",
  "ran_at": "$(utc_now)",
  "contracts_dir": "${CONTRACTS_DIR}",
  "build_cmd": "${BUILD_CMD}",
  "log": "build.log"
}
EOF2

log "Build complete."
