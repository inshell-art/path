#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}
AUDIT_ID=${AUDIT_ID:-}
AUDIT_PATH=${AUDIT_PATH:-}

ROOT=$(git rev-parse --show-toplevel)

if [[ -n "$AUDIT_PATH" ]]; then
  AUDIT_DIR="$AUDIT_PATH"
else
  if [[ -z "$NETWORK" || -z "$AUDIT_ID" ]]; then
    echo "Usage: NETWORK=<devnet|sepolia|mainnet> AUDIT_ID=<id> $0" >&2
    echo "   or: AUDIT_PATH=<path> $0" >&2
    exit 2
  fi
  AUDIT_DIR="$ROOT/audits/$NETWORK/$AUDIT_ID"
fi

PLAN_PATH="$AUDIT_DIR/audit_plan.json"
if [[ ! -f "$PLAN_PATH" ]]; then
  echo "Missing audit_plan.json in $AUDIT_DIR" >&2
  exit 2
fi

export ROOT AUDIT_DIR PLAN_PATH

python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path
from datetime import datetime, timezone

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()

root = Path(os.environ["ROOT"])
audit_dir = Path(os.environ["AUDIT_DIR"])
plan = json.loads(Path(os.environ["PLAN_PATH"]).read_text())
network = plan.get("network", "")
audit_id = plan.get("audit_id", "")
run_ids = plan.get("run_ids", [])

bundle_refs = []
files_indexed = []

for run_id in run_ids:
    bundle_dir = root / "bundles" / network / run_id
    exists = bundle_dir.is_dir()
    bundle_refs.append({
        "run_id": run_id,
        "bundle_path": str(bundle_dir.relative_to(root)),
        "exists": exists
    })
    if not exists:
        continue
    for file_path in sorted([p for p in bundle_dir.rglob("*") if p.is_file()]):
        files_indexed.append({
            "path": str(file_path.relative_to(root)),
            "sha256": sha256_file(file_path)
        })

payload = {
    "audit_id": audit_id,
    "network": network,
    "bundle_refs": bundle_refs,
    "files_indexed": files_indexed,
    "collect_time": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
}

(audit_dir / "audit_evidence_index.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
print(f"Audit evidence index written: {audit_dir / 'audit_evidence_index.json'}")
PY
