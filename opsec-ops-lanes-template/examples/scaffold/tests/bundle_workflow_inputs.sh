#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEMPLATE_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
WORK_DIR=$(mktemp -d)

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cp -R "$TEMPLATE_ROOT/examples/scaffold/." "$WORK_DIR"
cp -R "$TEMPLATE_ROOT/schemas" "$WORK_DIR/schemas"

cd "$WORK_DIR"
chmod +x ops/tools/*.sh

git init -q
git config user.email "bundle-workflow-test@example.local"
git config user.name "Bundle Workflow Test"
git add .
git commit -q -m "init scaffold bundle workflow tests"

expect_fail() {
  local label="$1"
  shift
  if "$@"; then
    echo "Expected failure but command succeeded: $label" >&2
    exit 1
  fi
  echo "Expected failure observed: $label"
}

make_params() {
  local path="$1"
  cat > "$path" <<'JSON'
{
  "name": "Ops Token",
  "symbol": "OPS",
  "paymentToken": "0x0000000000000000000000000000000000000011",
  "treasury": "0x0000000000000000000000000000000000000022",
  "openTime": 1735689600,
  "startDelay": 3600
}
JSON
}

lock_wrapper_json() {
  local network="$1"
  local lane="$2"
  local run_id="$3"
  local params_file="$4"
  NETWORK="$network" LANE="$lane" RUN_ID="$run_id" INPUT_FILE="$params_file" ops/tools/lock_inputs.sh >/dev/null
  local path="$WORK_DIR/artifacts/$network/current/inputs/inputs.$run_id.json"
  printf '%s' "$(<"$path")"
}

workflow_bundle() {
  local network="$1"
  local lane="$2"
  local run_id="$3"
  local inputs_json="${4:-}"

  NETWORK="$network" LANE="$lane" RUN_ID="$run_id" INPUTS_JSON="$inputs_json" bash -euo pipefail <<'SH'
POLICY_FILE=""
for candidate in \
  "./ops/policy/lane.${NETWORK}.json" \
  "./ops/policy/${NETWORK}.policy.json" \
  "./ops/policy/lane.${NETWORK}.example.json" \
  "./ops/policy/${NETWORK}.policy.example.json" \
  "./policy/${NETWORK}.policy.example.json"
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

has_required = False
for item in required_inputs:
    if isinstance(item, dict) and isinstance(item.get("kind"), str) and item.get("kind").strip():
        has_required = True
        break

print("true" if has_required else "false")
PY
)

INPUTS_TEMPLATE=""
if [[ "$REQUIRES_INPUTS" == "true" && -z "$INPUTS_JSON" ]]; then
  echo "inputs_json is required because lane policy declares required_inputs for $NETWORK/$LANE. Provide the locked wrapper JSON output from ops/tools/lock_inputs.sh." >&2
  exit 2
fi

if [[ -n "$INPUTS_JSON" ]]; then
  INPUTS_TEMPLATE="artifacts/${NETWORK}/current/inputs/inputs.${RUN_ID}.json"
  mkdir -p "$(dirname "$INPUTS_TEMPLATE")"
  printf '%s' "$INPUTS_JSON" > "$INPUTS_TEMPLATE"
fi

NETWORK="$NETWORK" LANE="$LANE" RUN_ID="$RUN_ID" INPUTS_TEMPLATE="$INPUTS_TEMPLATE" ./ops/tools/bundle.sh
SH
}

PARAMS_FILE="$WORK_DIR/constructor.params.json"
make_params "$PARAMS_FILE"

# 1) CI-like workflow succeeds for sepolia deploy when given locked wrapper JSON.
RUN_SEPOLIA="ci-sepolia-deploy"
LOCKED_SEPOLIA_JSON=$(lock_wrapper_json sepolia deploy "$RUN_SEPOLIA" "$PARAMS_FILE")
rm -f "artifacts/sepolia/current/inputs/inputs.${RUN_SEPOLIA}.json"
workflow_bundle sepolia deploy "$RUN_SEPOLIA" "$LOCKED_SEPOLIA_JSON"
python3 - <<'PY'
import hashlib
import json
from pathlib import Path

run_id = "ci-sepolia-deploy"
artifact_inputs = Path(f"artifacts/sepolia/current/inputs/inputs.{run_id}.json")
bundle_inputs = Path(f"bundles/sepolia/{run_id}/inputs.json")
intent = json.loads(Path(f"bundles/sepolia/{run_id}/intent.json").read_text())

if not artifact_inputs.exists():
    raise SystemExit("workflow did not write locked inputs to artifacts path")
if not bundle_inputs.exists():
    raise SystemExit("bundle missing inputs.json")
digest = hashlib.sha256(bundle_inputs.read_bytes()).hexdigest()
if intent.get("inputs_sha256") != digest:
    raise SystemExit("intent.json.inputs_sha256 mismatch")
print("sepolia workflow bundle verified")
PY

# 2) CI-like workflow succeeds for mainnet deploy when given locked wrapper JSON.
RUN_MAINNET="ci-mainnet-deploy"
LOCKED_MAINNET_JSON=$(lock_wrapper_json mainnet deploy "$RUN_MAINNET" "$PARAMS_FILE")
rm -f "artifacts/mainnet/current/inputs/inputs.${RUN_MAINNET}.json"
workflow_bundle mainnet deploy "$RUN_MAINNET" "$LOCKED_MAINNET_JSON"
python3 - <<'PY'
from pathlib import Path

run_id = "ci-mainnet-deploy"
if not Path(f"bundles/mainnet/{run_id}/inputs.json").exists():
    raise SystemExit("mainnet bundle missing inputs.json")
print("mainnet workflow bundle verified")
PY

# 3) Missing inputs_json must fail clearly for required-input lane.
expect_fail "workflow missing inputs_json for deploy lane" workflow_bundle sepolia deploy ci-missing-inputs ""

# 4) Non-required lane should still work without inputs_json.
workflow_bundle devnet plan ci-devnet-plan ""

echo "bundle_workflow_inputs.sh: PASS"
