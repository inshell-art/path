#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

# --- env & deps ---
[ -f scripts/.env.example ] && . scripts/.env.example
[ -f scripts/.env.local ] && . scripts/.env.local
[ -f output/addresses.env ] && . output/addresses.env

need() { command -v "$1" >/dev/null 2>&1 || {
	echo "Missing: $1" >&2
	exit 1
}; }
need sncast
need jq
need tee

RPC="${RPC_URL:-http://127.0.0.1:5050/rpc}"
PROFILE="${PROFILE:-dev_deployer}"
OUT_DIR="output"
mkdir -p "$OUT_DIR"
: >"$OUT_DIR/.gitkeep"

ADDR_FILE="$OUT_DIR/addresses.devnet.json"
ADDR_NFT="${PATH_NFT:-$(jq -r '.path_nft // empty' "$ADDR_FILE" 2>/dev/null || true)}"
ADDR_MINTER="${PATH_MINTER:-$(jq -r '.path_minter // empty' "$ADDR_FILE" 2>/dev/null || true)}"
ADDR_ADAPTER="${PATH_ADAPTER:-$(jq -r '.path_minter_adapter // empty' "$ADDR_FILE" 2>/dev/null || true)}"
ADDR_PULSE="${PULSE_AUCTION:-$(jq -r '.pulse_auction // empty' "$ADDR_FILE" 2>/dev/null || true)}"

[ -n "$ADDR_NFT" ] && [ -n "$ADDR_MINTER" ] && [ -n "$ADDR_ADAPTER" ] && [ -n "$ADDR_PULSE" ] ||
	{
		echo "!! Missing addresses. Run deploy first."
		exit 1
	}

# Role ids: set explicitly in scripts/.env.local if your lib defines constants.
# Fallback: common pattern keccak(name) % prime.
MINTER_ROLE_ID="${MINTER_ROLE_ID:-$(
	python3 - <<'PY'
import hashlib; P=2**251+17*2**192+1
print(hex(int.from_bytes(hashlib.sha3_256(b"MINTER_ROLE").digest(),"big")%P))
PY
)}"
SALES_ROLE_ID="${SALES_ROLE_ID:-$(
	python3 - <<'PY'
import hashlib; P=2**251+17*2**192+1
print(hex(int.from_bytes(hashlib.sha3_256(b"SALES_ROLE").digest(),"big")%P))
PY
)}"

invoke() { # invoke <label> <addr> <fn> <calldata...>
	local label="$1" addr="$2" fn="$3"
	shift 3
	local ts out
	ts="$(date +%F-%H%M%S)"
	out="$OUT_DIR/invoke_${label}_${ts}.json"
	echo "==> $label: $fn @ $addr"
	# Pipe to tee so a revert doesn't trip set -e (tee returns 0)
	sncast --profile "$PROFILE" --json invoke \
		--contract-address "$addr" --function "$fn" --calldata "$@" |
		tee "$out" >/dev/null
}

echo "NOTE: Your signer is profile '$PROFILE'. It must match the ADMIN/OWNER used at deploy."

# 1) NFT: grant MINTER_ROLE to PathMinter (idempotent: ignore revert if already granted or wrong admin)
invoke "NFT.grant(MINTER_ROLE->MINTER)" "$ADDR_NFT" grant_role "$MINTER_ROLE_ID" "$ADDR_MINTER"

# 2) MINTER: grant SALES_ROLE to Adapter
invoke "MINTER.grant(SALES_ROLE->ADAPTER)" "$ADDR_MINTER" grant_role "$SALES_ROLE_ID" "$ADDR_ADAPTER"

# 3) Adapter wiring: set minter & auction (idempotent-ish; ignore revert if already set or not owner)
invoke "Adapter.set_minter" "$ADDR_ADAPTER" set_minter "$ADDR_MINTER"
invoke "Adapter.set_auction" "$ADDR_ADAPTER" set_auction "$ADDR_PULSE"

echo "Config complete."
