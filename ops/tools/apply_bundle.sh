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
APPLY_EXECUTION_MODE="stub"
DEPLOY_FILE=""
DEPLOY_LOG=""
DEPLOY_COMMAND=""

if [[ "$LANE_FROM_RUN" == "deploy" ]]; then
  mkdir -p "$BUNDLE_DIR/deployments"
  DEPLOY_CMD=()

  case "$NETWORK_FROM_RUN" in
    devnet)
      DEPLOY_FILE="$BUNDLE_DIR/deployments/localhost-eth.json"
      DEPLOY_LOG="$BUNDLE_DIR/deploy.deploy.log"
      DEPLOY_CMD=(npm run evm:deploy:local:eth)
      ;;
    sepolia)
      DEPLOY_FILE="$BUNDLE_DIR/deployments/sepolia-eth.json"
      DEPLOY_LOG="$BUNDLE_DIR/deploy.deploy.log"
      DEPLOY_CMD=(npm --prefix evm exec -- hardhat run scripts/deploy-local-eth.js --network sepolia)
      ;;
    mainnet)
      DEPLOY_FILE="$BUNDLE_DIR/deployments/mainnet-eth.json"
      DEPLOY_LOG="$BUNDLE_DIR/deploy.deploy.log"
      DEPLOY_CMD=(npm --prefix evm exec -- hardhat run scripts/deploy-local-eth.js --network mainnet)
      ;;
  esac

  if [[ "${#DEPLOY_CMD[@]}" -gt 0 ]]; then
    DEPLOY_COMMAND="${DEPLOY_CMD[*]}"
    echo "Executing deploy lane command: ${DEPLOY_COMMAND}"
    DEPLOY_OUT_FILE="$DEPLOY_FILE" "${DEPLOY_CMD[@]}" | tee "$DEPLOY_LOG"
    APPLY_EXECUTION_MODE="deployed"
  fi
fi

export APPLIED_AT TXS_PATH SNAP_DIR APPLY_EXECUTION_MODE DEPLOY_FILE DEPLOY_LOG DEPLOY_COMMAND NETWORK_FROM_RUN LANE_FROM_RUN
python3 - <<'PY'
import json
import os
from pathlib import Path

applied_at = os.environ["APPLIED_AT"]
execution_mode = os.environ.get("APPLY_EXECUTION_MODE", "stub")
deployment_file = os.environ.get("DEPLOY_FILE", "")
deploy_log = os.environ.get("DEPLOY_LOG", "")
deploy_command = os.environ.get("DEPLOY_COMMAND", "")
network = os.environ.get("NETWORK_FROM_RUN", "")
lane = os.environ.get("LANE_FROM_RUN", "")

(Path(os.environ["TXS_PATH"]).parent).mkdir(parents=True, exist_ok=True)
(Path(os.environ["SNAP_DIR"])).mkdir(parents=True, exist_ok=True)

deployment = {}
if deployment_file and Path(deployment_file).exists():
    try:
        deployment = json.loads(Path(deployment_file).read_text())
    except Exception:
        deployment = {}

txs = []
if execution_mode == "deployed":
    deploy_txs = deployment.get("deployTxs", {})
    for _, tx_hash in deploy_txs.items():
        if isinstance(tx_hash, str) and tx_hash.startswith("0x") and len(tx_hash) > 2:
            txs.append(tx_hash)
else:
    txs = ["0xSTUB_TX"]

txs_payload = {
    "applied_at": applied_at,
    "network": network,
    "lane": lane,
    "execution_mode": execution_mode,
    "txs": txs,
    "notes": "Deploy lane executes configured deploy command and records deployment tx hashes when available." if execution_mode == "deployed" else "Scaffold stub. Replace with real tx hashes."
}
if deployment_file:
    txs_payload["deployment_file"] = deployment_file
if deploy_log:
    txs_payload["deploy_log"] = deploy_log
if deploy_command:
    txs_payload["deploy_command"] = deploy_command

(Path(os.environ["TXS_PATH"])).write_text(json.dumps(txs_payload, indent=2, sort_keys=True) + "\n")

snapshot_payload = {
    "applied_at": applied_at,
    "network": network,
    "lane": lane,
    "execution_mode": execution_mode,
    "notes": "Contains post-apply deployment snapshot."
}
if deployment:
    snapshot_payload["deployment"] = {
        "network": deployment.get("network"),
        "chainId": deployment.get("chainId"),
        "deployer": deployment.get("deployer"),
        "contracts": deployment.get("contracts", {})
    }

(Path(os.environ["SNAP_DIR"]) / "post_state.json").write_text(json.dumps(snapshot_payload, indent=2, sort_keys=True) + "\n")
PY

echo "Apply complete. Wrote txs.json and snapshots/ in $BUNDLE_DIR"
