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
mkdir -p "$WORK_DIR/policy"
cp "$TEMPLATE_ROOT/policy/sepolia.policy.example.json" "$WORK_DIR/policy/sepolia.policy.example.json"
cp "$TEMPLATE_ROOT/policy/mainnet.policy.example.json" "$WORK_DIR/policy/mainnet.policy.example.json"

cd "$WORK_DIR"
chmod +x ops/tools/*.sh

git init -q
git config user.email "inputs-gate-test@example.local"
git config user.name "Inputs Gate Test"
git add .
git commit -q -m "init scaffold inputs gate tests"

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
  "startDelay": 3600,
  "pricing": {
    "startPrice": "1000000000000000000",
    "endPrice": "500000000000000000"
  },
  "tokenPerEpoch": "1000",
  "epochSeconds": 86400
}
JSON
}

lock_inputs_for_run() {
  local network="$1"
  local lane="$2"
  local run_id="$3"
  local params_file="$4"
  NETWORK="$network" LANE="$lane" RUN_ID="$run_id" INPUT_FILE="$params_file" ops/tools/lock_inputs.sh >/dev/null
  echo "$WORK_DIR/artifacts/$network/current/inputs/inputs.$run_id.json"
}

write_approval() {
  local bundle_dir="$1"
  BUNDLE_DIR="$bundle_dir" python3 - <<'PY'
import json
import os
from pathlib import Path
bundle = Path(os.environ["BUNDLE_DIR"])
manifest = json.loads((bundle / "bundle_manifest.json").read_text())
intent = json.loads((bundle / "intent.json").read_text())
run = json.loads((bundle / "run.json").read_text())
approval = {
    "approved_at": "2026-03-04T00:00:00Z",
    "approver": "test",
    "network": run.get("network", ""),
    "lane": run.get("lane", ""),
    "run_id": run.get("run_id", ""),
    "bundle_hash": manifest.get("bundle_hash", ""),
    "intent_hash": "",
    "inputs_sha256": intent.get("inputs_sha256", ""),
    "notes": "test approval"
}
(bundle / "approval.json").write_text(json.dumps(approval, indent=2, sort_keys=True) + "\n")
PY
}

PARAMS_FILE="$WORK_DIR/constructor.params.json"
make_params "$PARAMS_FILE"

# 1) Required-input policy: deploy without INPUTS_TEMPLATE must fail.
expect_fail "missing inputs template for required lane" env NETWORK=sepolia LANE=deploy RUN_ID=req-missing ops/tools/bundle.sh

# 2) Valid locked inputs should pass verify/apply and be recorded.
RUN_VALID="valid-pinned"
LOCKED_VALID=$(lock_inputs_for_run sepolia deploy "$RUN_VALID" "$PARAMS_FILE")
NETWORK=sepolia LANE=deploy RUN_ID="$RUN_VALID" INPUTS_TEMPLATE="$LOCKED_VALID" ops/tools/bundle.sh
NETWORK=sepolia RUN_ID="$RUN_VALID" ops/tools/verify_bundle.sh
write_approval "$WORK_DIR/bundles/sepolia/$RUN_VALID"

# external override should fail apply
OTHER_INPUTS="$WORK_DIR/inputs.override.json"
cp "$LOCKED_VALID" "$OTHER_INPUTS"
expect_fail "external INPUTS_FILE override" env SIGNING_OS=1 NETWORK=sepolia RUN_ID="$RUN_VALID" INPUTS_FILE="$OTHER_INPUTS" ops/tools/apply_bundle.sh

# apply with bundled inputs should pass
env SIGNING_OS=1 NETWORK=sepolia RUN_ID="$RUN_VALID" ops/tools/apply_bundle.sh
python3 - <<'PY'
import json
from pathlib import Path
txs = json.loads(Path("bundles/sepolia/valid-pinned/txs.json").read_text())
if not txs.get("inputs_sha256"):
    raise SystemExit("txs.json missing inputs_sha256")
if not txs.get("inputs_file"):
    raise SystemExit("txs.json missing inputs_file")
print("inputs binding recorded in txs.json")
PY

# 3) Mutation test: mutate one byte in inputs.json after bundle => verify fails.
RUN_MUTATE="mutate-inputs"
LOCKED_MUTATE=$(lock_inputs_for_run sepolia deploy "$RUN_MUTATE" "$PARAMS_FILE")
NETWORK=sepolia LANE=deploy RUN_ID="$RUN_MUTATE" INPUTS_TEMPLATE="$LOCKED_MUTATE" ops/tools/bundle.sh
python3 - <<'PY'
import json
from pathlib import Path
p = Path("bundles/sepolia/mutate-inputs/inputs.json")
data = json.loads(p.read_text())
data["params"]["name"] = "Tampered"
p.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
expect_fail "mutated inputs bytes" env NETWORK=sepolia RUN_ID="$RUN_MUTATE" ops/tools/verify_bundle.sh

# 4) Coherence test: mismatch inputs.network with manifest rehashed => verify fails on coherence.
RUN_COH="coherence-mismatch"
LOCKED_COH=$(lock_inputs_for_run sepolia deploy "$RUN_COH" "$PARAMS_FILE")
NETWORK=sepolia LANE=deploy RUN_ID="$RUN_COH" INPUTS_TEMPLATE="$LOCKED_COH" ops/tools/bundle.sh
python3 - <<'PY'
import hashlib
import json
from pathlib import Path
b = Path("bundles/sepolia/coherence-mismatch")
inputs = json.loads((b / "inputs.json").read_text())
inputs["network"] = "mainnet"
(b / "inputs.json").write_text(json.dumps(inputs, indent=2, sort_keys=True) + "\n")
manifest = json.loads((b / "bundle_manifest.json").read_text())
for item in manifest.get("immutable_files", []):
    p = b / item["path"]
    item["sha256"] = hashlib.sha256(p.read_bytes()).hexdigest()
bundle_hash_input = "\n".join([f"{i['path']}={i['sha256']}" for i in manifest["immutable_files"]]).encode()
manifest["bundle_hash"] = hashlib.sha256(bundle_hash_input).hexdigest()
(b / "bundle_manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
expect_fail "inputs coherence mismatch" env NETWORK=sepolia RUN_ID="$RUN_COH" ops/tools/verify_bundle.sh

# 5) Mainnet rehearsal-proof gate remains unchanged and enforced.
RUN_MAINNET="mainnet-proof-check"
LOCKED_MAINNET=$(lock_inputs_for_run mainnet deploy "$RUN_MAINNET" "$PARAMS_FILE")
NETWORK=mainnet LANE=deploy RUN_ID="$RUN_MAINNET" INPUTS_TEMPLATE="$LOCKED_MAINNET" ops/tools/bundle.sh
NETWORK=mainnet RUN_ID="$RUN_MAINNET" ops/tools/verify_bundle.sh
write_approval "$WORK_DIR/bundles/mainnet/$RUN_MAINNET"
expect_fail "mainnet rehearsal proof gate" env SIGNING_OS=1 NETWORK=mainnet RUN_ID="$RUN_MAINNET" ops/tools/apply_bundle.sh

echo "inputs_gate.sh: PASS"
