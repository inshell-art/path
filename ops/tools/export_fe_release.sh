#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

usage() {
  cat <<'USAGE' >&2
Usage:
  npm run ops:export:fe-release -- --network <devnet|sepolia|mainnet> --run-id <id> [--rpc-url <url>] [--out-dir <dir>] [--release-tier <temporary|candidate|final>] [--audit-id <id>] [--force]

Inputs may also be provided by env:
  NETWORK, RUN_ID, RPC_URL, RELEASE_TIER, AUDIT_ID, OUT_DIR

RPC resolution order:
  --rpc-url -> RPC_URL -> <NETWORK>_RPC_URL
USAGE
  exit 1
}

NETWORK="${NETWORK:-}"
RUN_ID="${RUN_ID:-}"
RPC_URL="${RPC_URL:-}"
OUT_DIR="${OUT_DIR:-}"
RELEASE_TIER="${RELEASE_TIER:-temporary}"
AUDIT_ID="${AUDIT_ID:-}"
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --network) NETWORK="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --rpc-url) RPC_URL="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --release-tier) RELEASE_TIER="$2"; shift 2 ;;
    --audit-id) AUDIT_ID="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

case "$NETWORK" in
  devnet|sepolia|mainnet) ;;
  *) echo "Invalid or missing --network" >&2; usage ;;
esac

[[ -n "$RUN_ID" ]] || { echo "Missing --run-id" >&2; usage; }

if [[ -z "$RPC_URL" ]]; then
  network_upper=$(printf '%s' "$NETWORK" | tr '[:lower:]' '[:upper:]')
  rpc_var=$(printf '%s_RPC_URL' "$network_upper")
  RPC_URL="${!rpc_var:-}"
fi
[[ -n "$RPC_URL" ]] || { echo "Missing RPC URL (--rpc-url or env)" >&2; exit 1; }

case "$RELEASE_TIER" in
  temporary|candidate|final) ;;
  *) echo "Invalid --release-tier: $RELEASE_TIER" >&2; exit 1 ;;
esac

BUNDLE_DIR="bundles/$NETWORK/$RUN_ID"
DEPLOY_FILE="$BUNDLE_DIR/deployments/$NETWORK-eth.json"
RUN_FILE="$BUNDLE_DIR/run.json"
TXS_FILE="$BUNDLE_DIR/txs.json"
POST_FILE="$BUNDLE_DIR/postconditions.json"
AUDIT_DIR="audits/$NETWORK/${AUDIT_ID:-}"

for path in "$DEPLOY_FILE" "$RUN_FILE" "$TXS_FILE" "$POST_FILE"; do
  [[ -f "$path" ]] || { echo "Missing required file: $path" >&2; exit 1; }
done

jq -e '.status == "pass"' "$POST_FILE" >/dev/null || {
  echo "postconditions.json does not report pass" >&2
  exit 1
}

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="artifacts/$NETWORK/current/fe-release"
fi
ABI_DIR="$OUT_DIR/abi"
mkdir -p "$ABI_DIR"

if [[ $FORCE -ne 1 && -e "$OUT_DIR/protocol-release.$NETWORK.json" ]]; then
  echo "Refusing to overwrite existing FE release output without --force: $OUT_DIR" >&2
  exit 1
fi

PATH_NFT_ADDR=$(jq -r '.contracts.pathNft' "$DEPLOY_FILE")
PATH_MINTER_ADDR=$(jq -r '.contracts.pathMinter' "$DEPLOY_FILE")
PATH_ADAPTER_ADDR=$(jq -r '.contracts.pathMinterAdapter' "$DEPLOY_FILE")
PULSE_AUCTION_ADDR=$(jq -r '.contracts.pulseAuction' "$DEPLOY_FILE")
TREASURY_ADDR=$(jq -r '.treasury' "$DEPLOY_FILE")
PAYMENT_TOKEN_ADDR=$(jq -r '.paymentToken' "$DEPLOY_FILE")

for addr in "$PATH_NFT_ADDR" "$PATH_MINTER_ADDR" "$PATH_ADAPTER_ADDR" "$PULSE_AUCTION_ADDR" "$TREASURY_ADDR" "$PAYMENT_TOKEN_ADDR"; do
  [[ "$addr" =~ ^0x[a-fA-F0-9]{40}$ ]] || { echo "Invalid address in deployment file: $addr" >&2; exit 1; }
done

extract_abi() {
  local src="$1"
  local dst="$2"
  [[ -f "$src" ]] || { echo "Missing ABI artifact: $src" >&2; exit 1; }
  jq '.abi' "$src" > "$dst"
}

extract_abi "evm/artifacts/src/PathNFT.sol/PathNFT.json" "$ABI_DIR/PathNFT.json"
extract_abi "evm/artifacts/src/PathMinter.sol/PathMinter.json" "$ABI_DIR/PathMinter.json"
extract_abi "evm/artifacts/src/PathMinterAdapter.sol/PathMinterAdapter.json" "$ABI_DIR/PathMinterAdapter.json"
extract_abi "evm/artifacts/src/PulseAuction.sol/PulseAuction.json" "$ABI_DIR/PulseAuction.json"

rpc_tmp=$(mktemp)
cleanup() {
  rm -f "$rpc_tmp"
}
trap cleanup EXIT

load_receipt() {
  local key="$1"
  local tx="$2"
  local expected_addr="$3"
  local status
  status=$(cast receipt --rpc-url "$RPC_URL" "$tx" status | awk '{print $1}')
  [[ "$status" == "1" ]] || { echo "Receipt status not successful for $key: $tx" >&2; exit 1; }
  local block_number
  block_number=$(cast receipt --rpc-url "$RPC_URL" "$tx" blockNumber)
  [[ "$block_number" =~ ^[0-9]+$ ]] || { echo "Missing blockNumber for $key: $tx" >&2; exit 1; }
  local contract_address
  contract_address=$(cast receipt --rpc-url "$RPC_URL" "$tx" contractAddress 2>/dev/null || true)
  if [[ -n "$contract_address" && "$contract_address" != "null" ]]; then
    local contract_address_lc
    local expected_addr_lc
    contract_address_lc=$(printf '%s' "$contract_address" | tr '[:upper:]' '[:lower:]')
    expected_addr_lc=$(printf '%s' "$expected_addr" | tr '[:upper:]' '[:lower:]')
    [[ "$contract_address_lc" == "$expected_addr_lc" ]] || {
      echo "Receipt contractAddress mismatch for $key: $contract_address != $expected_addr" >&2
      exit 1
    }
  fi
  jq -n --arg key "$key" --argjson block "$block_number" '{($key): $block}'
}

PATH_NFT_TX=$(jq -r '.deployTxs.pathNft' "$DEPLOY_FILE")
PATH_MINTER_TX=$(jq -r '.deployTxs.pathMinter' "$DEPLOY_FILE")
PATH_ADAPTER_TX=$(jq -r '.deployTxs.pathMinterAdapter' "$DEPLOY_FILE")
PULSE_AUCTION_TX=$(jq -r '.deployTxs.pulseAuction' "$DEPLOY_FILE")

jq -s 'add' \
  <(load_receipt path_nft "$PATH_NFT_TX" "$PATH_NFT_ADDR") \
  <(load_receipt path_minter "$PATH_MINTER_TX" "$PATH_MINTER_ADDR") \
  <(load_receipt path_minter_adapter "$PATH_ADAPTER_TX" "$PATH_ADAPTER_ADDR") \
  <(load_receipt pulse_auction "$PULSE_AUCTION_TX" "$PULSE_AUCTION_ADDR") > "$rpc_tmp"

for addr in "$PATH_NFT_ADDR" "$PATH_MINTER_ADDR" "$PATH_ADAPTER_ADDR" "$PULSE_AUCTION_ADDR"; do
  code=$(cast code --rpc-url "$RPC_URL" "$addr")
  [[ -n "$code" && "$code" != "0x" ]] || { echo "No on-chain code at $addr" >&2; exit 1; }
done

ADDRESSES_OUT="$OUT_DIR/addresses.$NETWORK.json"
MANIFEST_OUT="$OUT_DIR/protocol-release.$NETWORK.json"
CHECKSUMS_OUT="$OUT_DIR/checksums.json"
ENV_OUT="$OUT_DIR/env.$NETWORK.example"

python3 - "$ROOT" "$NETWORK" "$RUN_ID" "$DEPLOY_FILE" "$RUN_FILE" "$TXS_FILE" "$POST_FILE" "$rpc_tmp" "$ADDRESSES_OUT" "$MANIFEST_OUT" "$ENV_OUT" "$CHECKSUMS_OUT" "$RELEASE_TIER" "$AUDIT_ID" <<'PY'
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

root = Path(sys.argv[1])
network = sys.argv[2]
run_id = sys.argv[3]
deploy_file = Path(sys.argv[4])
run_file = Path(sys.argv[5])
txs_file = Path(sys.argv[6])
post_file = Path(sys.argv[7])
blocks_file = Path(sys.argv[8])
addresses_out = Path(sys.argv[9])
manifest_out = Path(sys.argv[10])
env_out = Path(sys.argv[11])
checksums_out = Path(sys.argv[12])
release_tier = sys.argv[13]
audit_id = sys.argv[14]

def load(p: Path):
    with p.open() as fh:
        return json.load(fh)

def relpath(p: Path) -> str:
    return str(p.resolve().relative_to(root.resolve()))

addr_re = re.compile(r"^0x[a-fA-F0-9]{40}$")
hash_re = re.compile(r"^0x[a-fA-F0-9]{64}$")

run = load(run_file)
deploy = load(deploy_file)
txs = load(txs_file)
post = load(post_file)
blocks = load(blocks_file)

audit_status = "none"
if audit_id:
    audit_dir = root / "audits" / network / audit_id
    signoff_candidates = [
        audit_dir / "audit_signoff.json",
        audit_dir / "signoff.json",
    ]
    signoff_path = next((path for path in signoff_candidates if path.exists()), None)
    if signoff_path is None:
        raise SystemExit(f"missing audit signoff for {audit_id}")
    signoff = load(signoff_path)
    if signoff.get("audit_id") != audit_id:
        raise SystemExit(f"audit signoff id mismatch for {audit_id}")
    if signoff.get("network") != network:
        raise SystemExit(f"audit signoff network mismatch for {audit_id}")
    if signoff.get("decision") != "approve":
        raise SystemExit(f"audit signoff not approved for {audit_id}")
    run_ids = signoff.get("run_ids", [])
    if run_id not in run_ids:
        raise SystemExit(f"audit signoff does not cover run_id {run_id}")
    audit_status = "pass"

contracts = {
    "path_nft": deploy["contracts"]["pathNft"],
    "path_minter": deploy["contracts"]["pathMinter"],
    "path_minter_adapter": deploy["contracts"]["pathMinterAdapter"],
    "pulse_auction": deploy["contracts"]["pulseAuction"],
}

addresses = {
    **contracts,
    "treasury": deploy["treasury"],
    "payment_token": deploy["paymentToken"],
}

for key, value in addresses.items():
    if not addr_re.match(value):
        raise SystemExit(f"invalid address for {key}: {value}")

code_hashes = {
    "path_nft": deploy["codeHashes"]["pathNft"],
    "path_minter": deploy["codeHashes"]["pathMinter"],
    "path_minter_adapter": deploy["codeHashes"]["pathMinterAdapter"],
    "pulse_auction": deploy["codeHashes"]["pulseAuction"],
}
for key, value in code_hashes.items():
    if not hash_re.match(value):
        raise SystemExit(f"invalid code hash for {key}: {value}")

manifest = {
    "schema_version": 1,
    "protocol": "path",
    "network": network,
    "chain_id": int(deploy["chainId"]),
    "repo_commit": run["git_commit"],
    "deploy_run_id": run_id,
    "release_tier": release_tier,
    "deployer": deploy["deployer"],
    "treasury": deploy["treasury"],
    "payment_token": deploy["paymentToken"],
    "contracts": contracts,
    "deploy_txs": {
        "path_nft": deploy["deployTxs"]["pathNft"],
        "path_minter": deploy["deployTxs"]["pathMinter"],
        "path_minter_adapter": deploy["deployTxs"]["pathMinterAdapter"],
        "pulse_auction": deploy["deployTxs"]["pulseAuction"],
    },
    "deploy_blocks": {
        "path_nft": int(blocks["path_nft"]),
        "path_minter": int(blocks["path_minter"]),
        "path_minter_adapter": int(blocks["path_minter_adapter"]),
        "pulse_auction": int(blocks["pulse_auction"]),
    },
    "code_hashes": code_hashes,
    "config": {
        "name": deploy["config"]["name"],
        "symbol": deploy["config"]["symbol"],
        "base_uri": deploy["config"].get("baseUri", ""),
        "open_time": int(deploy["config"]["openTime"]),
        "open_time_iso": deploy["config"]["openTimeIso"],
        "start_delay_sec": int(deploy["config"]["startDelaySec"]),
        "k": str(deploy["config"]["k"]),
        "genesis_price": str(deploy["config"]["genesisPrice"]),
        "genesis_floor": str(deploy["config"]["genesisFloor"]),
        "token_base": int(deploy["config"]["tokenBase"]),
        "epoch_base": int(deploy["config"]["epochBase"]),
        "reserved_cap": int(deploy["config"]["reservedCap"]),
    },
    "status": {
        "postconditions": post["status"],
        "audit": audit_status,
        "audit_id": audit_id or None,
        "ready_for_fe": True,
        "notes": "temporary Sepolia integration target" if release_tier == "temporary" else ""
    },
    "source_artifacts": {
        "deployment_relpath": relpath(deploy_file),
        "bundle_relpath": relpath(deploy_file.parent.parent),
    },
    "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
}

if not re.match(r"^[0-9a-f]{40}$", manifest["repo_commit"]):
    raise SystemExit("invalid repo_commit")

if release_tier == "final" and audit_status != "pass":
    raise SystemExit("final release_tier requires approved audit signoff")

addresses_out.write_text(json.dumps(addresses, indent=2) + "\n")
manifest_out.write_text(json.dumps(manifest, indent=2) + "\n")
env_out.write_text(
    f"VITE_NETWORK={network}\n"
    f"VITE_PULSE_AUCTION_DEPLOY_BLOCK={manifest['deploy_blocks']['pulse_auction']}\n"
)

checksums = {}
for path in [addresses_out, manifest_out, env_out]:
    checksums[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
abi_dir = manifest_out.parent / "abi"
for path in sorted(abi_dir.glob("*.json")):
    checksums[f"abi/{path.name}"] = hashlib.sha256(path.read_bytes()).hexdigest()
checksums_out.write_text(json.dumps(checksums, indent=2) + "\n")
PY

python3 - "$ADDRESSES_OUT" "$MANIFEST_OUT" <<'PY'
import json
import re
import sys
from pathlib import Path

addr_re = re.compile(r"^0x[a-fA-F0-9]{40}$")
hash40_re = re.compile(r"^[0-9a-f]{40}$")

addresses = json.loads(Path(sys.argv[1]).read_text())
manifest = json.loads(Path(sys.argv[2]).read_text())

required_addresses = {
    "path_nft",
    "path_minter",
    "path_minter_adapter",
    "pulse_auction",
    "treasury",
    "payment_token",
}
if set(addresses.keys()) != required_addresses:
    raise SystemExit("addresses file shape mismatch")
for value in addresses.values():
    if not addr_re.match(value):
        raise SystemExit(f"invalid exported address: {value}")

if manifest.get("schema_version") != 1:
    raise SystemExit("invalid schema_version")
if manifest.get("protocol") != "path":
    raise SystemExit("invalid protocol")
if manifest.get("network") not in {"devnet", "sepolia", "mainnet"}:
    raise SystemExit("invalid network")
if not hash40_re.match(manifest.get("repo_commit", "")):
    raise SystemExit("invalid repo_commit")
contracts = manifest.get("contracts", {})
required_contracts = {"path_nft", "path_minter", "path_minter_adapter", "pulse_auction"}
if set(contracts.keys()) != required_contracts:
    raise SystemExit("manifest contracts shape mismatch")
for key in required_contracts:
    if contracts[key] != addresses[key]:
        raise SystemExit(f"manifest contract mismatch for {key}")
if manifest.get("treasury") != addresses["treasury"]:
    raise SystemExit("manifest treasury does not match addresses file")
if manifest.get("payment_token") != addresses["payment_token"]:
    raise SystemExit("manifest payment_token does not match addresses file")
required_blocks = {"path_nft", "path_minter", "path_minter_adapter", "pulse_auction"}
if set(manifest.get("deploy_blocks", {}).keys()) != required_blocks:
    raise SystemExit("deploy_blocks shape mismatch")
if manifest.get("status", {}).get("postconditions") != "pass":
    raise SystemExit("postconditions not pass")
print("fe release validation passed")
PY

printf 'fe-release exported\n'
printf 'network=%s\n' "$NETWORK"
printf 'run_id=%s\n' "$RUN_ID"
printf 'out_dir=%s\n' "$OUT_DIR"
printf 'release_manifest=%s\n' "$MANIFEST_OUT"
printf 'addresses=%s\n' "$ADDRESSES_OUT"
printf 'env_hint=%s\n' "$ENV_OUT"
printf 'checksums=%s\n' "$CHECKSUMS_OUT"
