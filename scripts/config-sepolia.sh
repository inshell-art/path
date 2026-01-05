#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
# Configure roles & wiring for PATH on Sepolia, with verification summary.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

# ---- env & deps ---------------------------------------------------------------
[ -f scripts/.env.example ] && . scripts/.env.example
[ -f scripts/.env.sepolia.local ] && . scripts/.env.sepolia.local
[ -f scripts/params.sepolia.example ] && . scripts/params.sepolia.example
[ -f scripts/params.sepolia.local ] && . scripts/params.sepolia.local
[ -f output/sepolia/addresses.sepolia.env ] && . output/sepolia/addresses.sepolia.env

need() { command -v "$1" >/dev/null 2>&1 || {
	echo "Missing: $1" >&2
	exit 1
}; }
need sncast
need jq
need tee
need python3

OUT_DIR="output/sepolia"
mkdir -p "$OUT_DIR"
: >"$OUT_DIR/.gitkeep"

ADDR_FILE="$OUT_DIR/addresses.sepolia.json"
PROFILE="${CONFIG_PROFILE:-${PROFILE:-main-sep}}"
RPC="${RPC_URL:?set RPC_URL in scripts/.env.sepolia.local}"

# Prefer env exports, else fall back to JSON file
ADDR_NFT="${PATH_NFT:-$(jq -r '.path_nft // empty' "$ADDR_FILE" 2>/dev/null || true)}"
ADDR_MINTER="${PATH_MINTER:-$(jq -r '.path_minter // empty' "$ADDR_FILE" 2>/dev/null || true)}"
ADDR_ADAPTER="${PATH_ADAPTER:-$(jq -r '.path_minter_adapter // empty' "$ADDR_FILE" 2>/dev/null || true)}"
ADDR_AUCTION="${PULSE_AUCTION:-$(jq -r '.pulse_auction // empty' "$ADDR_FILE" 2>/dev/null || true)}"

# ---- helpers ------------------------------------------------------------------
require_nonempty() { [ -n "$2" ] || {
	echo "!! $1 is empty" >&2
	exit 1
}; }

norm_hex() {
	# normalize a hex string to 0x... (lowercase), or empty on parse failure
	python3 - "$1" <<'PY'
import sys
x=sys.argv[1].strip()
if x.startswith(("0x","0X")): x=x[2:]
try:
    v=int(x or "0",16)
    print(hex(v))
except Exception:
    print("")
PY
}

lower() {
	python3 - "$1" <<'PY'
import sys; print((sys.argv[1] or "").lower())
PY
}

# Compute role id
role_id() { # usage: selector_id NAME
	python3 - "$1" <<'PY'
import sys
import hashlib
name = sys.argv[1].encode()

# get keccak256
h = None
try:
    from eth_hash.auto import keccak
    h = keccak(name)
except Exception:
    try:
        from Crypto.Hash import keccak as K
        k = K.new(digest_bits=256); k.update(name); h = k.digest()
    except Exception:
        try:
            import sha3  # pysha3
            k = sha3.keccak_256(); k.update(name); h = k.digest()
        except Exception:
            # fallback to stdlib sha3_256 (available in Python 3.6+) as keccak-compatible here
            try:
                k = hashlib.sha3_256(); k.update(name); h = k.digest()
            except Exception:
                print("ERROR: install eth-hash[pycryptodome], pycryptodome, or pysha3", file=sys.stderr)
                sys.exit(1)

MASK = (1 << 250) - 1
print(hex(int.from_bytes(h, 'big') & MASK))
PY
}

# Safer sncast wrappers
invoke() { # invoke <label> <addr> <fn> <calldata...>
	local label="$1" addr="$2" fn="$3"
	shift 3
	local ts out
	ts="$(date +%F-%H%M%S)"
	out="$OUT_DIR/invoke_${label}_${ts}.json"
	echo "==> $label: $fn @ $addr"
	if [ "$#" -eq 0 ]; then
		echo "!! BUG: no calldata supplied to $fn ($label)" >&2
		exit 1
	fi
	echo "   calldata: $*"
	local argv=(sncast --profile "$PROFILE" --json invoke
		--contract-address "$addr" --function "$fn" --calldata)
	for w in "$@"; do argv+=("$w"); done
	"${argv[@]}" | tee "$out" >/dev/null || true
}

call_json() { # call_json <addr> <fn> [calldata...]
	local addr="$1" fn="$2"
	shift 2
	local argv=(sncast --profile "$PROFILE" --json call
		--contract-address "$addr" --function "$fn")
	if [ "$#" -gt 0 ]; then
		argv+=(--calldata)
		for w in "$@"; do argv+=("$w"); done
	fi
	"${argv[@]}"
}

# ---- normalize & validate inputs ---------------------------------------------
ADDR_NFT="$(norm_hex "$ADDR_NFT")"
require_nonempty PATH_NFT "$ADDR_NFT"
ADDR_MINTER="$(norm_hex "$ADDR_MINTER")"
require_nonempty PATH_MINTER "$ADDR_MINTER"
ADDR_ADAPTER="$(norm_hex "$ADDR_ADAPTER")"
require_nonempty PATH_ADAPTER "$ADDR_ADAPTER"
ADDR_AUCTION="$(norm_hex "$ADDR_AUCTION")"
require_nonempty PULSE_AUCTION "$ADDR_AUCTION"

export MINTER_ROLE_ID="$(role_id MINTER_ROLE)"
echo "minter role id: $MINTER_ROLE_ID"
require_nonempty MINTER_ROLE_ID "$MINTER_ROLE_ID"
export SALES_ROLE_ID="$(role_id SALES_ROLE)"
echo "sales role id: $SALES_ROLE_ID"
require_nonempty SALES_ROLE_ID "$SALES_ROLE_ID"

echo "NOTE: Using profile '$PROFILE' at RPC: $RPC"
printf "      NFT=%s  MINTER=%s  ADAPTER=%s  AUCTION=%s\n" "$ADDR_NFT" "$ADDR_MINTER" "$ADDR_ADAPTER" "$ADDR_AUCTION"

# ---- perform grants & wiring (idempotent-friendly) ----------------------------
invoke "NFT.grant(MINTER_ROLE->MINTER)" "$ADDR_NFT" grant_role "$MINTER_ROLE_ID" "$ADDR_MINTER"
invoke "MINTER.grant(SALES_ROLE->ADAPTER)" "$ADDR_MINTER" grant_role "$SALES_ROLE_ID" "$ADDR_ADAPTER"
invoke "Adapter.set_minter" "$ADDR_ADAPTER" set_minter "$ADDR_MINTER"
invoke "Adapter.set_auction" "$ADDR_ADAPTER" set_auction "$ADDR_AUCTION"

# ---- verification -------------------------------------------------------------
# NFT.has_role(MINTER_ROLE, MINTER)
NFT_HAS="$(call_json "$ADDR_NFT" has_role "$MINTER_ROLE_ID" "$ADDR_MINTER" |
	jq -r '.response_raw[-1] // .response[-1] // empty' 2>/dev/null || true)"

# MINTER.has_role(SALES_ROLE, ADAPTER)
MINTER_HAS="$(call_json "$ADDR_MINTER" has_role "$SALES_ROLE_ID" "$ADDR_ADAPTER" |
	jq -r '.response_raw[-1] // .response[-1] // empty' 2>/dev/null || true)"

# Adapter.get_config() -> (auction, minter)
CFG_JSON="$(call_json "$ADDR_ADAPTER" get_config 2>/dev/null || true)"
ADAPTER_AUCTION_ADDR="$(jq -r '.response_raw[0] // .response[0] // empty' <<<"$CFG_JSON" 2>/dev/null || true)"
ADAPTER_MINTER_ADDR="$(jq -r '.response_raw[1] // .response[1] // empty' <<<"$CFG_JSON" 2>/dev/null || true)"

# Normalize for comparison
EXP_AUCTION="$(lower "$ADDR_AUCTION")"
EXP_MINTER="$(lower "$ADDR_MINTER")"
GOT_AUCTION="$(lower "${ADAPTER_AUCTION_ADDR:-}")"
GOT_MINTER="$(lower "${ADAPTER_MINTER_ADDR:-}")"

AUCTION_OK="FAIL"
[ -n "$GOT_AUCTION" ] && [ "$GOT_AUCTION" = "$EXP_AUCTION" ] && AUCTION_OK="OK"
MINTER_OK="FAIL"
[ -n "$GOT_MINTER" ] && [ "$GOT_MINTER" = "$EXP_MINTER" ] && MINTER_OK="OK"

echo
echo "================ CONFIG RESULT ================"
case "$NFT_HAS" in
0x1 | 1) echo "NFT -> MINTER  (MINTER_ROLE): OK" ;;
0x0 | 0) echo "NFT -> MINTER  (MINTER_ROLE): NOT SET" ;;
*) echo "NFT -> MINTER  (MINTER_ROLE): unknown (no has_role?)" ;;
esac
case "$MINTER_HAS" in
0x1 | 1) echo "MINTER -> ADAPTER (SALES_ROLE): OK" ;;
0x0 | 0) echo "MINTER -> ADAPTER (SALES_ROLE): NOT SET" ;;
*) echo "MINTER -> ADAPTER (SALES_ROLE): unknown (no has_role?)" ;;
esac
echo "ADAPTER.get_config():"
echo "  auction = ${ADAPTER_AUCTION_ADDR:-<empty>}  [expect $ADDR_AUCTION]  -> $AUCTION_OK"
echo "  minter  = ${ADAPTER_MINTER_ADDR:-<empty>}   [expect $ADDR_MINTER]   -> $MINTER_OK"
echo "=============================================="

# Exit non-zero only on definite mismatches (addresses). Role checks may be unknown.
fail=0
[ "$AUCTION_OK" = "OK" ] || fail=$((fail + 1))
[ "$MINTER_OK" = "OK" ] || fail=$((fail + 1))
exit $fail
