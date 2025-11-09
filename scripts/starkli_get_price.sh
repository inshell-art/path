#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

[ -f scripts/.env.example ] && . scripts/.env.example
[ -f scripts/.env.local ] && . scripts/.env.local
[ -f output/addresses.env ] && . output/addresses.env

need() { command -v "$1" >/dev/null 2>&1 || {
	echo "Missing: $1" >&2
	exit 1
}; }
need starkli

RPC="${RPC_URL:-http://127.0.0.1:5050/rpc}"
BLOCK_TAG="${SMOKE_BLOCK_TAG:-latest}"
: "${PULSE_AUCTION:?source output/addresses.env}"

echo "RPC       : $RPC"
echo "Block tag : $BLOCK_TAG"
echo "Auction   : $PULSE_AUCTION"
echo

starkli call --rpc "$RPC" --block "$BLOCK_TAG" "$PULSE_AUCTION" get_current_price 2
