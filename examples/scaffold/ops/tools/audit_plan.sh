#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}
AUDIT_ID=${AUDIT_ID:-}
RUN_IDS=${RUN_IDS:-}
AUDITOR=${AUDITOR:-${USER:-unknown}}
TIME_FROM=${TIME_FROM:-}
TIME_TO=${TIME_TO:-}
AUDIT_SCOPE=${AUDIT_SCOPE:-lane-process-controls}

if [[ -z "$NETWORK" || -z "$AUDIT_ID" ]]; then
  echo "Usage: NETWORK=<devnet|sepolia|mainnet> AUDIT_ID=<id> [RUN_IDS=r1,r2] $0" >&2
  exit 2
fi

case "$NETWORK" in
  devnet|sepolia|mainnet) ;;
  *) echo "Invalid NETWORK: $NETWORK" >&2; exit 2 ;;
esac

ROOT=$(git rev-parse --show-toplevel)
AUDIT_DIR="$ROOT/audits/$NETWORK/$AUDIT_ID"
mkdir -p "$AUDIT_DIR"

if [[ -z "$TIME_TO" ]]; then
  TIME_TO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi
if [[ -z "$TIME_FROM" ]]; then
  TIME_FROM=$(date -u -v-30d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "30 days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "1970-01-01T00:00:00Z")
fi

GIT_COMMIT=$(git rev-parse HEAD)

POLICY_FILE="$ROOT/ops/policy/audit.policy.json"
if [[ ! -f "$POLICY_FILE" ]]; then
  POLICY_FILE="$ROOT/ops/policy/audit.policy.example.json"
fi
if [[ ! -f "$POLICY_FILE" ]]; then
  POLICY_FILE="$ROOT/policy/audit.policy.example.json"
fi

export ROOT AUDIT_DIR NETWORK AUDIT_ID RUN_IDS AUDITOR TIME_FROM TIME_TO AUDIT_SCOPE GIT_COMMIT POLICY_FILE

python3 - <<'PY'
import json
import os
from pathlib import Path

root = Path(os.environ["ROOT"])
audit_dir = Path(os.environ["AUDIT_DIR"])
network = os.environ["NETWORK"]
audit_id = os.environ["AUDIT_ID"]
run_ids_env = os.environ.get("RUN_IDS", "").strip()
auditor = os.environ["AUDITOR"]
time_from = os.environ["TIME_FROM"]
time_to = os.environ["TIME_TO"]
scope = os.environ["AUDIT_SCOPE"]
repo_commit = os.environ["GIT_COMMIT"]
policy_file = os.environ.get("POLICY_FILE", "")

if run_ids_env:
    run_ids = [x.strip() for x in run_ids_env.split(",") if x.strip()]
else:
    bundle_root = root / "bundles" / network
    if bundle_root.exists():
        run_ids = sorted([p.name for p in bundle_root.iterdir() if p.is_dir()])
    else:
        run_ids = []

controls = [
    "AUD-001", "AUD-002", "AUD-003", "AUD-004", "AUD-005",
    "AUD-006", "AUD-007", "AUD-008", "AUD-009", "AUD-010"
]
if policy_file and Path(policy_file).exists():
    policy = json.loads(Path(policy_file).read_text())
    by_net = policy.get("required_controls", {})
    configured = by_net.get(network)
    if isinstance(configured, list) and configured:
        controls = configured

plan = {
    "audit_id": audit_id,
    "network": network,
    "scope": {
        "module": "ops-lanes-audit",
        "mode": scope
    },
    "time_window": {
        "from": time_from,
        "to": time_to
    },
    "run_ids": run_ids,
    "controls": controls,
    "auditor": auditor,
    "repo_commit": repo_commit,
    "generated_at": time_to
}

schema_path = root / "schemas/audit_plan.schema.json"
if schema_path.exists():
    schema = json.loads(schema_path.read_text())
else:
    schema = {
        "required": [
            "audit_id",
            "network",
            "scope",
            "time_window",
            "run_ids",
            "controls",
            "auditor",
            "repo_commit",
            "generated_at"
        ],
        "properties": {
            "network": {
                "enum": ["devnet", "sepolia", "mainnet"]
            }
        }
    }

for key in schema.get("required", []):
    if key not in plan:
        raise SystemExit(f"audit_plan missing required key: {key}")

network_enum = (
    schema.get("properties", {})
    .get("network", {})
    .get("enum", [])
)
if network_enum and plan["network"] not in network_enum:
    raise SystemExit(f"audit_plan network enum violation: {plan['network']}")

(audit_dir / "audit_plan.json").write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
print(f"Audit plan written: {audit_dir / 'audit_plan.json'}")
PY
