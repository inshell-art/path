#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
export ROOT

NETWORK=${NETWORK:-}
LANE=${LANE:-deploy}
CHECK_GH_AUTH=${CHECK_GH_AUTH:-0}
GH_REPO=${GH_REPO:-inshell-art/path}
OPSEC_ROOT=${OPSEC_ROOT:-~/.opsec}
export NETWORK LANE

expand_user_path() {
  local value="${1:-}"
  if [[ "$value" == "~/"* ]]; then
    printf '%s\n' "$HOME/${value#~/}"
  else
    printf '%s\n' "$value"
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required tool: $cmd" >&2
    exit 2
  fi
}

check_git_clean() {
  local label="$1"
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Tracked git tree is dirty ($label)." >&2
    exit 1
  fi
}

if [[ -z "$NETWORK" ]]; then
  echo "Usage: NETWORK=<sepolia|mainnet> [LANE=<lane>] [CHECK_GH_AUTH=1] $0" >&2
  exit 2
fi

case "$NETWORK" in
  sepolia|mainnet) ;;
  *)
    echo "Invalid NETWORK: $NETWORK" >&2
    exit 2
    ;;
esac

for cmd in node npm git jq python3 make gitleaks gh; do
  require_cmd "$cmd"
done

python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

root = Path(os.environ["ROOT"])
network = os.environ["NETWORK"]
lane = os.environ["LANE"]
policy_path = root / "ops" / "policy" / f"lane.{network}.json"

if not policy_path.exists():
    print(f"Missing policy file: {policy_path}", file=sys.stderr)
    sys.exit(1)

policy = json.loads(policy_path.read_text())
lanes = policy.get("lanes")
if not isinstance(lanes, dict) or lane not in lanes or not isinstance(lanes[lane], dict):
    print(f"Lane {lane!r} not found in {policy_path.relative_to(root)}", file=sys.stderr)
    sys.exit(1)
PY

PARAMS_FILE=$(expand_user_path "${PARAMS_FILE:-$OPSEC_ROOT/path/params/params.${NETWORK}.deploy.json}")

echo "[devos] network=$NETWORK lane=$LANE"

check_git_clean "before preflight"

NETWORK="$NETWORK" npm run ops:policy:init:check

if [[ "$LANE" == "deploy" ]]; then
  if [[ ! -f "$PARAMS_FILE" ]]; then
    echo "Missing deploy params file: $PARAMS_FILE" >&2
    exit 1
  fi
  if [[ ! -r "$PARAMS_FILE" ]]; then
    echo "Deploy params file is not readable: $PARAMS_FILE" >&2
    exit 1
  fi
  echo "[devos] deploy params ok: $PARAMS_FILE"
fi

if [[ "$CHECK_GH_AUTH" == "1" ]]; then
  gh auth status >/dev/null
  gh repo view "$GH_REPO" >/dev/null
  echo "[devos] gh auth ok for $GH_REPO"
else
  echo "[devos] gh auth check skipped (set CHECK_GH_AUTH=1 to enable)"
fi

npm run ops:scan-secrets
npm run evm:compile
npm run evm:test

check_git_clean "after preflight"

echo "[devos] preflight passed for $NETWORK/$LANE"
