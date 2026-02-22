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

read -r BUNDLE_HASH APPROVAL_HASH NETWORK_FROM_RUN LANE_FROM_RUN <<EOF_HASH
$(python3 - <<'PY'
import json
import os
from pathlib import Path
bundle_dir = Path(os.environ["BUNDLE_DIR"])
manifest = json.loads((bundle_dir / "bundle_manifest.json").read_text())
approval = json.loads((bundle_dir / "approval.json").read_text())
run = json.loads((bundle_dir / "run.json").read_text())
print(manifest.get("bundle_hash", ""), approval.get("bundle_hash", ""), run.get("network", ""), run.get("lane", ""))
PY
)
EOF_HASH

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
  "$ROOT/ops/policy/${NETWORK_FROM_RUN}.policy.example.json"
do
  if [[ -f "$candidate" ]]; then
    POLICY_FILE="$candidate"
    break
  fi
done

if [[ -z "$POLICY_FILE" ]]; then
  echo "Missing policy file for network: $NETWORK_FROM_RUN" >&2
  echo "Expected one of: lane.${NETWORK_FROM_RUN}.json, ${NETWORK_FROM_RUN}.policy.json, lane.${NETWORK_FROM_RUN}.example.json, ${NETWORK_FROM_RUN}.policy.example.json" >&2
  exit 2
fi

read -r REQUIRES_REHEARSAL REHEARSAL_NETWORK <<EOF_REHEARSAL
$(POLICY_FILE="$POLICY_FILE" RUN_LANE="$LANE_FROM_RUN" python3 - <<'PY'
import json
import os
from pathlib import Path
policy_path = Path(os.environ["POLICY_FILE"])
run_lane = os.environ["RUN_LANE"]
policy = json.loads(policy_path.read_text())
lanes = policy.get("lanes", {})
lane = lanes.get(run_lane, {})
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

print("true" if require_flag else "false", proof_network)
PY
)
EOF_REHEARSAL

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

TXS_PATH="$BUNDLE_DIR/txs.json"
SNAP_DIR="$BUNDLE_DIR/snapshots"
mkdir -p "$SNAP_DIR"

APPLIED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export APPLIED_AT TXS_PATH SNAP_DIR
python3 - <<'PY'
import json
import os
from pathlib import Path

applied_at = os.environ["APPLIED_AT"]

(Path(os.environ["TXS_PATH"]).parent).mkdir(parents=True, exist_ok=True)
(Path(os.environ["SNAP_DIR"])).mkdir(parents=True, exist_ok=True)

(Path(os.environ["TXS_PATH"])).write_text(json.dumps({
    "applied_at": applied_at,
    "txs": ["0xSTUB_TX"],
    "notes": "Scaffold stub. Replace with real tx hashes."
}, indent=2, sort_keys=True) + "\n")

(Path(os.environ["SNAP_DIR"]) / "post_state.json").write_text(json.dumps({
    "applied_at": applied_at,
    "notes": "Scaffold stub. Replace with real snapshots."
}, indent=2, sort_keys=True) + "\n")
PY

echo "Apply stub complete. Wrote txs.json and snapshots/ in $BUNDLE_DIR"
