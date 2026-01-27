#!/usr/bin/env bash
set -euo pipefail

OPS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$OPS_ROOT/../.." && pwd)"
WORKBOOK_DIR="${WORKBOOK_DIR:-$REPO_ROOT/workbook}"

log() {
  printf '[ops] %s\n' "$*"
}

die() {
  printf '[ops] ERROR: %s\n' "$*" >&2
  exit 1
}

require_env() {
  local var
  for var in "$@"; do
    if [[ -z "${!var:-}" ]]; then
      die "Missing required env: $var"
    fi
  done
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      die "Missing required command: $cmd"
    fi
  done
}

utc_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

artifact_dir() {
  require_env OPS_NETWORK
  local dir="$WORKBOOK_DIR/artifacts/$OPS_NETWORK/$1"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

run_cmd_logged() {
  local cmd="$1"
  local log_file="$2"
  local workdir="$3"
  mkdir -p "$(dirname "$log_file")"
  (cd "$workdir" && bash -lc "$cmd") >"$log_file" 2>&1
}
