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

IFS=$'\t' read -r BUNDLE_HASH INTENT_HASH NETWORK_FROM_RUN LANE_FROM_RUN RUN_ID_FROM_RUN INPUTS_HASH INPUTS_PATH <<EOF_META
$(python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
manifest = json.loads((bundle_dir / "bundle_manifest.json").read_text())
run = json.loads((bundle_dir / "run.json").read_text())
intent = json.loads((bundle_dir / "intent.json").read_text())

bundle_hash = manifest.get("bundle_hash", "")
intent_hash = ""
for item in manifest.get("immutable_files", []):
    if item.get("path") == "intent.json":
        intent_hash = item.get("sha256", "")
        break
if not intent_hash and (bundle_dir / "intent.json").exists():
    intent_hash = hashlib.sha256((bundle_dir / "intent.json").read_bytes()).hexdigest()

inputs_hash = intent.get("inputs_sha256", "")
inputs_path = ""
if inputs_hash:
    candidate = bundle_dir / "inputs.json"
    if not candidate.exists():
        raise SystemExit("intent has inputs_sha256 but bundle inputs.json is missing")
    actual = hashlib.sha256(candidate.read_bytes()).hexdigest()
    if actual != inputs_hash:
        raise SystemExit("inputs hash mismatch: intent.json vs inputs.json")
    inputs_path = str(candidate)


def emit(value):
    return value if value else "__EMPTY__"

print("\t".join([
    emit(bundle_hash),
    emit(intent_hash),
    emit(run.get("network", "")),
    emit(run.get("lane", "")),
    emit(run.get("run_id", "")),
    emit(inputs_hash),
    emit(inputs_path),
]))
PY
)
EOF_META

for field in BUNDLE_HASH INTENT_HASH NETWORK_FROM_RUN LANE_FROM_RUN RUN_ID_FROM_RUN INPUTS_HASH INPUTS_PATH; do
  if [[ "${!field}" == "__EMPTY__" ]]; then
    printf -v "$field" '%s' ""
  fi
done

if [[ -z "$BUNDLE_HASH" || -z "$NETWORK_FROM_RUN" || -z "$LANE_FROM_RUN" ]]; then
  echo "Invalid bundle or run.json" >&2
  exit 2
fi

if [[ -n "$INPUTS_HASH" && -n "$INPUTS_PATH" ]]; then
  echo "Inputs summary (deterministic):"
  INPUTS_PATH="$INPUTS_PATH" python3 - <<'PY'
import json
import os
from pathlib import Path

wrapper = json.loads(Path(os.environ["INPUTS_PATH"]).read_text())
params = wrapper.get("params", {}) if isinstance(wrapper.get("params"), dict) else {}

def pick(key):
    return params.get(key, "<missing>")

rows = [
    ("kind", wrapper.get("kind", "<missing>")),
    ("name", pick("name")),
    ("symbol", pick("symbol")),
    ("paymentToken", pick("paymentToken")),
    ("treasury", pick("treasury")),
    ("openTime", pick("openTime")),
    ("startDelay", pick("startDelay")),
    ("tokenPerEpoch", pick("tokenPerEpoch")),
    ("epochSeconds", pick("epochSeconds")),
]
pricing = pick("pricing")
if isinstance(pricing, (dict, list)):
    pricing = json.dumps(pricing, sort_keys=True)
rows.append(("pricing", pricing))

for key, value in rows:
    if isinstance(value, (dict, list)):
        value = json.dumps(value, sort_keys=True)
    print(f"  {key:16} {value}")
PY
fi

SUFFIX=${BUNDLE_HASH: -8}
if [[ -n "$INPUTS_HASH" ]]; then
  INPUTS_SUFFIX=${INPUTS_HASH: -8}
  PHRASE_REQUIRED="APPROVE $NETWORK_FROM_RUN $LANE_FROM_RUN $SUFFIX IN$INPUTS_SUFFIX"
else
  PHRASE_REQUIRED="APPROVE $NETWORK_FROM_RUN $LANE_FROM_RUN $SUFFIX"
fi

echo "Type exactly: $PHRASE_REQUIRED"
read -r PHRASE

if [[ "$PHRASE" != "$PHRASE_REQUIRED" ]]; then
  echo "Approval phrase mismatch" >&2
  exit 2
fi

APPROVER=${USER:-unknown}
APPROVED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export BUNDLE_HASH INTENT_HASH NETWORK_FROM_RUN LANE_FROM_RUN APPROVER APPROVED_AT RUN_ID_FROM_RUN INPUTS_HASH

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

inputs_hash = os.environ.get("INPUTS_HASH", "").strip()
if inputs_hash:
    approval["inputs_sha256"] = inputs_hash

(bundle_dir / "approval.json").write_text(json.dumps(approval, indent=2, sort_keys=True) + "\n")
print(f"Approval written to {bundle_dir / 'approval.json'}")
PY
