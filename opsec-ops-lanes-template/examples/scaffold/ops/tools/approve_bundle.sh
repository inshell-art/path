#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}
RUN_ID=${RUN_ID:-}
BUNDLE_PATH=${BUNDLE_PATH:-}

ROOT=$(git rev-parse --show-toplevel)

if [[ -n "$BUNDLE_PATH" ]]; then
  BUNDLE_DIR="$BUNDLE_PATH"
else
  if [[ -z "$NETWORK" || -z "$RUN_ID" ]]; then
    echo "Usage: NETWORK=<devnet|sepolia|mainnet> RUN_ID=<id> $0" >&2
    echo "   or: BUNDLE_PATH=<path> $0" >&2
    exit 2
  fi
  BUNDLE_DIR="$ROOT/bundles/$NETWORK/$RUN_ID"
fi

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "Bundle directory not found: $BUNDLE_DIR" >&2
  exit 2
fi

if [[ ! -f "$BUNDLE_DIR/bundle_manifest.json" ]]; then
  echo "Missing bundle_manifest.json in $BUNDLE_DIR" >&2
  exit 2
fi

export BUNDLE_DIR

read -r BUNDLE_HASH INTENT_HASH NETWORK_FROM_RUN LANE_FROM_RUN RUN_ID_FROM_RUN <<EOF_HASH
$(python3 - <<'PY'
import json
import os
import hashlib
from pathlib import Path
bundle_dir = Path(os.environ["BUNDLE_DIR"])
manifest = json.loads((bundle_dir / "bundle_manifest.json").read_text())
run = json.loads((bundle_dir / "run.json").read_text())

bundle_hash = manifest.get("bundle_hash", "")
intent_hash = ""
for item in manifest.get("immutable_files", []):
    if item.get("path") == "intent.json":
        intent_hash = item.get("sha256", "")
        break
if not intent_hash and (bundle_dir / "intent.json").exists():
    intent_hash = hashlib.sha256((bundle_dir / "intent.json").read_bytes()).hexdigest()

print(bundle_hash, intent_hash, run.get("network", ""), run.get("lane", ""), run.get("run_id", ""))
PY
)
EOF_HASH

if [[ -z "$BUNDLE_HASH" || -z "$NETWORK_FROM_RUN" || -z "$LANE_FROM_RUN" ]]; then
  echo "Invalid bundle or run.json" >&2
  exit 2
fi

SUFFIX=${BUNDLE_HASH: -8}
PHRASE_REQUIRED="APPROVE $NETWORK_FROM_RUN $LANE_FROM_RUN $SUFFIX"

echo "Type exactly: $PHRASE_REQUIRED"
read -r PHRASE

if [[ "$PHRASE" != "$PHRASE_REQUIRED" ]]; then
  echo "Approval phrase mismatch" >&2
  exit 2
fi

APPROVER=${USER:-unknown}
APPROVED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export BUNDLE_HASH INTENT_HASH NETWORK_FROM_RUN LANE_FROM_RUN APPROVER APPROVED_AT RUN_ID_FROM_RUN

python3 - <<'PY'
import json
import os
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
approval = {
    "approved_at": os.environ["APPROVED_AT"],
    "approver": os.environ["APPROVER"],
    "network": os.environ["NETWORK_FROM_RUN"],
    "lane": os.environ["LANE_FROM_RUN"],
    "run_id": os.environ.get("RUN_ID_FROM_RUN", ""),
    "bundle_hash": os.environ["BUNDLE_HASH"],
    "intent_hash": os.environ["INTENT_HASH"],
    "notes": "Human approval required. No manual calldata review."
}

(bundle_dir / "approval.json").write_text(json.dumps(approval, indent=2, sort_keys=True) + "\n")
print(f"Approval written to {bundle_dir / 'approval.json'}")
PY
