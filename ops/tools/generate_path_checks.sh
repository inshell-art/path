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

DEPLOY_FILE="${DEPLOY_FILE:-$DEFAULT_DEPLOY_FILE}"

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
  "consumeUnit enforces signed authorization and owner/approval checks|consumeUnit uses nonce-based auth and rejects signature replay|consumeUnit accepts ERC-1271 contract-wallet signatures"
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

invariants = {
    "adapter_wiring_frozen": bool(onchain_ok and onchain_path_invariants.get("adapter_wiring_frozen") is True),
    "sales_caller_frozen_to_adapter": bool(onchain_ok and onchain_path_invariants.get("sales_caller_frozen_to_adapter") is True),
    "epoch_token_coupling_holds": bool(onchain_ok and onchain_path_invariants.get("epoch_token_coupling_holds") is True),
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

from datetime import datetime, timezone

payload = {
    "checks_version": 2,
    "network": os.environ["NETWORK"],
    "lane": os.environ["LANE"],
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "pass": all(required_checks.values()),
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
