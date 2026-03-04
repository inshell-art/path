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

REPORT_PATH="$AUDIT_DIR/audit_report.json"
if [[ ! -f "$REPORT_PATH" ]]; then
  echo "Missing audit_report.json in $AUDIT_DIR" >&2
  exit 2
fi

export ROOT REPORT_PATH

python3 - <<'PY'
import json
import os
from pathlib import Path

root = Path(os.environ["ROOT"])
report_path = Path(os.environ["REPORT_PATH"])
report = json.loads(report_path.read_text())

policy = {}
for candidate in [
    root / "ops/policy/audit.policy.json",
    root / "ops/policy/audit.policy.example.json",
    root / "policy/audit.policy.example.json",
]:
    if candidate.exists():
        policy = json.loads(candidate.read_text())
        break

fail_statuses = set((policy.get("release_gate", {}) or {}).get("fail_on_status", ["fail"]))
status = report.get("status", "")
if status in fail_statuses:
    raise SystemExit(f"audit release gate failed: status={status} report={report_path}")

print(f"audit release gate passed: status={status} report={report_path}")
PY
