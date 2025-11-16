#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

# ---- env ----
[ -f scripts/.env.example ] && . scripts/.env.example
[ -f scripts/.env.local ] && . scripts/.env.local
[ -f scripts/params.devnet.example ] && . scripts/params.devnet.example
[ -f output/addresses.env ] && . output/addresses.env

need() { command -v "$1" >/dev/null 2>&1 || {
	echo "Missing: $1" >&2
	exit 1
}; }
need sncast
need jq
need python3
need curl

RPC="${RPC_URL:-http://127.0.0.1:5050/rpc}"
PROFILE_BIDDER="${BIDDER_PROFILE:-dev_bidder1}"
: "${PULSE_AUCTION:?source output/addresses.env}"
: "${PAYTOKEN:?source scripts/params.devnet.example}"

SLEEP_S="${SLEEP_S:-2}"                             # pause after bid (seconds)
ALLOW_DEC="${ALLOW_DEC:-1000000000000000000000000}" # 1e24

OUT_DIR="output"
mkdir -p "$OUT_DIR"
: >"$OUT_DIR/.gitkeep"
LOG_FILE="$OUT_DIR/smoke_$(date +%F-%H%M%S).jsonl"

ACCOUNTS_FILE="${SNCAST_ACCOUNTS_FILE:-.accounts/devnet_oz_accounts.json}"
ACCT_NS="${SNCAST_ACCOUNTS_NAMESPACE:-alpha-sepolia}"
BIDDER_ADDR="$(jq -r --arg ns "$ACCT_NS" --arg p "$PROFILE_BIDDER" '.[$ns][$p].address' "$ACCOUNTS_FILE")"

u256_split_dec() {
	python3 - "$1" <<'PY'
import sys
n=int(sys.argv[1],0); print(n & ((1<<128)-1), n>>128)
PY
}
dec_of_hex() {
	python3 - "$1" <<'PY'
import sys; s=sys.argv[1].strip(); print(int(s,16) if s.startswith(("0x","0X")) else int(s))
PY
}
lower() {
	python3 - "$1" <<'PY'
import sys; print((sys.argv[1] or "").lower())
PY
}

call_json() { # call_json <profile> <addr> <fn> [calldata...]
	local prof="$1" addr="$2" fn="$3"
	shift 3
	local argv=(sncast --profile "$prof" --json call --contract-address "$addr" --function "$fn")
	if [ "$#" -gt 0 ]; then
		argv+=(--calldata)
		for w in "$@"; do argv+=("$w"); done
	fi
	local out last
	out="$("${argv[@]}")"
	last="$(printf '%s\n' "$out" | tail -n 1)"
	printf '%s\n' "$last"
}
invoke_json() { # invoke_json <profile> <addr> <fn> [calldata...]
	local prof="$1" addr="$2" fn="$3"
	shift 3
	local argv=(sncast --profile "$prof" --json invoke --contract-address "$addr" --function "$fn")
	if [ "$#" -gt 0 ]; then
		argv+=(--calldata)
		for w in "$@"; do argv+=("$w"); done
	fi
	local out last
	out="$("${argv[@]}")"
	last="$(printf '%s\n' "$out" | tail -n 1)"
	printf '%s\n' "$last"
}
await_receipt() { # await_receipt <tx_hash> -> "block_number finality"
	local h="$1" tries=80
	while [ $tries -gt 0 ]; do
		local j r bn fs
		j="$(curl -sS -H 'Content-Type: application/json' \
			-d '{"jsonrpc":"2.0","method":"starknet_getTransactionReceipt","params":["'"$h"'"],"id":1}' \
			"$RPC" 2>/dev/null)" || true
		r="$(jq -r '.result // empty' <<<"$j")"
		if [ -n "$r" ]; then
			bn="$(jq -r '.block_number // "0x0"' <<<"$r")"
			fs="$(jq -r '.finality_status // .status // ""' <<<"$r")"
			echo "$(dec_of_hex "$bn") ${fs:-UNKNOWN}"
			return 0
		fi
		sleep 0.25
		tries=$((tries - 1))
	done
	echo "0 TIMEOUT"
}

get_price_u256() { # -> "low high"
	local j lo hi
	j="$(call_json "$PROFILE_BIDDER" "$PULSE_AUCTION" get_current_price 2>/dev/null || true)"
	lo="$(jq -r '.response_raw[0] // .response[0] // empty' <<<"$j")"
	hi="$(jq -r '.response_raw[1] // .response[1] // empty' <<<"$j")"
	[ -n "$lo" ] || {
		echo "0x0 0x0"
		return 0
	}
	echo "$lo $hi"
}

echo "==> Smoke (post-deploy sanity)"
cat <<EOF
    RPC     : $RPC
    Auction : $PULSE_AUCTION
    PayToken: $PAYTOKEN
    Bidder  : $PROFILE_BIDDER ($BIDDER_ADDR)
    Allow   : $ALLOW_DEC
    Log     : $LOG_FILE
EOF
echo
echo "Genesis-only smoke → ensure bidder balance covers the initial ask."
echo

# Genesis guard – skip if curve already active
curve_status="$(call_json "$PROFILE_BIDDER" "$PULSE_AUCTION" curve_active 2>/dev/null || true)"
curve_flag="$(jq -r '.response_raw[0] // .response[0] // empty' <<<"$curve_status" 2>/dev/null || true)"
case "$(lower "$curve_flag")" in
	0x1 | 1)
		echo "Pulse auction curve is already active – genesis bid settled; nothing to do."
		exit 0
		;;
	0x0 | 0)
		echo "Genesis bid still open; continuing."
		;;
	"")
		echo "Unable to read curve_active state (empty response)." >&2
		exit 1
		;;
	*)
		echo "Unexpected curve_active response: $curve_flag" >&2
		exit 1
		;;
esac
echo

# Approve once
read -r ALLOW_LO ALLOW_HI <<<"$(u256_split_dec "$ALLOW_DEC")"
TX_APPROVE="$(invoke_json "$PROFILE_BIDDER" "$PAYTOKEN" approve "$PULSE_AUCTION" "$ALLOW_LO" "$ALLOW_HI" | jq -r '.transaction_hash // empty')"
[ -n "$TX_APPROVE" ] && echo "approve tx: $TX_APPROVE"
read -r ABN AFS <<<"$(await_receipt "$TX_APPROVE")"
echo "approve confirmed in block=$ABN finality=$AFS"
echo

read -r ASK_LO ASK_HI <<<"$(get_price_u256)"
printf "[genesis] bid (lo=%s hi=%s) … " "$ASK_LO" "$ASK_HI"

TX="$(invoke_json "$PROFILE_BIDDER" "$PULSE_AUCTION" bid "$ASK_LO" "$ASK_HI" | jq -r '.transaction_hash // empty')"
if [ -z "$TX" ]; then
	echo "submit_error"
	echo '{"error":"submit_error"}' >>"$LOG_FILE"
	exit 1
fi

read -r BN FIN <<<"$(await_receipt "$TX")"
echo "tx=$TX block=$BN finality=$FIN"
jq -nc --arg tx "$TX" --arg bn "$BN" --arg fin "$FIN" \
	--arg lo "$ASK_LO" --arg hi "$ASK_HI" \
	'{"tx":$tx,"block":($bn|tonumber),"finality":$fin,"u256":{"low":$lo,"high":$hi}}' \
	>>"$LOG_FILE"

echo
echo "Genesis smoke complete. JSONL log → $LOG_FILE"
