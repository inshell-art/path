#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "apply_bundle.sh accepts no args. Use env NETWORK=... RUN_ID=..." >&2
  exit 2
fi

NETWORK=${NETWORK:-}
RUN_ID=${RUN_ID:-}
BUNDLE_PATH=${BUNDLE_PATH:-}

if [[ "${SIGNING_OS:-}" != "1" ]]; then
  echo "Refusing to run: SIGNING_OS=1 is required." >&2
  exit 2
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Refusing to run: working tree is dirty." >&2
  exit 2
fi

ROOT=$(git rev-parse --show-toplevel)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

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

BUNDLE_PATH="$BUNDLE_DIR" "$SCRIPT_DIR/verify_bundle.sh"

if [[ ! -f "$BUNDLE_DIR/approval.json" ]]; then
  echo "Missing approval.json in $BUNDLE_DIR" >&2
  exit 2
fi

IFS=$'\t' read -r BUNDLE_HASH APPROVAL_HASH NETWORK_FROM_RUN LANE_FROM_RUN INTENT_INPUTS_HASH APPROVAL_INPUTS_HASH RUN_ID_FROM_RUN <<EOF_META
$(python3 - <<'PY'
import json
import os
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
manifest = json.loads((bundle_dir / "bundle_manifest.json").read_text())
approval = json.loads((bundle_dir / "approval.json").read_text())
run = json.loads((bundle_dir / "run.json").read_text())
intent = json.loads((bundle_dir / "intent.json").read_text())


def emit(value):
    return value if value else "__EMPTY__"

print("\t".join([
    emit(manifest.get("bundle_hash", "")),
    emit(approval.get("bundle_hash", "")),
    emit(run.get("network", "")),
    emit(run.get("lane", "")),
    emit(intent.get("inputs_sha256", "")),
    emit(approval.get("inputs_sha256", "")),
    emit(run.get("run_id", "")),
]))
PY
)
EOF_META

for field in BUNDLE_HASH APPROVAL_HASH NETWORK_FROM_RUN LANE_FROM_RUN INTENT_INPUTS_HASH APPROVAL_INPUTS_HASH RUN_ID_FROM_RUN; do
  if [[ "${!field}" == "__EMPTY__" ]]; then
    printf -v "$field" '%s' ""
  fi
done

if [[ -z "$BUNDLE_HASH" || -z "$APPROVAL_HASH" ]]; then
  echo "Invalid manifest or approval" >&2
  exit 2
fi

if [[ "$BUNDLE_HASH" != "$APPROVAL_HASH" ]]; then
  echo "Approval does not match bundle hash" >&2
  exit 2
fi

if [[ -n "$NETWORK" && "$NETWORK" != "$NETWORK_FROM_RUN" ]]; then
  echo "Network mismatch: $NETWORK vs $NETWORK_FROM_RUN" >&2
  exit 2
fi

POLICY_FILE=""
for candidate in \
  "$ROOT/ops/policy/lane.${NETWORK_FROM_RUN}.json" \
  "$ROOT/ops/policy/${NETWORK_FROM_RUN}.policy.json" \
  "$ROOT/ops/policy/lane.${NETWORK_FROM_RUN}.example.json" \
  "$ROOT/ops/policy/${NETWORK_FROM_RUN}.policy.example.json" \
  "$ROOT/policy/${NETWORK_FROM_RUN}.policy.example.json"
do
  if [[ -f "$candidate" ]]; then
    POLICY_FILE="$candidate"
    break
  fi
done

if [[ -z "$POLICY_FILE" ]]; then
  echo "Missing policy file for network: $NETWORK_FROM_RUN" >&2
  echo "Expected one of: lane.${NETWORK_FROM_RUN}.json, ${NETWORK_FROM_RUN}.policy.json, lane.${NETWORK_FROM_RUN}.example.json, ${NETWORK_FROM_RUN}.policy.example.json, policy/${NETWORK_FROM_RUN}.policy.example.json" >&2
  exit 2
fi

IFS=$'\t' read -r REQUIRES_REHEARSAL REHEARSAL_NETWORK REQUIRED_INPUT_KINDS <<EOF_POLICY
$(POLICY_FILE="$POLICY_FILE" RUN_LANE="$LANE_FROM_RUN" python3 - <<'PY'
import json
import os
from pathlib import Path

policy = json.loads(Path(os.environ["POLICY_FILE"]).read_text())
run_lane = os.environ["RUN_LANE"]
lane = ((policy.get("lanes") or {}).get(run_lane) or {})

# Rehearsal gate (canonical + backward-compat)
gates = lane.get("gates", {})
if not isinstance(gates, dict):
    gates = {}

new_keys_present = "require_rehearsal_proof" in gates or "rehearsal_proof_network" in gates
if new_keys_present:
    require_flag = bool(gates.get("require_rehearsal_proof", False))
    proof_network = str(gates.get("rehearsal_proof_network", "devnet")).strip().lower()
    if require_flag and proof_network not in {"devnet", "sepolia"}:
        raise SystemExit(f"invalid rehearsal_proof_network for lane '{run_lane}': {proof_network}")
    if not require_flag:
        proof_network = ""
else:
    devnet_flag = bool(lane.get("requires_devnet_rehearsal_proof", False) or gates.get("require_devnet_rehearsal_proof", False))
    sepolia_flag = bool(lane.get("requires_sepolia_rehearsal_proof", False) or gates.get("require_sepolia_rehearsal_proof", False))
    require_flag = devnet_flag or sepolia_flag
    if devnet_flag:
        proof_network = "devnet"
    elif sepolia_flag:
        proof_network = "sepolia"
    else:
        proof_network = ""

required_inputs = lane.get("required_inputs", [])
if required_inputs is None:
    required_inputs = []
if not isinstance(required_inputs, list):
    raise SystemExit("policy lanes.<lane>.required_inputs must be a list when set")

kinds = []
for item in required_inputs:
    if isinstance(item, dict) and isinstance(item.get("kind"), str) and item.get("kind").strip():
        kinds.append(item["kind"].strip())

print("\t".join([
    "true" if require_flag else "false",
    proof_network if proof_network else "__EMPTY__",
    ",".join(kinds) if kinds else "__EMPTY__",
]))
PY
)
EOF_POLICY

if [[ "$REHEARSAL_NETWORK" == "__EMPTY__" ]]; then
  REHEARSAL_NETWORK=""
fi
if [[ "$REQUIRED_INPUT_KINDS" == "__EMPTY__" ]]; then
  REQUIRED_INPUT_KINDS=""
fi

if [[ "$NETWORK_FROM_RUN" == "mainnet" && "$REQUIRES_REHEARSAL" == "true" ]]; then
  PROOF_RUN_ID="${REHEARSAL_PROOF_RUN_ID:-${DEVNET_PROOF_RUN_ID:-${SEPOLIA_PROOF_RUN_ID:-}}}"
  if [[ -z "$PROOF_RUN_ID" ]]; then
    echo "Missing rehearsal proof run id for mainnet apply. Set REHEARSAL_PROOF_RUN_ID (fallbacks: DEVNET_PROOF_RUN_ID, SEPOLIA_PROOF_RUN_ID)." >&2
    exit 2
  fi
  if [[ -z "$REHEARSAL_NETWORK" ]]; then
    echo "Policy requested rehearsal proof but rehearsal_proof_network is empty for lane: $LANE_FROM_RUN" >&2
    exit 2
  fi
  PROOF_DIR="$ROOT/bundles/$REHEARSAL_NETWORK/$PROOF_RUN_ID"
  if [[ ! -f "$PROOF_DIR/txs.json" || ! -f "$PROOF_DIR/postconditions.json" ]]; then
    echo "Rehearsal proof missing txs.json or postconditions.json in $REHEARSAL_NETWORK bundle: $PROOF_DIR" >&2
    exit 2
  fi
fi

INPUTS_FILE_USED=""
INPUTS_SHA256_USED=""
if [[ -n "$REQUIRED_INPUT_KINDS" ]]; then
  EXPECTED_INPUTS_PATH="$BUNDLE_DIR/inputs.json"
  if [[ ! -f "$EXPECTED_INPUTS_PATH" ]]; then
    echo "inputs.json required by policy but missing: $EXPECTED_INPUTS_PATH" >&2
    exit 2
  fi

  EXTERNAL_INPUTS_FILE="${INPUTS_FILE:-}"
  if [[ -n "$EXTERNAL_INPUTS_FILE" && "$EXTERNAL_INPUTS_FILE" != "$EXPECTED_INPUTS_PATH" ]]; then
    echo "External INPUTS_FILE override is not allowed. Expected INPUTS_FILE=$EXPECTED_INPUTS_PATH" >&2
    exit 2
  fi

  export INPUTS_FILE="$EXPECTED_INPUTS_PATH"

  IFS=$'\t' read -r ACTUAL_INPUTS_HASH WRAPPER_KIND WRAPPER_NETWORK WRAPPER_LANE WRAPPER_RUN_ID <<EOF_INPUTS
$(INPUTS_PATH="$EXPECTED_INPUTS_PATH" python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

inputs_path = Path(os.environ["INPUTS_PATH"])
wrapper = json.loads(inputs_path.read_text())
actual = hashlib.sha256(inputs_path.read_bytes()).hexdigest()

def emit(v):
    return v if v else "__EMPTY__"

print("\t".join([
    emit(actual),
    emit(wrapper.get("kind", "")),
    emit(wrapper.get("network", "")),
    emit(wrapper.get("lane", "")),
    emit(wrapper.get("run_id", "")),
]))
PY
)
EOF_INPUTS

  for field in ACTUAL_INPUTS_HASH WRAPPER_KIND WRAPPER_NETWORK WRAPPER_LANE WRAPPER_RUN_ID; do
    if [[ "${!field}" == "__EMPTY__" ]]; then
      printf -v "$field" '%s' ""
    fi
  done

  if [[ -z "$INTENT_INPUTS_HASH" ]]; then
    echo "inputs required but intent.json.inputs_sha256 is missing" >&2
    exit 2
  fi
  if [[ "$ACTUAL_INPUTS_HASH" != "$INTENT_INPUTS_HASH" ]]; then
    echo "inputs hash mismatch: inputs.json vs intent.json" >&2
    exit 2
  fi
  if [[ -z "$APPROVAL_INPUTS_HASH" ]]; then
    echo "inputs required but approval.json.inputs_sha256 is missing" >&2
    exit 2
  fi
  if [[ "$ACTUAL_INPUTS_HASH" != "$APPROVAL_INPUTS_HASH" ]]; then
    echo "inputs hash mismatch: inputs.json vs approval.json" >&2
    exit 2
  fi

  IFS=',' read -r -a REQUIRED_KINDS_ARRAY <<< "$REQUIRED_INPUT_KINDS"
  KIND_MATCH=0
  for k in "${REQUIRED_KINDS_ARRAY[@]}"; do
    if [[ "$WRAPPER_KIND" == "$k" ]]; then
      KIND_MATCH=1
      break
    fi
  done
  if [[ "$KIND_MATCH" != "1" ]]; then
    echo "inputs kind '$WRAPPER_KIND' not allowed; expected one of: $REQUIRED_INPUT_KINDS" >&2
    exit 2
  fi

  if [[ "$WRAPPER_NETWORK" != "$NETWORK_FROM_RUN" || "$WRAPPER_LANE" != "$LANE_FROM_RUN" || "$WRAPPER_RUN_ID" != "$RUN_ID_FROM_RUN" ]]; then
    echo "inputs wrapper coherence mismatch with run.json (network/lane/run_id)" >&2
    exit 2
  fi

  INPUTS_FILE_USED="$EXPECTED_INPUTS_PATH"
  INPUTS_SHA256_USED="$ACTUAL_INPUTS_HASH"
else
  if [[ -n "$INTENT_INPUTS_HASH" || -n "$APPROVAL_INPUTS_HASH" ]]; then
    echo "inputs hash present in artifacts but policy does not declare required_inputs for this lane" >&2
    exit 2
  fi
fi

TXS_PATH="$BUNDLE_DIR/txs.json"
SNAP_DIR="$BUNDLE_DIR/snapshots"
mkdir -p "$SNAP_DIR"

APPLIED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export APPLIED_AT TXS_PATH SNAP_DIR INPUTS_FILE_USED INPUTS_SHA256_USED
python3 - <<'PY'
import json
import os
from pathlib import Path

applied_at = os.environ["APPLIED_AT"]

payload = {
    "applied_at": applied_at,
    "txs": ["0xSTUB_TX"],
    "notes": "Scaffold stub. Replace with real tx hashes.",
}

inputs_file = os.environ.get("INPUTS_FILE_USED", "").strip()
inputs_hash = os.environ.get("INPUTS_SHA256_USED", "").strip()
if inputs_file:
    payload["inputs_file"] = inputs_file
if inputs_hash:
    payload["inputs_sha256"] = inputs_hash

(Path(os.environ["TXS_PATH"])).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")

snapshot_payload = {
    "applied_at": applied_at,
    "notes": "Scaffold stub. Replace with real snapshots.",
}
if inputs_file:
    snapshot_payload["inputs_file"] = inputs_file
if inputs_hash:
    snapshot_payload["inputs_sha256"] = inputs_hash

(Path(os.environ["SNAP_DIR"]) / "post_state.json").write_text(json.dumps(snapshot_payload, indent=2, sort_keys=True) + "\n")
PY

echo "Apply stub complete. Wrote txs.json and snapshots/ in $BUNDLE_DIR"
