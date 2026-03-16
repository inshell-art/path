#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RUN_A="audit-fixture-a-$STAMP"
RUN_B="audit-fixture-b-$STAMP"
AUDIT_ID="audit-smoke-$STAMP"
AUDIT_DIR="$ROOT/audits/devnet/$AUDIT_ID"
BUNDLE_ROOT="$ROOT/bundles/devnet"
COMMIT=$(git rev-parse HEAD)
DEPLOYER=$(jq -r '.signer_alias_map.DEVNET_DEPLOY_SW_A' ops/policy/lane.devnet.json)

cleanup() {
  rm -rf "$BUNDLE_ROOT/$RUN_A" "$BUNDLE_ROOT/$RUN_B" "$AUDIT_DIR"
}
trap cleanup EXIT

make_bundle() {
  local run_id="$1"
  local run_dir="$BUNDLE_ROOT/$run_id"
  install -d -m 755 "$run_dir"
  RUN_DIR="$run_dir" RUN_ID="$run_id" COMMIT="$COMMIT" DEPLOYER="$DEPLOYER" python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

run_dir = Path(os.environ["RUN_DIR"])
run_id = os.environ["RUN_ID"]
commit = os.environ["COMMIT"]
deployer = os.environ["DEPLOYER"]

run = {
    "created_at": "2026-03-16T00:00:00Z",
    "git_commit": commit,
    "lane": "deploy",
    "network": "devnet",
    "run_id": run_id,
}
checks = {
    "checks_version": 1,
    "inputs_pinned": True,
    "lane": "deploy",
    "network": "devnet",
    "pass": True,
}
inputs = {
    "kind": "constructor_params",
    "network": "devnet",
    "lane": "deploy",
    "run_id": run_id,
    "payload": {
        "name": "PATH NFT",
        "symbol": "PATH"
    }
}
inputs_bytes = json.dumps(inputs, indent=2, sort_keys=True).encode() + b"\n"
inputs_sha = hashlib.sha256(inputs_bytes).hexdigest()
intent = {
    "inputs_sha256": inputs_sha,
    "lane": "deploy",
    "network": "devnet",
    "notes": "fixture",
}
files = {
    "run.json": run,
    "intent.json": intent,
    "checks.json": checks,
}
for name, payload in files.items():
    (run_dir / name).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
(run_dir / "inputs.json").write_bytes(inputs_bytes)
immutable = []
for rel in ["run.json", "intent.json", "checks.json", "inputs.json"]:
    digest = hashlib.sha256((run_dir / rel).read_bytes()).hexdigest()
    immutable.append({"path": rel, "sha256": digest})
manifest_digest = hashlib.sha256("\n".join(f"{item['path']}={item['sha256']}" for item in immutable).encode()).hexdigest()
manifest = {
    "bundle_hash": manifest_digest,
    "generated_at": "2026-03-16T00:00:00Z",
    "git_commit": commit,
    "immutable_files": immutable,
    "lane": "deploy",
    "manifest_version": 1,
    "network": "devnet",
    "run_id": run_id,
}
approval = {
    "approved_at": "2026-03-16T00:05:00Z",
    "approver": "fixture",
    "bundle_hash": manifest_digest,
    "inputs_sha256": inputs_sha,
    "lane": "deploy",
    "network": "devnet",
    "run_id": run_id,
}
txs = {
    "applied_at": "2026-03-16T00:10:00Z",
    "network": "devnet",
    "lane": "deploy",
    "execution_mode": "deployed",
    "txs": ["0xabc123"],
    "inputs_sha256": inputs_sha,
    "inputs_file": str((run_dir / "inputs.json").resolve()),
    "signer_address_used": deployer,
    "expected_deployer_address": deployer,
}
postconditions = {
    "mode": "auto",
    "network": "devnet",
    "run_id": run_id,
    "status": "pass",
    "verified_at": "2026-03-16T00:15:00Z",
}
for name, payload in {
    "bundle_manifest.json": manifest,
    "approval.json": approval,
    "txs.json": txs,
    "postconditions.json": postconditions,
}.items():
    (run_dir / name).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
}

make_bundle "$RUN_A"
make_bundle "$RUN_B"

NETWORK=devnet AUDIT_ID="$AUDIT_ID" RUN_IDS="$RUN_A,$RUN_B" ./ops/tools/audit_plan.sh
NETWORK=devnet AUDIT_ID="$AUDIT_ID" ./ops/tools/audit_collect.sh
NETWORK=devnet AUDIT_ID="$AUDIT_ID" ./ops/tools/audit_verify.sh
NETWORK=devnet AUDIT_ID="$AUDIT_ID" ./ops/tools/audit_report.sh
NETWORK=devnet AUDIT_ID="$AUDIT_ID" AUDIT_APPROVER=fixture ./ops/tools/audit_signoff.sh

jq -e '.status == "pass"' "$AUDIT_DIR/audit_verify.json" >/dev/null
jq -e '.status == "pass"' "$AUDIT_DIR/audit_report.json" >/dev/null
test -f "$AUDIT_DIR/audit_manifest.json"
test -f "$AUDIT_DIR/audit_report.md"
test -f "$AUDIT_DIR/audit_signoff.json"
