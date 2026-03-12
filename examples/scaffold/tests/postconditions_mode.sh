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
cp "$TEMPLATE_ROOT/policy/devnet.policy.example.json" "$WORK_DIR/policy/devnet.policy.example.json"

cd "$WORK_DIR"
chmod +x ops/tools/*.sh

git init -q
git config user.email "postconditions-test@example.local"
git config user.name "Postconditions Test"
git add .
git commit -q -m "init scaffold postconditions mode tests"

expect_fail() {
  local label="$1"
  shift
  if "$@"; then
    echo "Expected failure but command succeeded: $label" >&2
    exit 1
  fi
  echo "Expected failure observed: $label"
}

write_approval() {
  local bundle_dir="$1"
  BUNDLE_DIR="$bundle_dir" python3 - <<'PY'
import json
import os
from pathlib import Path

bundle = Path(os.environ["BUNDLE_DIR"])
manifest = json.loads((bundle / "bundle_manifest.json").read_text())
run = json.loads((bundle / "run.json").read_text())
approval = {
    "approved_at": "2026-03-08T00:00:00Z",
    "approver": "test",
    "network": run.get("network", ""),
    "lane": run.get("lane", ""),
    "run_id": run.get("run_id", ""),
    "bundle_hash": manifest.get("bundle_hash", ""),
    "intent_hash": "",
    "notes": "test approval"
}
(bundle / "approval.json").write_text(json.dumps(approval, indent=2, sort_keys=True) + "\n")
PY
}

assert_postconditions() {
  local path="$1"
  local expected_mode="$2"
  local expected_status="$3"
  POST_PATH="$path" EXPECTED_MODE="$expected_mode" EXPECTED_STATUS="$expected_status" python3 - <<'PY'
import json
import os
from pathlib import Path

p = Path(os.environ["POST_PATH"])
doc = json.loads(p.read_text())
if doc.get("mode") != os.environ["EXPECTED_MODE"]:
    raise SystemExit(f"unexpected mode: {doc.get('mode')}")
if doc.get("status") != os.environ["EXPECTED_STATUS"]:
    raise SystemExit(f"unexpected status: {doc.get('status')}")
print(f"postconditions mode/status ok: {doc.get('mode')}/{doc.get('status')}")
PY
}

# 1) Auto-pass happy path.
RUN_PASS="pc-auto-pass"
NETWORK=devnet LANE=deploy RUN_ID="$RUN_PASS" ops/tools/bundle.sh
write_approval "$WORK_DIR/bundles/devnet/$RUN_PASS"
env SIGNING_OS=1 NETWORK=devnet RUN_ID="$RUN_PASS" ops/tools/apply_bundle.sh
NETWORK=devnet RUN_ID="$RUN_PASS" ops/tools/postconditions.sh
assert_postconditions "bundles/devnet/$RUN_PASS/postconditions.json" "auto" "pass"
python3 - <<'PY'
import json
from pathlib import Path
doc = json.loads(Path("bundles/devnet/pc-auto-pass/postconditions.json").read_text())
checks = {c["name"]: c for c in doc.get("checks", [])}
for key in ("txs_present", "bundle_verified", "deploy_post_state_present"):
    if key not in checks or checks[key].get("status") != "pass":
        raise SystemExit(f"missing or non-pass check: {key}")
print("auto-pass checks verified")
PY

# 2) Missing txs => auto-fail.
RUN_NO_TXS="pc-missing-txs"
NETWORK=devnet LANE=plan RUN_ID="$RUN_NO_TXS" ops/tools/bundle.sh
NETWORK=devnet RUN_ID="$RUN_NO_TXS" ops/tools/postconditions.sh
assert_postconditions "bundles/devnet/$RUN_NO_TXS/postconditions.json" "auto" "fail"

# 3) checks.path.json pass=false => auto-fail.
RUN_PATH_FAIL="pc-checks-path-fail"
NETWORK=devnet LANE=deploy RUN_ID="$RUN_PATH_FAIL" ops/tools/bundle.sh
write_approval "$WORK_DIR/bundles/devnet/$RUN_PATH_FAIL"
env SIGNING_OS=1 NETWORK=devnet RUN_ID="$RUN_PATH_FAIL" ops/tools/apply_bundle.sh
cat > "bundles/devnet/$RUN_PATH_FAIL/checks.path.json" <<'JSON'
{
  "pass": false,
  "reason": "negative fixture"
}
JSON
NETWORK=devnet RUN_ID="$RUN_PATH_FAIL" ops/tools/postconditions.sh
assert_postconditions "bundles/devnet/$RUN_PATH_FAIL/postconditions.json" "auto" "fail"
python3 - <<'PY'
import json
from pathlib import Path
doc = json.loads(Path("bundles/devnet/pc-checks-path-fail/postconditions.json").read_text())
checks = {c["name"]: c for c in doc.get("checks", [])}
if checks.get("checks_path_pass", {}).get("status") != "fail":
    raise SystemExit("expected checks_path_pass=fail")
print("checks.path failure propagated")
PY

# 4) Manual compatibility (explicit status required).
POSTCONDITIONS_MODE=manual POSTCONDITIONS_STATUS=pass NETWORK=devnet RUN_ID="$RUN_PASS" ops/tools/postconditions.sh
assert_postconditions "bundles/devnet/$RUN_PASS/postconditions.json" "manual" "pass"
expect_fail "manual requires explicit status" env POSTCONDITIONS_MODE=manual NETWORK=devnet RUN_ID="$RUN_PASS" ops/tools/postconditions.sh

echo "postconditions_mode.sh: PASS"
