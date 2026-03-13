#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}
LANE=${LANE:-}
RUN_ID=${RUN_ID:-}
GH_REPO=${GH_REPO:-}
GH_REF=${GH_REF:-main}
WORKFLOW_NAME=${WORKFLOW_NAME:-Ops Bundle (CI)}
LOCKED_INPUTS_FILE=${LOCKED_INPUTS_FILE:-}

ROOT=$(git rev-parse --show-toplevel)

if [[ -z "$NETWORK" || -z "$LANE" || -z "$RUN_ID" ]]; then
  echo "Usage: NETWORK=<devnet|sepolia|mainnet> LANE=<lane> RUN_ID=<id> $0" >&2
  echo "   optional: GH_REPO=<owner/repo> GH_REF=<ref> WORKFLOW_NAME=<name> LOCKED_INPUTS_FILE=<path>" >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Missing GitHub CLI 'gh' in PATH" >&2
  exit 2
fi

if [[ -z "$GH_REPO" ]]; then
  GH_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
fi

if [[ -z "$GH_REPO" ]]; then
  echo "Unable to determine GitHub repository. Set GH_REPO=<owner/repo>." >&2
  exit 2
fi

POLICY_FILE=""
for candidate in \
  "$ROOT/ops/policy/lane.${NETWORK}.json" \
  "$ROOT/ops/policy/${NETWORK}.policy.json" \
  "$ROOT/ops/policy/lane.${NETWORK}.example.json" \
  "$ROOT/ops/policy/${NETWORK}.policy.example.json" \
  "$ROOT/policy/${NETWORK}.policy.example.json"
do
  if [[ -f "$candidate" ]]; then
    POLICY_FILE="$candidate"
    break
  fi
done

if [[ -z "$POLICY_FILE" ]]; then
  echo "Missing policy file for network: $NETWORK" >&2
  exit 2
fi

REQUIRES_INPUTS=$(POLICY_FILE="$POLICY_FILE" RUN_LANE="$LANE" python3 - <<'PY'
import json
import os
from pathlib import Path

policy = json.loads(Path(os.environ["POLICY_FILE"]).read_text())
lane_cfg = ((policy.get("lanes") or {}).get(os.environ["RUN_LANE"]) or {})
required_inputs = lane_cfg.get("required_inputs", [])
if required_inputs is None:
    required_inputs = []
if not isinstance(required_inputs, list):
    raise SystemExit("policy lanes.<lane>.required_inputs must be a list when set")

for item in required_inputs:
    if isinstance(item, dict) and isinstance(item.get("kind"), str) and item.get("kind").strip():
        print("true")
        break
else:
    print("false")
PY
)

if [[ -z "$LOCKED_INPUTS_FILE" ]]; then
  LOCKED_INPUTS_FILE="$ROOT/artifacts/$NETWORK/current/inputs/inputs.$RUN_ID.json"
fi

cmd=(
  gh workflow run "$WORKFLOW_NAME"
  -R "$GH_REPO"
  --ref "$GH_REF"
  -f "network=$NETWORK"
  -f "lane=$LANE"
  -f "run_id=$RUN_ID"
)

if [[ "$REQUIRES_INPUTS" == "true" ]]; then
  if [[ ! -f "$LOCKED_INPUTS_FILE" ]]; then
    echo "Locked inputs file not found: $LOCKED_INPUTS_FILE" >&2
    exit 2
  fi
  cmd+=(-F "inputs_json=@$LOCKED_INPUTS_FILE")
fi

output="$("${cmd[@]}" 2>&1)"
status=$?
printf '%s\n' "$output"
if [[ $status -ne 0 ]]; then
  exit $status
fi

run_url=$(printf '%s\n' "$output" | awk '/https:\/\/github\.com\/.*\/actions\/runs\/[0-9]+/ {print $0; exit}')
run_db_id=""
if [[ -n "$run_url" ]]; then
  run_db_id="${run_url##*/}"
fi

echo "network=$NETWORK"
echo "lane=$LANE"
echo "run_id=$RUN_ID"
if [[ "$REQUIRES_INPUTS" == "true" ]]; then
  echo "locked_inputs_file=$LOCKED_INPUTS_FILE"
fi
if [[ -n "$run_db_id" ]]; then
  echo "run_db_id=$run_db_id"
fi
