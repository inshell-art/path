#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEMPLATE_ROOT=$(cd "$SCRIPT_DIR/../../../.." && pwd)
WORK_DIR=$(mktemp -d)

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cp -R "$TEMPLATE_ROOT/examples/scaffold/." "$WORK_DIR"
cp -R "$TEMPLATE_ROOT/schemas" "$WORK_DIR/schemas"
mkdir -p "$WORK_DIR/examples"
cp -R "$TEMPLATE_ROOT/examples/inputs" "$WORK_DIR/examples/inputs"

cd "$WORK_DIR"
chmod +x ops/tools/*.sh

git init -q
git config user.email "lock-inputs-test@example.local"
git config user.name "Lock Inputs Test"
git add .
git commit -q -m "init scaffold lock-inputs tests"

expect_fail() {
  local label="$1"
  shift
  if "$@"; then
    echo "Expected failure but command succeeded: $label" >&2
    exit 1
  fi
  echo "Expected failure observed: $label"
}

GOOD_PARAMS="$WORK_DIR/good.params.json"
cat > "$GOOD_PARAMS" <<'JSON'
{
  "name": "Ops Token",
  "symbol": "OPS",
  "paymentToken": "0x0000000000000000000000000000000000000011",
  "treasury": "0x0000000000000000000000000000000000000022",
  "openTime": 1735689600
}
JSON

BAD_PARAMS="$WORK_DIR/bad.params.json"
cat > "$BAD_PARAMS" <<'JSON'
{
  "name": "Ops Token",
  "symbol": "OPS",
  "paymentToken": "0x0000000000000000000000000000000000000011",
  "treasury": "0xYourTreasury"
}
JSON

MINIMAL_SCHEMA="examples/inputs/params.constructor_params.minimal.schema.example.json"

# 1) Pass case: normal params with string fields should pass invariants.
NETWORK=devnet LANE=deploy RUN_ID=pass-basic INPUT_FILE="$GOOD_PARAMS" ops/tools/lock_inputs.sh >/dev/null
if [[ ! -f "$WORK_DIR/artifacts/devnet/current/inputs/inputs.pass-basic.json" ]]; then
  echo "Expected locked inputs output not found for pass-basic" >&2
  exit 1
fi

# 2) Fail case: placeholder-like params should fail invariants.
expect_fail "placeholder token rejection" env NETWORK=devnet LANE=deploy RUN_ID=fail-placeholder INPUT_FILE="$BAD_PARAMS" ops/tools/lock_inputs.sh

# 3) Strict mode: missing schema should fail.
expect_fail "strict mode requires PARAMS_SCHEMA" env NETWORK=devnet LANE=deploy RUN_ID=fail-strict-missing-schema INPUT_FILE="$GOOD_PARAMS" STRICT_PARAMS_SCHEMA=1 ops/tools/lock_inputs.sh

# 4) Sepolia/Mainnet should refuse template example schema by default.
expect_fail "reject example schema on sepolia" env NETWORK=sepolia LANE=deploy RUN_ID=fail-example-schema INPUT_FILE="$GOOD_PARAMS" PARAMS_SCHEMA="$MINIMAL_SCHEMA" ops/tools/lock_inputs.sh

# 5) Override allows example schema explicitly and records schema hash evidence.
NETWORK=sepolia LANE=deploy RUN_ID=pass-example-override INPUT_FILE="$GOOD_PARAMS" PARAMS_SCHEMA="$MINIMAL_SCHEMA" ALLOW_EXAMPLE_PARAMS_SCHEMA=1 ops/tools/lock_inputs.sh >/dev/null
python3 - <<'PY'
import json
from pathlib import Path

p = Path("artifacts/sepolia/current/inputs/inputs.pass-example-override.json")
doc = json.loads(p.read_text())
source = doc.get("source", {})
if not source.get("params_schema_sha256"):
    raise SystemExit("missing source.params_schema_sha256")
if not source.get("params_schema_path_hint"):
    raise SystemExit("missing source.params_schema_path_hint")
print("schema hash evidence recorded")
PY

echo "test_lock_inputs.sh: PASS"
