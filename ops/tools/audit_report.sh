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
VERIFY_PATH="$AUDIT_DIR/audit_verification.json"
if [[ ! -f "$PLAN_PATH" || ! -f "$VERIFY_PATH" ]]; then
  echo "Missing audit_plan.json or audit_verification.json in $AUDIT_DIR" >&2
  exit 2
fi

POLICY_FILE="$ROOT/ops/policy/audit.policy.json"
if [[ ! -f "$POLICY_FILE" ]]; then
  POLICY_FILE="$ROOT/ops/policy/audit.policy.example.json"
fi
if [[ ! -f "$POLICY_FILE" ]]; then
  POLICY_FILE="$ROOT/policy/audit.policy.example.json"
fi

export ROOT AUDIT_DIR PLAN_PATH VERIFY_PATH POLICY_FILE

python3 - <<'PY'
import json
import os
import hashlib
from pathlib import Path
from datetime import datetime, timezone

root = Path(os.environ["ROOT"])
audit_dir = Path(os.environ["AUDIT_DIR"])
plan = json.loads(Path(os.environ["PLAN_PATH"]).read_text())
verification = json.loads(Path(os.environ["VERIFY_PATH"]).read_text())
policy = {}
policy_path = Path(os.environ.get("POLICY_FILE", ""))
if policy_path.exists():
    policy = json.loads(policy_path.read_text())

severity_by_control = {
    "AUD-001": "high",
    "AUD-002": "high",
    "AUD-003": "medium",
    "AUD-004": "high",
    "AUD-005": "medium",
    "AUD-006": "medium",
    "AUD-007": "high",
    "AUD-008": "high",
    "AUD-009": "medium",
    "AUD-010": "critical",
    "AUD-011": "high",
}
order = {"critical": 0, "high": 1, "medium": 2, "low": 3}

controls = plan.get("controls", [])
results = verification.get("control_results", [])
result_by_control = {r.get("control_id"): r for r in results}

findings = []
for cid in controls:
    r = result_by_control.get(cid)
    if not r:
        continue
    if r.get("status") != "fail":
        continue
    sev = severity_by_control.get(cid, "medium")
    findings.append({
        "id": f"F-{cid}",
        "severity": sev,
        "control_id": cid,
        "title": r.get("details", "Control failed"),
        "evidence_refs": r.get("evidence_refs", []),
        "repro_commands": r.get("repro_commands", []),
        "status": "open",
        "owner": "ops-owner",
        "tier": r.get("tier", "INFERRED")
    })

findings.sort(key=lambda x: order.get(x["severity"], 9))

summary = {"critical": 0, "high": 0, "medium": 0, "low": 0}
for f in findings:
    summary[f["severity"]] += 1

covered = len([r for r in results if r.get("status") in {"pass", "fail"}])
total = len(controls)
percent = round((covered / total * 100.0), 2) if total else 100.0

verified_claims = [
    f"{r.get('control_id')}={r.get('status')}"
    for r in results
    if r.get("status") == "pass" and r.get("tier") == "VERIFIED"
]
limitations = [
    f"{r.get('control_id')}: {r.get('details')}"
    for r in results
    if r.get("status") == "skip" or r.get("tier") == "INFERRED"
]

max_open = policy.get("max_open_findings_by_severity", {"critical": 0, "high": 0, "medium": 9999, "low": 9999})
min_cov = float(policy.get("min_coverage_percent", 0))

threshold_breach = any(summary[s] > int(max_open.get(s, 0)) for s in ["critical", "high", "medium", "low"])
coverage_breach = percent < min_cov

if threshold_breach or coverage_breach:
    status = "fail"
elif findings:
    status = "pass_with_findings"
else:
    status = "pass"

generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
report = {
    "audit_id": plan.get("audit_id"),
    "status": status,
    "coverage": {
        "covered": covered,
        "total": total,
        "percent": percent
    },
    "summary": summary,
    "verified_claims": verified_claims,
    "limitations": limitations,
    "repo_commit": os.popen("git rev-parse HEAD").read().strip(),
    "generated_at": generated_at
}

findings_doc = {
    "audit_id": plan.get("audit_id"),
    "findings": findings
}

# Minimal schema enforcement without external dependencies
schema_report_path = root / "schemas/audit_report.schema.json"
schema_findings_path = root / "schemas/audit_finding.schema.json"
if schema_report_path.exists():
    schema_report = json.loads(schema_report_path.read_text())
else:
    schema_report = {
        "required": ["audit_id", "status", "coverage", "summary", "verified_claims", "limitations", "repo_commit", "generated_at"],
        "properties": {"status": {"enum": ["pass", "pass_with_findings", "fail"]}}
    }
if schema_findings_path.exists():
    schema_findings = json.loads(schema_findings_path.read_text())
else:
    schema_findings = {
        "required": ["audit_id", "findings"],
        "properties": {
            "findings": {
                "items": {
                    "required": ["id", "severity", "control_id", "title", "evidence_refs", "repro_commands", "status", "owner"]
                }
            }
        }
    }

for key in schema_report.get("required", []):
    if key not in report:
        raise SystemExit(f"audit_report missing required key: {key}")
if report["status"] not in schema_report["properties"]["status"]["enum"]:
    raise SystemExit("audit_report status enum violation")

for key in schema_findings.get("required", []):
    if key not in findings_doc:
        raise SystemExit(f"findings doc missing required key: {key}")
for f in findings_doc["findings"]:
    for key in schema_findings["properties"]["findings"]["items"]["required"]:
        if key not in f:
            raise SystemExit(f"finding missing required key: {key}")
    if f["severity"] not in ["low", "medium", "high", "critical"]:
        raise SystemExit("finding severity enum violation")
    if f["status"] not in ["open", "accepted", "resolved"]:
        raise SystemExit("finding status enum violation")

(audit_dir / "findings.json").write_text(json.dumps(findings_doc, indent=2, sort_keys=True) + "\n")
(audit_dir / "audit_report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
print(f"Audit report written: {audit_dir / 'audit_report.json'}")
print(f"Findings written: {audit_dir / 'findings.json'}")
PY
