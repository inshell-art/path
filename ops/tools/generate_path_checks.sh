#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}
LANE=${LANE:-}
OUT_FILE=${OUT_FILE:-}

if [[ -z "$NETWORK" || -z "$LANE" || -z "$OUT_FILE" ]]; then
  echo "Usage: NETWORK=<...> LANE=<...> OUT_FILE=<path> $0" >&2
  exit 2
fi

ROOT=$(git rev-parse --show-toplevel)
mkdir -p "$(dirname "$OUT_FILE")"

case "$NETWORK" in
  devnet)
    HARDHAT_NETWORK="${CHECKS_EVM_NETWORK:-localhost}"
    DEFAULT_DEPLOY_FILE="$ROOT/evm/deployments/localhost-eth.json"
    DEFAULT_ALLOW_WRITE_HANDSHAKE=1
    ;;
  sepolia)
    HARDHAT_NETWORK="${CHECKS_EVM_NETWORK:-sepolia}"
    DEFAULT_DEPLOY_FILE="$ROOT/evm/deployments/sepolia-eth.json"
    DEFAULT_ALLOW_WRITE_HANDSHAKE=0
    ;;
  mainnet)
    HARDHAT_NETWORK="${CHECKS_EVM_NETWORK:-mainnet}"
    DEFAULT_DEPLOY_FILE="$ROOT/evm/deployments/mainnet-eth.json"
    DEFAULT_ALLOW_WRITE_HANDSHAKE=0
    ;;
  *)
    echo "Unsupported NETWORK for path checks: $NETWORK" >&2
    exit 2
    ;;
esac

case "$OUT_FILE" in
  */bundles/"$NETWORK"/*)
    BUNDLE_DIR="$(dirname "$OUT_FILE")"
    case "$NETWORK" in
      devnet)
        DEFAULT_DEPLOY_FILE="$BUNDLE_DIR/deployments/localhost-eth.json"
        ;;
      sepolia)
        DEFAULT_DEPLOY_FILE="$BUNDLE_DIR/deployments/sepolia-eth.json"
        ;;
      mainnet)
        DEFAULT_DEPLOY_FILE="$BUNDLE_DIR/deployments/mainnet-eth.json"
        ;;
    esac
    ;;
esac

DEPLOY_FILE="${DEPLOY_FILE:-$DEFAULT_DEPLOY_FILE}"

CAMPAIGN_WRAPPER="${CAMPAIGN_INPUTS_FILE:-}"
if [[ -z "$CAMPAIGN_WRAPPER" ]]; then
  OUT_DIR="$(dirname "$OUT_FILE")"
  if [[ -f "$OUT_DIR/inputs.json" ]]; then
    CAMPAIGN_WRAPPER="$OUT_DIR/inputs.json"
  fi
fi

CAMPAIGN_KIND=""
if [[ -n "$CAMPAIGN_WRAPPER" && -f "$CAMPAIGN_WRAPPER" ]]; then
  CAMPAIGN_KIND=$(CAMPAIGN_WRAPPER="$CAMPAIGN_WRAPPER" python3 - <<'PY'
import json
import os
from pathlib import Path

payload = json.loads(Path(os.environ["CAMPAIGN_WRAPPER"]).read_text())
print(payload.get("kind", ""))
PY
)
fi

if [[ "$CAMPAIGN_KIND" == "path_campaign_phase_a" || "$CAMPAIGN_KIND" == "path_campaign_phase_b" ]]; then
  PARAMS_TMP="$(mktemp)"
  CAMPAIGN_LOG="${OUT_FILE%.json}.campaign.log"
  cleanup_campaign() {
    rm -f "$PARAMS_TMP"
  }
  trap cleanup_campaign EXIT

  CAMPAIGN_WRAPPER="$CAMPAIGN_WRAPPER" PARAMS_TMP="$PARAMS_TMP" python3 - <<'PY'
import json
import os
from pathlib import Path

wrapper = json.loads(Path(os.environ["CAMPAIGN_WRAPPER"]).read_text())
params = wrapper.get("params")
if not isinstance(params, dict):
    raise SystemExit("campaign inputs wrapper params must be an object")
Path(os.environ["PARAMS_TMP"]).write_text(json.dumps(params, indent=2, sort_keys=True) + "\n")
PY

  CAMPAIGN_MODE="predeploy"
  CAMPAIGN_RECEIPT_FILE=""
  if [[ -f "$DEPLOY_FILE" ]]; then
    CAMPAIGN_MODE="postdeploy"
    CAMPAIGN_RECEIPT_FILE="$DEPLOY_FILE"
  fi
  CAMPAIGN_CHECKPOINT_FILE="${PATH_CAMPAIGN_CHECKPOINT_FILE:-}"
  if [[ -z "$CAMPAIGN_CHECKPOINT_FILE" ]]; then
    case "$CAMPAIGN_KIND" in
      path_campaign_phase_a)
        CAMPAIGN_CHECKPOINT_FILE="$(dirname "$DEPLOY_FILE")/path-phase-a-checkpoint.json"
        ;;
      path_campaign_phase_b)
        CAMPAIGN_CHECKPOINT_FILE="$(dirname "$DEPLOY_FILE")/path-phase-b-checkpoint.json"
        ;;
    esac
  fi
  CAMPAIGN_SOURCE_BUNDLE_DIGEST="${PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST:-}"
  if [[ -z "$CAMPAIGN_SOURCE_BUNDLE_DIGEST" && -n "${BUNDLE_DIR:-}" && -f "$BUNDLE_DIR/bundle_manifest.json" ]]; then
    CAMPAIGN_SOURCE_BUNDLE_DIGEST=$(jq -r '.bundle_hash // empty' "$BUNDLE_DIR/bundle_manifest.json")
  fi

  CAMPAIGN_POLICY_FILE="${POLICY_FILE:-}"
  if [[ -z "$CAMPAIGN_POLICY_FILE" ]]; then
    for candidate in \
      "$ROOT/ops/policy/lane.${NETWORK}.json" \
      "$ROOT/ops/policy/${NETWORK}.policy.json" \
      "$ROOT/ops/policy/lane.${NETWORK}.example.json" \
      "$ROOT/ops/policy/${NETWORK}.policy.example.json"
    do
      if [[ -f "$candidate" ]]; then
        CAMPAIGN_POLICY_FILE="$candidate"
        break
      fi
    done
  fi
  if [[ -z "$CAMPAIGN_POLICY_FILE" ]]; then
    echo "Missing campaign policy for $NETWORK" >&2
    exit 2
  fi

  case "$NETWORK" in
    devnet) CAMPAIGN_RPC_URL="${PATH_LOCAL_RPC_URL:-http://127.0.0.1:8546}" ;;
    sepolia) CAMPAIGN_RPC_URL="${SEPOLIA_RPC_URL:-}" ;;
    mainnet) CAMPAIGN_RPC_URL="${MAINNET_RPC_URL:-}" ;;
  esac
  if [[ -z "$CAMPAIGN_RPC_URL" ]]; then
    echo "Missing RPC URL for PATH campaign $NETWORK checks" >&2
    exit 2
  fi

  IFS=$'\t' read -r CAMPAIGN_EXPECTED_SIGNER CAMPAIGN_RPC_ALLOWED <<EOF_CAMPAIGN_POLICY
$(CAMPAIGN_POLICY_FILE="$CAMPAIGN_POLICY_FILE" CAMPAIGN_RPC_URL="$CAMPAIGN_RPC_URL" NETWORK="$NETWORK" LANE="$LANE" python3 - <<'PY'
import json
import os
from pathlib import Path
from urllib.parse import urlparse

policy = json.loads(Path(os.environ["CAMPAIGN_POLICY_FILE"]).read_text())
lane = ((policy.get("lanes") or {}).get(os.environ["LANE"]) or {})
aliases = lane.get("allowed_signers") or []
if len(aliases) != 1:
    raise SystemExit("PATH campaign deploy lane requires exactly one allowed signer alias")
signer = str((policy.get("signer_alias_map") or {}).get(aliases[0], "")).strip()
if not signer:
    raise SystemExit(f"Missing signer_alias_map address for {aliases[0]}")

host = (urlparse(os.environ["CAMPAIGN_RPC_URL"]).hostname or "").lower()
if not host:
    raise SystemExit("Unable to parse campaign RPC host")
if os.environ["NETWORK"] == "devnet":
    allowed = host in {"127.0.0.1", "localhost", "::1"}
else:
    allowlist = {str(item).strip().lower() for item in policy.get("rpc_host_allowlist") or []}
    allowed = host in allowlist
print(f"{signer}\t{'1' if allowed else '0'}")
PY
)
EOF_CAMPAIGN_POLICY
  if [[ "$CAMPAIGN_RPC_ALLOWED" != "1" ]]; then
    echo "Campaign RPC host is not policy-allowlisted" >&2
    exit 2
  fi

  if (
    cd "$ROOT/evm"
    DEPLOY_PARAMS_FILE="$PARAMS_TMP" \
      PATH_CAMPAIGN_INPUT_KIND="$CAMPAIGN_KIND" \
      PATH_CAMPAIGN_CHECK_MODE="$CAMPAIGN_MODE" \
      PATH_CAMPAIGN_RECEIPT_FILE="$CAMPAIGN_RECEIPT_FILE" \
      PATH_CAMPAIGN_CHECKPOINT_FILE="$CAMPAIGN_CHECKPOINT_FILE" \
      PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST="$CAMPAIGN_SOURCE_BUNDLE_DIGEST" \
      PATH_CAMPAIGN_POLICY_SIGNER_ADDRESS="$CAMPAIGN_EXPECTED_SIGNER" \
      PATH_CAMPAIGN_RPC_HOST_ALLOWED="$CAMPAIGN_RPC_ALLOWED" \
      PATH_CAMPAIGN_NETWORK_LABEL="$NETWORK" \
      PATH_CAMPAIGN_LANE_LABEL="$LANE" \
      PATH_CAMPAIGN_CHECKS_OUT="$OUT_FILE" \
      npx hardhat run scripts/check-path-campaign-state.js --network "$HARDHAT_NETWORK" \
      >"$CAMPAIGN_LOG" 2>&1
  ); then
    cat "$OUT_FILE"
    exit 0
  else
    campaign_rc=$?
  fi
  CAMPAIGN_KIND="$CAMPAIGN_KIND" CAMPAIGN_MODE="$CAMPAIGN_MODE" CAMPAIGN_LOG="$CAMPAIGN_LOG" OUT_FILE="$OUT_FILE" NETWORK="$NETWORK" LANE="$LANE" CAMPAIGN_RC="$campaign_rc" python3 - <<'PY'
import json
import os
from pathlib import Path

payload = {
    "checks_version": 2,
    "network": os.environ["NETWORK"],
    "lane": os.environ["LANE"],
    "phase": os.environ["CAMPAIGN_MODE"],
    "deployment_present": os.environ["CAMPAIGN_MODE"] == "postdeploy",
    "pass": False,
    "required_checks": {
        "chain_id": False,
        "rpc_allowlist": False,
        "signer_allowlist": False,
        "bytecode_hash": False,
        "proxy_implementation": False,
        "path_invariants": False,
    },
    "path_invariants": {"campaign_pre_or_postconditions": False},
    "details": {
        "inputKind": os.environ["CAMPAIGN_KIND"],
        "exitCode": int(os.environ["CAMPAIGN_RC"]),
        "log": os.environ["CAMPAIGN_LOG"],
    },
}
Path(os.environ["OUT_FILE"]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
  exit "$campaign_rc"
fi

if [[ -z "${ALLOW_WRITE_HANDSHAKE:-}" ]]; then
  HANDSHAKE_FROM_POLICY=""
  if [[ -n "${POLICY_FILE:-}" && -f "${POLICY_FILE}" ]]; then
    HANDSHAKE_FROM_POLICY=$(POLICY_FILE="${POLICY_FILE}" python3 - <<'PY'
import json
import os
from pathlib import Path

policy = json.loads(Path(os.environ["POLICY_FILE"]).read_text())
mode = str(policy.get("path", {}).get("sale_handshake", {}).get("mode", "")).strip().lower()
if mode == "execute_bid":
    print("1")
elif mode == "skip":
    print("0")
else:
    print("")
PY
)
  fi
  if [[ -n "$HANDSHAKE_FROM_POLICY" ]]; then
    ALLOW_WRITE_HANDSHAKE="$HANDSHAKE_FROM_POLICY"
  else
    ALLOW_WRITE_HANDSHAKE="$DEFAULT_ALLOW_WRITE_HANDSHAKE"
  fi
fi

ONCHAIN_TMP="$(mktemp)"
ONCHAIN_LOG="${OUT_FILE%.json}.onchain.log"
SIGNED_LOG="${OUT_FILE%.json}.signed-consume.log"
ONCHAIN_OK=0
ONCHAIN_EXIT=0

if (
  cd "$ROOT/evm"
  DEPLOY_FILE="$DEPLOY_FILE" LANE="$LANE" POLICY_FILE="${POLICY_FILE:-}" ALLOW_WRITE_HANDSHAKE="$ALLOW_WRITE_HANDSHAKE" \
    npx hardhat run scripts/check-path-invariants-local-eth.js --network "$HARDHAT_NETWORK" >"$ONCHAIN_TMP" 2>"$ONCHAIN_LOG"
); then
  ONCHAIN_OK=1
else
  ONCHAIN_EXIT=$?
fi

SIGNED_OK=0
SIGNED_EXIT=0
SIGNED_CMD=(
  npm --prefix "$ROOT/evm" run test --
  test/pathNft.behavior.test.js
  --grep
  "consumeUnit enforces signed authorization and current-owner checks|permission epoch prevents stale signatures from reviving after a transfer round trip|consumeUnit uses nonce-based auth and rejects signature replay|consumeUnit accepts ERC-1271 contract-wallet signatures"
)
if "${SIGNED_CMD[@]}" >"$SIGNED_LOG" 2>&1; then
  SIGNED_OK=1
else
  SIGNED_EXIT=$?
fi

export NETWORK LANE OUT_FILE ONCHAIN_TMP ONCHAIN_LOG ONCHAIN_OK ONCHAIN_EXIT SIGNED_LOG SIGNED_OK SIGNED_EXIT ROOT HARDHAT_NETWORK DEPLOY_FILE
python3 - <<'PY'
import json
import os
from pathlib import Path

out_file = Path(os.environ["OUT_FILE"])
onchain_tmp = Path(os.environ["ONCHAIN_TMP"])
onchain_log = Path(os.environ["ONCHAIN_LOG"])
signed_log = Path(os.environ["SIGNED_LOG"])

onchain_ok = os.environ["ONCHAIN_OK"] == "1"
signed_ok = os.environ["SIGNED_OK"] == "1"
onchain_exit = int(os.environ["ONCHAIN_EXIT"])
signed_exit = int(os.environ["SIGNED_EXIT"])

onchain_report = {}
if onchain_ok:
    try:
        onchain_report = json.loads(onchain_tmp.read_text())
    except Exception as exc:
        onchain_ok = False
        onchain_exit = 1
        onchain_report = {"error": f"failed to parse on-chain report: {exc}"}
else:
    onchain_report = {
        "error": "on-chain probe failed",
        "hint": f"see log: {onchain_log}"
    }

onchain_required_checks = onchain_report.get("requiredChecks", {})
onchain_path_invariants = onchain_report.get("pathInvariants", {})
phase = onchain_report.get("phase", "unknown")
deployment_present = onchain_report.get("deploymentPresent") is True

def invariant_ok(*names):
    return bool(onchain_ok and any(onchain_path_invariants.get(name) is True for name in names))

public_minter_frozen = invariant_ok(
    "public_minter_frozen_to_path_pulse_adapter",
    "sales_caller_frozen_to_adapter",
)
epoch_token_coupling = invariant_ok(
    "epoch_token_coupling_defined",
    "epoch_token_coupling_holds",
)

invariants = {
    "adapter_wiring_frozen": bool(onchain_ok and onchain_path_invariants.get("adapter_wiring_frozen") is True),
    "sales_caller_frozen_to_adapter": public_minter_frozen,
    "public_minter_frozen_to_path_pulse_adapter": public_minter_frozen,
    "epoch_token_coupling_holds": epoch_token_coupling,
    "epoch_token_coupling_defined": epoch_token_coupling,
    "role_owner_hygiene_ok": bool(onchain_ok and onchain_path_invariants.get("role_owner_hygiene_ok") is True),
    "auction_config_matches": bool(onchain_ok and onchain_path_invariants.get("auction_config_matches") is True),
    "sale_handshake_ok": bool(onchain_ok and onchain_path_invariants.get("sale_handshake_ok") is True),
    "movement_config_policy_ok": bool(onchain_ok and onchain_path_invariants.get("movement_config_policy_ok") is True),
    "signed_consume_path_ok": bool(signed_ok),
}

required_checks = {
    "chain_id": bool(onchain_ok and onchain_required_checks.get("chain_id") is True),
    "rpc_allowlist": bool(onchain_ok and onchain_required_checks.get("rpc_allowlist") is True),
    "signer_allowlist": bool(onchain_ok and onchain_required_checks.get("signer_allowlist") is True),
    "bytecode_hash": bool(onchain_ok and onchain_required_checks.get("bytecode_hash") is True),
    "proxy_implementation": bool(onchain_ok and onchain_required_checks.get("proxy_implementation") is True),
}
required_checks["path_invariants"] = all(invariants.values())

if phase == "predeploy" and os.environ["LANE"] == "deploy":
    predeploy_gate = all([
        required_checks.get("chain_id") is True,
        required_checks.get("rpc_allowlist") is True,
        required_checks.get("signer_allowlist") is True,
    ])
else:
    predeploy_gate = all(required_checks.values())

from datetime import datetime, timezone

payload = {
    "checks_version": 2,
    "network": os.environ["NETWORK"],
    "lane": os.environ["LANE"],
    "phase": phase,
    "deployment_present": deployment_present,
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "pass": predeploy_gate,
    "required_checks": required_checks,
    "path_invariants": invariants,
    "sources": {
        "onchain": {
            "script": "evm/scripts/check-path-invariants-local-eth.js",
            "network": os.environ.get("HARDHAT_NETWORK", ""),
            "exit_code": onchain_exit,
            "log": str(onchain_log),
            "deploy_file": os.environ.get("DEPLOY_FILE", ""),
        },
        "signed_consume_test": {
            "suite": "evm/test/pathNft.behavior.test.js",
            "grep": "signed authorization / nonce replay / ERC-1271",
            "exit_code": signed_exit,
            "log": str(signed_log),
        },
    },
    "details": {
        "onchain_report": onchain_report,
    },
}

out_file.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
print(f"Wrote {out_file}")
PY

rm -f "$ONCHAIN_TMP"
