#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
# Verify roles and adapter wiring on Sepolia (read-only).
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
need python3
need jq

ADDR_FILE="output/sepolia/addresses.sepolia.json"
RPC="${RPC_URL:?set RPC_URL in scripts/.env.sepolia.local}"

# Prefer env exports, else fall back to JSON file
ADDR_NFT="${PATH_NFT:-$(jq -r '.path_nft // empty' "$ADDR_FILE" 2>/dev/null || true)}"
ADDR_MINTER="${PATH_MINTER:-$(jq -r '.path_minter // empty' "$ADDR_FILE" 2>/dev/null || true)}"
ADDR_ADAPTER="${PATH_ADAPTER:-$(jq -r '.path_minter_adapter // empty' "$ADDR_FILE" 2>/dev/null || true)}"
ADDR_AUCTION="${PULSE_AUCTION:-$(jq -r '.pulse_auction // empty' "$ADDR_FILE" 2>/dev/null || true)}"

require_nonempty() { [ -n "$2" ] || {
	echo "!! $1 is empty" >&2
	exit 1
}; }

require_nonempty PATH_NFT "$ADDR_NFT"
require_nonempty PATH_MINTER "$ADDR_MINTER"
require_nonempty PATH_ADAPTER "$ADDR_ADAPTER"
require_nonempty PULSE_AUCTION "$ADDR_AUCTION"

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

MINTER_ROLE_ID="$(role_id MINTER_ROLE)"
SALES_ROLE_ID="$(role_id SALES_ROLE)"

RESULT="$(
	python3 - "$RPC" "$ADDR_NFT" "$ADDR_MINTER" "$ADDR_ADAPTER" "$ADDR_AUCTION" \
		"$MINTER_ROLE_ID" "$SALES_ROLE_ID" <<'PY'
import asyncio
import json
import sys

import aiohttp
from starknet_py.hash.selector import get_selector_from_name
from starknet_py.net.client_models import Call
from starknet_py.net.full_node_client import FullNodeClient

rpc, nft, minter, adapter, auction, minter_role, sales_role = sys.argv[1:]

def to_int(x: str) -> int:
    return int(x, 0)

async def main() -> None:
    connector = aiohttp.TCPConnector(ssl=False)
    async with aiohttp.ClientSession(connector=connector) as session:
        client = FullNodeClient(node_url=rpc, session=session)

        def mk_call(addr: str, fn: str, calldata: list[int]) -> Call:
            return Call(
                to_addr=to_int(addr),
                selector=get_selector_from_name(fn),
                calldata=calldata,
            )

        nft_has = await client.call_contract(
            mk_call(nft, "has_role", [to_int(minter_role), to_int(minter)]),
            block_hash="latest",
        )
        minter_has = await client.call_contract(
            mk_call(minter, "has_role", [to_int(sales_role), to_int(adapter)]),
            block_hash="latest",
        )
        cfg = await client.call_contract(
            mk_call(adapter, "get_config", []),
            block_hash="latest",
        )

    out = {
        "nft_has": int(nft_has[0]) if nft_has else 0,
        "minter_has": int(minter_has[0]) if minter_has else 0,
        "adapter_auction": hex(cfg[0]) if len(cfg) > 0 else "",
        "adapter_minter": hex(cfg[1]) if len(cfg) > 1 else "",
        "expected_auction": auction.lower(),
        "expected_minter": minter.lower(),
    }
    print(json.dumps(out))

asyncio.run(main())
PY
)"

NFT_HAS="$(jq -r '.nft_has' <<<"$RESULT")"
MINTER_HAS="$(jq -r '.minter_has' <<<"$RESULT")"
ADAPTER_AUCTION_ADDR="$(jq -r '.adapter_auction' <<<"$RESULT")"
ADAPTER_MINTER_ADDR="$(jq -r '.adapter_minter' <<<"$RESULT")"
EXP_AUCTION_RAW="$(jq -r '.expected_auction' <<<"$RESULT")"
EXP_MINTER_RAW="$(jq -r '.expected_minter' <<<"$RESULT")"

normalize_hex() {
	python3 - "$1" <<'PY'
import sys
val = sys.argv[1].strip()
if not val:
    print("")
    sys.exit(0)
try:
    print(hex(int(val, 0)))
except Exception:
    print("")
PY
}

EXP_AUCTION="$(normalize_hex "$EXP_AUCTION_RAW")"
EXP_MINTER="$(normalize_hex "$EXP_MINTER_RAW")"
ADAPTER_AUCTION_ADDR_N="$(normalize_hex "$ADAPTER_AUCTION_ADDR")"
ADAPTER_MINTER_ADDR_N="$(normalize_hex "$ADAPTER_MINTER_ADDR")"

AUCTION_OK="FAIL"
[ -n "$ADAPTER_AUCTION_ADDR_N" ] && [ "$ADAPTER_AUCTION_ADDR_N" = "$EXP_AUCTION" ] && AUCTION_OK="OK"
MINTER_OK="FAIL"
[ -n "$ADAPTER_MINTER_ADDR_N" ] && [ "$ADAPTER_MINTER_ADDR_N" = "$EXP_MINTER" ] && MINTER_OK="OK"

echo
echo "================ VERIFY RESULT ================"
case "$NFT_HAS" in
1) echo "NFT -> MINTER  (MINTER_ROLE): OK" ;;
0) echo "NFT -> MINTER  (MINTER_ROLE): NOT SET" ;;
*) echo "NFT -> MINTER  (MINTER_ROLE): unknown ($NFT_HAS)" ;;
esac
case "$MINTER_HAS" in
1) echo "MINTER -> ADAPTER (SALES_ROLE): OK" ;;
0) echo "MINTER -> ADAPTER (SALES_ROLE): NOT SET" ;;
*) echo "MINTER -> ADAPTER (SALES_ROLE): unknown ($MINTER_HAS)" ;;
esac
echo "ADAPTER.get_config():"
echo "  auction = ${ADAPTER_AUCTION_ADDR_N:-<empty>}  [expect $EXP_AUCTION]  -> $AUCTION_OK"
echo "  minter  = ${ADAPTER_MINTER_ADDR_N:-<empty>}   [expect $EXP_MINTER]   -> $MINTER_OK"
echo "=============================================="

fail=0
[ "$AUCTION_OK" = "OK" ] || fail=$((fail + 1))
[ "$MINTER_OK" = "OK" ] || fail=$((fail + 1))
[ "$NFT_HAS" = "1" ] || fail=$((fail + 1))
[ "$MINTER_HAS" = "1" ] || fail=$((fail + 1))
exit $fail
