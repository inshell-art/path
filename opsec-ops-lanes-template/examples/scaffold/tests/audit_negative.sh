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
cp "$TEMPLATE_ROOT/policy/audit.policy.example.json" "$WORK_DIR/policy/audit.policy.example.json"

cd "$WORK_DIR"
chmod +x ops/tools/*.sh

git init -q
git config user.email "audit-negative@example.local"
git config user.name "Audit Negative"
git add .
git commit -q -m "init scaffold negatives"

expect_fail() {
  local label="$1"
  shift
  if "$@"; then
    echo "Expected failure but command succeeded: $label" >&2
    exit 1
  fi
  echo "Expected failure observed: $label"
}

# 1) manifest mismatch
NETWORK=devnet LANE=plan RUN_ID=neg-manifest ops/tools/bundle.sh
python3 - <<'PY'
import json
from pathlib import Path
path = Path("bundles/devnet/neg-manifest/intent.json")
data = json.loads(path.read_text())
data["notes"] = "tampered"
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
expect_fail "manifest mismatch" env NETWORK=devnet RUN_ID=neg-manifest ops/tools/verify_bundle.sh

# 2) commit mismatch
NETWORK=devnet LANE=plan RUN_ID=neg-commit ops/tools/bundle.sh
python3 - <<'PY'
import hashlib
import json
from pathlib import Path
bundle = Path("bundles/devnet/neg-commit")
run_path = bundle / "run.json"
manifest_path = bundle / "bundle_manifest.json"
run = json.loads(run_path.read_text())
manifest = json.loads(manifest_path.read_text())
run["git_commit"] = "deadbeef"
run_path.write_text(json.dumps(run, indent=2, sort_keys=True) + "\n")
for item in manifest.get("immutable_files", []):
    p = bundle / item["path"]
    item["sha256"] = hashlib.sha256(p.read_bytes()).hexdigest()
bundle_hash_input = "\n".join([f"{i['path']}={i['sha256']}" for i in manifest["immutable_files"]]).encode()
manifest["bundle_hash"] = hashlib.sha256(bundle_hash_input).hexdigest()
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY
expect_fail "commit mismatch" env NETWORK=devnet RUN_ID=neg-commit ops/tools/verify_bundle.sh

# 3) missing approval
NETWORK=devnet LANE=plan RUN_ID=neg-missing-approval ops/tools/bundle.sh
expect_fail "missing approval" env SIGNING_OS=1 NETWORK=devnet RUN_ID=neg-missing-approval ops/tools/apply_bundle.sh

# 4) approval hash mismatch
NETWORK=devnet LANE=plan RUN_ID=neg-hash-mismatch ops/tools/bundle.sh
python3 - <<'PY'
import json
from pathlib import Path
bundle = Path("bundles/devnet/neg-hash-mismatch")
manifest = json.loads((bundle / "bundle_manifest.json").read_text())
wrong_hash = "0" * 64
if wrong_hash == manifest.get("bundle_hash"):
    wrong_hash = "1" * 64
approval = {
    "approved_at": "2026-03-03T00:00:00Z",
    "approver": "negative-test",
    "network": "devnet",
    "lane": "plan",
    "run_id": "neg-hash-mismatch",
    "bundle_hash": wrong_hash,
    "intent_hash": "",
    "notes": "negative fixture"
}
(bundle / "approval.json").write_text(json.dumps(approval, indent=2, sort_keys=True) + "\n")
PY
expect_fail "approval hash mismatch" env SIGNING_OS=1 NETWORK=devnet RUN_ID=neg-hash-mismatch ops/tools/apply_bundle.sh

# 5) missing postconditions when rehearsal proof is required
NETWORK=mainnet LANE=handoff RUN_ID=neg-proof-missing-post ops/tools/bundle.sh
python3 - <<'PY'
import json
from pathlib import Path
bundle = Path("bundles/mainnet/neg-proof-missing-post")
manifest = json.loads((bundle / "bundle_manifest.json").read_text())
run = json.loads((bundle / "run.json").read_text())
approval = {
    "approved_at": "2026-03-03T00:00:00Z",
    "approver": "negative-test",
    "network": run.get("network", "mainnet"),
    "lane": run.get("lane", "handoff"),
    "run_id": run.get("run_id", "neg-proof-missing-post"),
    "bundle_hash": manifest.get("bundle_hash", ""),
    "intent_hash": "",
    "notes": "negative fixture"
}
(bundle / "approval.json").write_text(json.dumps(approval, indent=2, sort_keys=True) + "\n")
proof_dir = Path("bundles/devnet/proof-without-postconditions")
proof_dir.mkdir(parents=True, exist_ok=True)
(proof_dir / "txs.json").write_text(json.dumps({"txs": ["0xabc"]}, indent=2, sort_keys=True) + "\n")
PY
expect_fail "missing postconditions proof" env SIGNING_OS=1 NETWORK=mainnet RUN_ID=neg-proof-missing-post REHEARSAL_PROOF_RUN_ID=proof-without-postconditions ops/tools/apply_bundle.sh

echo "audit_negative.sh: PASS"
