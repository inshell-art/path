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
git config user.email "audit-smoke@example.local"
git config user.name "Audit Smoke"
git add .
git commit -q -m "init scaffold smoke"

RUN_ID="smoke-$(date -u +%Y%m%dT%H%M%SZ)"
AUDIT_ID="audit-smoke-$(date -u +%Y%m%dT%H%M%SZ)"

NETWORK=devnet LANE=plan RUN_ID="$RUN_ID" ops/tools/bundle.sh
NETWORK=devnet AUDIT_ID="$AUDIT_ID" RUN_IDS="$RUN_ID" ops/tools/audit_plan.sh
NETWORK=devnet AUDIT_ID="$AUDIT_ID" ops/tools/audit_collect.sh
NETWORK=devnet AUDIT_ID="$AUDIT_ID" ops/tools/audit_verify.sh
NETWORK=devnet AUDIT_ID="$AUDIT_ID" ops/tools/audit_report.sh

AUDIT_DIR="audits/devnet/$AUDIT_ID"
for name in audit_plan.json audit_evidence_index.json audit_verification.json audit_report.json findings.json; do
  if [[ ! -f "$AUDIT_DIR/$name" ]]; then
    echo "Missing required audit output: $AUDIT_DIR/$name" >&2
    exit 1
  fi
done

export AUDIT_DIR
python3 - <<'PY'
import json
import os
from pathlib import Path

base = Path(os.environ["AUDIT_DIR"])
for name in [
    "audit_plan.json",
    "audit_evidence_index.json",
    "audit_verification.json",
    "audit_report.json",
    "findings.json",
]:
    json.loads((base / name).read_text())

report = json.loads((base / "audit_report.json").read_text())
if report.get("status") not in {"pass", "pass_with_findings", "fail"}:
    raise SystemExit("invalid audit_report status")
print("Smoke audit output valid")
PY

echo "audit_smoke.sh: PASS"
