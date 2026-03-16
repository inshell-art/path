#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RUN_ID="audit-negative-$STAMP"
AUDIT_ID="audit-negative-$STAMP"
AUDIT_DIR="$ROOT/audits/devnet/$AUDIT_ID"
BUNDLE_DIR="$ROOT/bundles/devnet/$RUN_ID"
COMMIT=$(git rev-parse HEAD)
DEPLOYER=$(jq -r '.signer_alias_map.DEVNET_DEPLOY_SW_A' ops/policy/lane.devnet.json)

cleanup() {
  rm -rf "$BUNDLE_DIR" "$AUDIT_DIR"
}
trap cleanup EXIT

install -d -m 755 "$BUNDLE_DIR"
RUN_DIR="$BUNDLE_DIR" RUN_ID="$RUN_ID" COMMIT="$COMMIT" DEPLOYER="$DEPLOYER" python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

run_dir = Path(os.environ["RUN_DIR"])
run_id = os.environ["RUN_ID"]
commit = os.environ["COMMIT"]
deployer = os.environ["DEPLOYER"]
run = {"created_at": "2026-03-16T00:00:00Z", "git_commit": commit, "lane": "deploy", "network": "devnet", "run_id": run_id}
checks = {"checks_version": 1, "inputs_pinned": True, "lane": "deploy", "network": "devnet", "pass": True}
inputs = {"kind": "constructor_params", "network": "devnet", "lane": "deploy", "run_id": run_id}
inputs_bytes = json.dumps(inputs, indent=2, sort_keys=True).encode() + b"\n"
inputs_sha = hashlib.sha256(inputs_bytes).hexdigest()
intent = {"inputs_sha256": inputs_sha, "lane": "deploy", "network": "devnet"}
for name, payload in {"run.json": run, "intent.json": intent, "checks.json": checks}.items():
    (run_dir / name).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
(run_dir / "inputs.json").write_bytes(inputs_bytes)
immutable = []
for rel in ["run.json", "intent.json", "checks.json", "inputs.json"]:
    immutable.append({"path": rel, "sha256": hashlib.sha256((run_dir / rel).read_bytes()).hexdigest()})
bundle_hash = hashlib.sha256("\n".join(f"{item['path']}={item['sha256']}" for item in immutable).encode()).hexdigest()
for name, payload in {
    "bundle_manifest.json": {"bundle_hash": bundle_hash, "generated_at": "2026-03-16T00:00:00Z", "git_commit": commit, "immutable_files": immutable, "lane": "deploy", "manifest_version": 1, "network": "devnet", "run_id": run_id},
    "approval.json": {"approved_at": "2026-03-16T00:05:00Z", "approver": "fixture", "bundle_hash": bundle_hash, "inputs_sha256": inputs_sha, "lane": "deploy", "network": "devnet", "run_id": run_id},
    "txs.json": {"applied_at": "2026-03-16T00:10:00Z", "network": "devnet", "lane": "deploy", "execution_mode": "deployed", "txs": ["0xabc123"], "inputs_sha256": inputs_sha, "inputs_file": str((run_dir / 'inputs.json').resolve()), "signer_address_used": deployer, "expected_deployer_address": deployer},
    "postconditions.json": {"mode": "auto", "network": "devnet", "run_id": run_id, "status": "pass", "verified_at": "2026-03-16T00:15:00Z"}
}.items():
    (run_dir / name).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

NETWORK=devnet AUDIT_ID="$AUDIT_ID" RUN_IDS="$RUN_ID" ./ops/tools/audit_plan.sh
NETWORK=devnet AUDIT_ID="$AUDIT_ID" ./ops/tools/audit_collect.sh
NETWORK=devnet AUDIT_ID="$AUDIT_ID" ./ops/tools/audit_verify.sh
NETWORK=devnet AUDIT_ID="$AUDIT_ID" ./ops/tools/audit_report.sh
chmod u+w "$AUDIT_DIR/runs/$RUN_ID/postconditions.json"
printf '\n' >> "$AUDIT_DIR/runs/$RUN_ID/postconditions.json"
if NETWORK=devnet AUDIT_ID="$AUDIT_ID" AUDIT_APPROVER=fixture ./ops/tools/audit_signoff.sh; then
  echo "expected audit signoff to fail after evidence mutation" >&2
  exit 1
fi
