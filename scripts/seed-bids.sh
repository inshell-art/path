#!/usr/bin/env bash
# Quote-driven seeder for PulseAuction:
# - Reads current ask via get_current_price
# - Applies PREMIUM_BPS slippage
# - Ensures allowance
# - One bid per block; logs reasons on failure
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

# ---- env ----------------------------------------------------------------------
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
BIDDER_PROFILE="${BIDDER_PROFILE:-dev_bidder1}"
: "${SNCAST_ACCOUNTS_FILE:?Set SNCAST_ACCOUNTS_FILE in scripts/.env.[example|local]}"
: "${SNCAST_ACCOUNTS_NAMESPACE:?Set SNCAST_ACCOUNTS_NAMESPACE in scripts/.env.[example|local]}"

# --- seeding knobs -------------------------------------------------------------
BID_COUNT="${BID_COUNT:-20}"      # number of bids to submit
PREMIUM_BPS="${PREMIUM_BPS:-300}" # add 3% above quoted ask
SLEEP_MIN="${SLEEP_MIN:-1.0}"     # seconds between bids (uniform)
SLEEP_MAX="${SLEEP_MAX:-3.0}"

# Allowance target (make it comfortably large)
ALLOW_DEC="${ALLOW_DEC:-1000000000000000000000000}" # 1e24 STRK "wei" (example)

# Required addresses
: "${PULSE_AUCTION:?source output/addresses.env first (PULSE_AUCTION missing)}"
: "${PAYTOKEN:?source scripts/params.devnet.example first (PAYTOKEN missing)}"

# Resolve bidder L2 address from sncast accounts file
BIDDER_ADDR="$(jq -r --arg ns "$SNCAST_ACCOUNTS_NAMESPACE" --arg p "$BIDDER_PROFILE" \
	'.[$ns][$p].address' "$SNCAST_ACCOUNTS_FILE")"
[ -n "$BIDDER_ADDR" ] && [ "$BIDDER_ADDR" != "null" ] || {
	echo "!! Could not resolve BIDDER_ADDR"
	exit 1
}

OUT_DIR="output"
mkdir -p "$OUT_DIR"
LOG_FILE="$OUT_DIR/seed_bids_$(date +%F-%H%M%S).jsonl"

# ---- helpers ------------------------------------------------------------------
u256_split() {
	python3 - "$1" <<'PY'
import sys
n=int(sys.argv[1],0)
print(n & ((1<<128)-1), n>>128)
PY
}

u256_add_bps() { # (low, high, bps) -> new_low new_high ; adds n * bps/10000
	python3 - "$@" <<'PY'
import sys
low=int(sys.argv[1],0); high=int(sys.argv[2],0); bps=int(sys.argv[3],0)
n=(high<<128)+low
m=n + (n*bps)//10000
print(hex(m & ((1<<128)-1)), hex(m>>128))
PY
}

rpc() {
	local m="$1" p="${2:-[]}"
	curl -sS -H 'Content-Type: application/json' \
		--data "{\"jsonrpc\":\"2.0\",\"method\":\"$m\",\"params\":$p,\"id\":1}" "$RPC"
}
block_number() { rpc starknet_blockNumber '[]' | jq -r '.result // 0'; }

wait_tx() { # tx tries sleep
	local tx="$1" tries="${2:-120}" sleep_s="${3:-0.25}" i=0
	while ((i < tries)); do
		local j="$(rpc starknet_getTransactionReceipt "[\"$tx\"]")"
		local st="$(jq -r '.result.finality_status // .result.status // empty' <<<"$j")"
		local bn="$(jq -r '.result.block_number // .result.blockNumber // empty' <<<"$j")"
		local ex="$(jq -r '.result.execution_status // .result.executionStatus // empty' <<<"$j")"
		if [[ "$st" =~ ACCEPTED_ON_L2|ACCEPTED_ON_L1 ]] && [[ -z "$ex" || "$ex" == "SUCCEEDED" ]]; then
			echo "${bn:-0} ${st}"
			return 0
		fi
		sleep "$sleep_s"
		i=$((i + 1))
	done
	echo "0 TIMEOUT"
	return 1
}

# Extract raw revert message if sncast fails before tx hash
decode_reason() {
	python3 - <<'PY'
import sys, re, json
s=sys.stdin.read()
# try simple json shapes
try:
    j=json.loads(s)
    if isinstance(j, dict):
        for k in ("error","message"): 
            if k in j and isinstance(j[k], str):
                print(j[k]); sys.exit(0)
except Exception: pass
# pull hex-encoded utf8-like blobs
cands = re.findall(r'0x[0-9a-fA-F]{8,}', s)
for h in cands:
    try:
        m=bytes.fromhex(h[2:]).decode('utf-8','ignore').strip()
        if sum(c.isalpha() for c in m) >= 3:
            print(m); sys.exit(0)
    except Exception: pass
print("")
PY
}

rand_sleep() {
	python3 - "$SLEEP_MIN" "$SLEEP_MAX" <<'PY'
import sys,random
a=float(sys.argv[1]); b=float(sys.argv[2])
print(f"{random.uniform(a,b):.3f}")
PY
}

read_allowance() {
	local j lo hi
	j="$(sncast --profile "$BIDDER_PROFILE" --json call \
		--contract-address "$PAYTOKEN" \
		--function allowance \
		--calldata "$BIDDER_ADDR" "$PULSE_AUCTION" 2>/dev/null || true)"
	lo="$(jq -r '.response_raw[0] // .response[0] // "0x0"' <<<"$j")"
	hi="$(jq -r '.response_raw[1] // .response[1] // "0x0"' <<<"$j")"
	echo "$lo $hi"
}

gte_u256() {
	python3 - "$@" <<'PY'
import sys
l1=int(sys.argv[1],0); h1=int(sys.argv[2],0)
l2=int(sys.argv[3],0); h2=int(sys.argv[4],0)
print(1 if ((h1<<128)+l1) >= ((h2<<128)+l2) else 0)
PY
}

ensure_allow() {
	read -r WANT_LO WANT_HI < <(u256_split "$ALLOW_DEC")
	read -r ALW_LO ALW_HI < <(read_allowance)
	if [[ "$(gte_u256 "$ALW_LO" "$ALW_HI" "$WANT_LO" "$WANT_HI")" == "1" ]]; then
		echo "    allowance OK (low=$ALW_LO, high=$ALW_HI)"
		return 0
	fi
	echo "==> Approving allowance… target u256: ${WANT_LO},${WANT_HI} (current low=$ALW_LO, high=$ALW_HI)"
	local j tx
	j="$(sncast --profile "$BIDDER_PROFILE" --json invoke \
		--contract-address "$PAYTOKEN" \
		--function approve \
		--calldata "$PULSE_AUCTION" "$WANT_LO" "$WANT_HI" 2>&1 || true)"
	tx="$(jq -r '.transaction_hash // empty' <<<"$j")"
	[[ -n "$tx" ]] && echo "    approve tx: $tx" || echo "    warn: approve produced no tx"
	# poll until allowance reflects target
	for _ in $(seq 1 32); do
		sleep 0.25
		read -r ALW_LO ALW_HI < <(read_allowance)
		if [[ "$(gte_u256 "$ALW_LO" "$ALW_HI" "$WANT_LO" "$WANT_HI")" == "1" ]]; then
			echo "    allowance OK (low=$ALW_LO, high=$ALW_HI)"
			return 0
		fi
	done
	echo "!! allowance did not reach target" >&2
	return 1
}

quote_price() { # -> prints low high of get_current_price()
	local j lo hi
	j="$(sncast --profile "$BIDDER_PROFILE" --json call \
		--contract-address "$PULSE_AUCTION" \
		--function get_current_price 2>/dev/null || true)"
	lo="$(jq -r '.response_raw[0] // .response[0] // "0x0"' <<<"$j")"
	hi="$(jq -r '.response_raw[1] // .response[1] // "0x0"' <<<"$j")"
	echo "$lo $hi"
}

# ---- banner -------------------------------------------------------------------
echo "==> Quote-based seeding"
echo "    Auction : $PULSE_AUCTION"
echo "    PayToken: $PAYTOKEN"
echo "    Bidder  : ${BIDDER_PROFILE} (${BIDDER_ADDR})"
echo "    Allow   : ensure >= ${ALLOW_DEC}"
echo "    Premium : +${PREMIUM_BPS} bps"
echo "    Delays  : ${SLEEP_MIN}s .. ${SLEEP_MAX}s"
echo "    Count   : ${BID_COUNT}"
echo "    Log     : ${LOG_FILE}"
echo

ensure_allow

last_bn="$(block_number)"
: "${last_bn:=0}"

for i in $(seq 1 "$BID_COUNT"); do
	delay="$(rand_sleep)"

	# 1) Quote
	read -r P_LO P_HI < <(quote_price)
	# 2) Apply premium
	read -r A_LO A_HI < <(u256_add_bps "$P_LO" "$P_HI" "$PREMIUM_BPS")

	# 3) Submit bid(amount = A_LO, A_HI)
	raw="$(sncast --profile "$BIDDER_PROFILE" --json invoke \
		--contract-address "$PULSE_AUCTION" \
		--function bid \
		--calldata "$A_LO" "$A_HI" 2>&1 || true)"
	tx="$(jq -r '.transaction_hash // empty' <<<"$raw" 2>/dev/null || true)"

	if [[ -n "$tx" ]]; then
		read -r bn st < <(wait_tx "$tx" 120 0.25 || true)
		[[ -z "$bn" || "$bn" = "0" ]] && bn="$(block_number)"
		# one bid per block: wait until chain advances
		tries=24
		while ((bn <= last_bn && tries > 0)); do
			sleep 0.25
			bn="$(block_number)"
			tries=$((tries - 1))
		done
		advanced=$((bn > last_bn ? 1 : 0))
		last_bn="$bn"

		echo "{\"ts\":\"$(date -Is)\",\"i\":$i,\"tx\":\"$tx\",\"block\":$bn,\"accepted\":\"$st\",\"price_low\":\"$P_LO\",\"price_high\":\"$P_HI\",\"amount_low\":\"$A_LO\",\"amount_high\":\"$A_HI\",\"sleep\":$delay,\"advanced\":$advanced}" >>"$LOG_FILE"
		echo "[$i/$BID_COUNT] tx=$tx block=$bn accepted=$st advanced=$advanced amount_low=$A_LO amount_high=$A_HI (quoted_low=$P_LO)"
	else
		reason="$(printf "%s" "$raw" | decode_reason || true)"
		echo "{\"ts\":\"$(date -Is)\",\"i\":$i,\"status\":\"submit_error\",\"price_low\":\"$P_LO\",\"price_high\":\"$P_HI\",\"amount_low\":\"$A_LO\",\"amount_high\":\"$A_HI\",\"reason\":$(jq -Rs . <<<"$reason"),\"raw\":$(jq -Rs . <<<"$raw")}" >>"$LOG_FILE"
		echo "[$i/$BID_COUNT] submit_error: ${reason:-<no-reason>} (quoted_low=$P_LO)"
	fi

	sleep "$delay"
done

echo
echo "Seed complete. JSONL log → $LOG_FILE"
