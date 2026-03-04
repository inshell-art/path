#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}
AUDIT_ID=${AUDIT_ID:-}
AUDIT_PATH=${AUDIT_PATH:-}
AUDIT_APPROVER=${AUDIT_APPROVER:-${USER:-unknown}}
AUDIT_SIGNOFF_NOTE=${AUDIT_SIGNOFF_NOTE:-}

ROOT=$(git rev-parse --show-toplevel)

if [[ -n "$AUDIT_PATH" ]]; then
  AUDIT_DIR="$AUDIT_PATH"
else
  if [[ -z "$NETWORK" || -z "$AUDIT_ID" ]]; then
    echo "Usage: NETWORK=<devnet|sepolia|mainnet> AUDIT_ID=<id> [AUDIT_APPROVER=<name>] $0" >&2
    echo "   or: AUDIT_PATH=<path> $0" >&2
    exit 2
  fi
  AUDIT_DIR="$ROOT/audits/$NETWORK/$AUDIT_ID"
fi

REPORT_PATH="$AUDIT_DIR/audit_report.json"
if [[ ! -f "$REPORT_PATH" ]]; then
  echo "Missing audit_report.json in $AUDIT_DIR" >&2
  exit 2
fi

export AUDIT_DIR REPORT_PATH AUDIT_APPROVER AUDIT_SIGNOFF_NOTE

python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path
from datetime import datetime, timezone

audit_dir = Path(os.environ["AUDIT_DIR"])
report_path = Path(os.environ["REPORT_PATH"])
report = json.loads(report_path.read_text())
report_hash = hashlib.sha256(report_path.read_bytes()).hexdigest()

signoff = {
    "audit_id": report.get("audit_id", ""),
    "approver": os.environ["AUDIT_APPROVER"],
    "approved_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "report_hash": report_hash,
    "notes": os.environ.get("AUDIT_SIGNOFF_NOTE", "")
}

(audit_dir / "signoff.json").write_text(json.dumps(signoff, indent=2, sort_keys=True) + "\n")
print(f"Audit signoff written: {audit_dir / 'signoff.json'}")
PY
