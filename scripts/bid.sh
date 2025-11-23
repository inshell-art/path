#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

# Pulse bidding loop: auto-derive last sale state from the devnet PulseAuction,
# compute trigger τ via the spec, bid with a max_price guard, and repeat N times.
# Usage: ./scripts/bid.sh [COUNT]

[ -f scripts/.env.example ] && . scripts/.env.example
[ -f scripts/.env.local ] && . scripts/.env.local
[ -f scripts/params.devnet.example ] && . scripts/params.devnet.example
[ -f output/addresses.env ] && . output/addresses.env

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
need sncast
need jq
need python3
need curl

COUNT="${1:-1}"
PROFILE_BIDDER="${PROFILE_BIDDER:-dev_bidder1}"
RPC="${RPC_URL:-http://127.0.0.1:5050/rpc}"
PAYTOKEN="${PAYTOKEN:?set PAYTOKEN or source env files}"
PULSE_AUCTION="${PULSE_AUCTION:?set PULSE_AUCTION or source env files}"
ACCOUNTS_FILE="${SNCAST_ACCOUNTS_FILE:-.accounts/devnet_oz_accounts.json}"
ACCT_NS="${SNCAST_ACCOUNTS_NAMESPACE:-alpha-sepolia}"
BIDDER_ADDR="$(jq -r --arg ns "$ACCT_NS" --arg p "$PROFILE_BIDDER" '.[$ns][$p].address' "$ACCOUNTS_FILE")"

# Config (logic in STRK units)
K_STRK_SECONDS="${K_STRK_SECONDS:-1000000}"
THETA="${THETA:-0.04}"
THETA_MEAN="${THETA_MEAN:-0.04}"
THETA_SD="${THETA_SD:-0.01}"
THETA_MIN="${THETA_MIN:-0.02}"
THETA_MAX="${THETA_MAX:-0.06}"
MIN_TAU_SEC="${MIN_TAU_SEC:-60}"
SLIPPAGE_BPS="${SLIPPAGE_BPS:-30}"
GENESIS_FLOOR_STRK="${GENESIS_FLOOR_STRK:-1000}"
EPOCH2_TAU_SEC="${EPOCH2_TAU_SEC:-}" # optional manual τ for epoch 2

echo "==> Starting Pulse bid loop (count=$COUNT)"
echo "RPC=$RPC profile=$PROFILE_BIDDER bidder=$BIDDER_ADDR"

rpc_base="${RPC%/rpc}"
alive="$(curl -sf "$rpc_base/is_alive" 2>/dev/null || true)"
if [ "$alive" != "Alive!!!" ]; then
	echo "Devnet RPC not alive at $RPC" >&2
	exit 1
fi

dec_of_hex() { python3 - "$1" <<'PY'
import sys
s=sys.argv[1]
if s.startswith(("0x","0X")):
    print(int(s,16))
else:
    print(int(s))
PY
}
wei_to_strk() { python3 - "$1" <<'PY'
import sys, decimal
decimal.getcontext().prec = 60
w=int(sys.argv[1]); print(float(decimal.Decimal(w)/(decimal.Decimal(10)**18)))
PY
}

fetch_sales_json="$(curl -sS -H 'Content-Type: application/json' \
	-d '{"jsonrpc":"2.0","method":"starknet_getEvents","params":[{"address":"'"$PULSE_AUCTION"'","from_block":{"block_number":0},"to_block":"latest","keys":[],"chunk_size":40}],"id":1}' \
	"$RPC")"

sales_state="$(python3 - "$fetch_sales_json" "$GENESIS_FLOOR_STRK" <<'PY'
import sys, json, decimal
decimal.getcontext().prec = 80
resp=json.loads(sys.argv[1])
events=resp.get("result",{}).get("events",[])
if not events:
    print(json.dumps({"has_sales": False}))
    sys.exit(0)

def decode(ev):
    d=ev["data"]
    price = int(d[0],16) + (int(d[1],16)<<128)
    ts = int(d[2],16)
    anchor = int(d[3],16)
    floor = int(d[4],16) + (int(d[5],16)<<128)
    epoch = int(d[6],16)
    return {"price":price,"ts":ts,"anchor":anchor,"floor":floor,"epoch":epoch}

decoded=[decode(e) for e in events if len(e.get("data",[]))>=7]
if not decoded:
    print(json.dumps({"has_sales": False}))
    sys.exit(0)
last=decoded[-1]
prev=decoded[-2] if len(decoded)>=2 else None
genesis_floor=int(sys.argv[2])

out={
    "has_sales": True,
    "last_price": last["price"],
    "last_ts": last["ts"],
    "last_floor": last["floor"],
    "last_epoch": last["epoch"],
    "prev_ts": prev["ts"] if prev else None,
    "prev_price": prev["price"] if prev else None,
    "prev_epoch": prev["epoch"] if prev else None,
    "genesis_floor": genesis_floor
}
print(json.dumps(out))
PY
)"

if [ "$(jq -r '.has_sales' <<<"$sales_state")" != "true" ]; then
	echo "No sales found; cannot derive state."
	exit 1
fi

last_ts="$(jq -r '.last_ts' <<<"$sales_state")"
last_price_wei="$(jq -r '.last_price' <<<"$sales_state")"
last_price_strk="$(wei_to_strk "$last_price_wei")"
prev_ts="$(jq -r '.prev_ts // empty' <<<"$sales_state")"
last_epoch="$(jq -r '.last_epoch' <<<"$sales_state")"

if [ -n "$prev_ts" ]; then
	last_tau_sec="$((last_ts - prev_ts))"
	floor_strk="$last_price_strk"
	epoch_index="$((last_epoch + 1))"
else
	last_tau_sec=""
	floor_strk="$GENESIS_FLOOR_STRK"
	epoch_index=2
fi

allow_json="$(sncast --profile "$PROFILE_BIDDER" --json call --contract-address "$PAYTOKEN" --function allowance --calldata "$BIDDER_ADDR" "$PULSE_AUCTION")"
allow_raw="$(jq -r '.response_raw[0] // .response[0] // "0x0"' <<<"$allow_json")"
allow_dec="$(dec_of_hex "$allow_raw")"

echo "Derived state:"
echo "  epoch_index=$epoch_index last_price=${last_price_strk}STRK last_ts=$last_ts prev_ts=${prev_ts:-n/a} last_tau=${last_tau_sec:-n/a} allow_wei=$allow_dec"

for ((i=1; i<=COUNT; i++)); do
	echo
	echo "=== Bid $i/$COUNT ==="
	theta_use="$(python3 - "$THETA_MEAN" "$THETA_SD" "$THETA_MIN" "$THETA_MAX" <<'PY'
import sys, random
mean=float(sys.argv[1]); sd=float(sys.argv[2]); lo=float(sys.argv[3]); hi=float(sys.argv[4])
while True:
    val=random.normalvariate(mean, sd)
    if lo <= val <= hi:
        print(val)
        break
PY
)"

	calc_json="$(python3 - "$K_STRK_SECONDS" "$theta_use" "$floor_strk" "$MIN_TAU_SEC" "$epoch_index" "$last_tau_sec" "$EPOCH2_TAU_SEC" "$SLIPPAGE_BPS" <<'PY'
import sys, json, math, decimal
from decimal import Decimal, ROUND_HALF_UP
decimal.getcontext().prec = 80

k=Decimal(sys.argv[1]); theta=Decimal(sys.argv[2]); floor=Decimal(sys.argv[3]); min_tau=Decimal(sys.argv[4])
epoch=int(sys.argv[5]); last_tau=Decimal(sys.argv[6]) if sys.argv[6] else None
epoch2_tau=Decimal(sys.argv[7]) if sys.argv[7] else None
slip_bps=Decimal(sys.argv[8])

if epoch==2:
    if epoch2_tau:
        tau=epoch2_tau
        theta_eff=k/(tau*floor)
    else:
        tau=k/(theta*floor)
        theta_eff=theta
    premium=k/tau
else:
    if not last_tau or last_tau<=0:
        raise SystemExit("last_tau required for epoch>=3")
    tau_star=k/(theta*floor)-k/last_tau
    if tau_star<=0:
        tau=min_tau
        theta_eff=k/(floor*(tau+k/last_tau))
    else:
        tau=tau_star
        theta_eff=theta
    premium=k/(tau+k/last_tau)
hammer=floor+premium
max_price=hammer*(Decimal(1)+slip_bps/Decimal(10000))
wei=(max_price*(Decimal(10)**18)).to_integral_value(rounding=ROUND_HALF_UP)
low=int(wei%(1<<128)); high=int(wei//(1<<128))
res={
    "tau": float(tau),
    "premium": float(premium),
    "hammer": float(hammer),
    "theta_eff": float(theta_eff),
    "max_price_wei": str(int(wei)),
    "u256": {"low": str(low),"high": str(high)}
}
print(json.dumps(res))
PY
)"
	tau="$(jq -r '.tau' <<<"$calc_json")"
	premium="$(jq -r '.premium' <<<"$calc_json")"
	hammer="$(jq -r '.hammer' <<<"$calc_json")"
	theta_eff="$(jq -r '.theta_eff' <<<"$calc_json")"
	max_price_wei="$(jq -r '.max_price_wei' <<<"$calc_json")"
	max_lo="$(jq -r '.u256.low' <<<"$calc_json")"
	max_hi="$(jq -r '.u256.high' <<<"$calc_json")"

	echo "floor=$floor_strk θ_eff=$theta_eff τ_target=$tau premium=$premium hammer=$hammer"

	# Fetch current ask to avoid max_price < ask (ASK_ABOVE_MAX_PRICE)
	ask_json="$(sncast --profile "$PROFILE_BIDDER" --json call --contract-address "$PULSE_AUCTION" --function get_current_price)"
	ask_lo="$(jq -r '.response_raw[0] // .response[0]' <<<"$ask_json")"
	ask_hi="$(jq -r '.response_raw[1] // .response[1]' <<<"$ask_json")"
	current_ask_wei="$(python3 - "$ask_hi" "$ask_lo" <<'PY'
import sys
hi=int(sys.argv[1],16) if str(sys.argv[1]).startswith(("0x","0X")) else int(sys.argv[1])
lo=int(sys.argv[2],16) if str(sys.argv[2]).startswith(("0x","0X")) else int(sys.argv[2])
print((hi<<128)+lo)
PY
)"
	max_before="$max_price_wei"
	max_price_wei="$(python3 - "$current_ask_wei" "$max_price_wei" <<'PY'
import sys
ask=int(sys.argv[1]); mp=int(sys.argv[2]); print(max(ask, mp))
PY
)"
	if python3 - "$max_before" "$max_price_wei" <<'PY'
import sys
a=int(sys.argv[1]); b=int(sys.argv[2]); sys.exit(0 if a!=b else 1)
PY
	then
		echo "Raised max_price to current ask to avoid guard failure (ask wei=$current_ask_wei)."
	fi
	max_lo="$(python3 - "$max_price_wei" <<'PY'
import sys
w=int(sys.argv[1]); print(w & ((1<<128)-1))
PY
)"
	max_hi="$(python3 - "$max_price_wei" <<'PY'
import sys
w=int(sys.argv[1]); print(w>>128)
PY
)"

	# Pre-bid balance check
	balance_json="$(sncast --profile "$PROFILE_BIDDER" --json call --contract-address "$PAYTOKEN" --function balance_of --calldata "$BIDDER_ADDR")"
	balance_raw="$(jq -r '.response_raw[0] // .response[0] // "0x0"' <<<"$balance_json")"
	balance_dec="$(dec_of_hex "$balance_raw")"
	if ! python3 - "$balance_dec" "$max_price_wei" <<'PY'
import sys
bal=int(sys.argv[1]); need=int(sys.argv[2]); sys.exit(0 if bal>=need else 1)
PY
	then
		echo "Balance too low (have $balance_dec wei, need $max_price_wei); skipping this bid."
		continue
	fi

	if ! python3 - "$allow_dec" "$max_price_wei" <<'PY'
import sys
allow=int(sys.argv[1]); need=int(sys.argv[2]); sys.exit(0 if allow>=need else 1)
PY
	then
		echo "Allowance too low (have $allow_dec, need $max_price_wei); please approve before rerun."
		echo "Needed u256: lo=$(python3 - \"$max_price_wei\" <<'PP'\nimport sys\nw=int(sys.argv[1]); print(w & ((1<<128)-1))\nPP\n) hi=$(python3 - \"$max_price_wei\" <<'PP'\nimport sys\nw=int(sys.argv[1]); print(w>>128)\nPP\n)"
		exit 1
	fi

	target_ts=$(python3 - "$last_ts" "$tau" <<'PY'
import sys, time, decimal
decimal.getcontext().prec=40
last=int(sys.argv[1]); tau=decimal.Decimal(sys.argv[2])
target=decimal.Decimal(last)+tau
now=decimal.Decimal(time.time())
print(float(target-now))
PY
)
	if awk "BEGIN{exit !($target_ts>0)}"; then
		target_abs=$(python3 - "$last_ts" "$tau" <<'PY'
import sys, time, decimal
decimal.getcontext().prec=40
last=int(sys.argv[1]); tau=decimal.Decimal(sys.argv[2])
target=decimal.Decimal(last)+tau
print(int(target.to_integral_value(rounding=decimal.ROUND_HALF_UP)))
PY
)
		echo "Sleeping to target (live countdown)..."
		while :; do
			now=$(date +%s)
			rem=$((target_abs - now))
			[ "$rem" -le 0 ] && break
			h=$((rem/3600))
			m=$(((rem%3600)/60))
			s=$((rem%60))
			printf "\rSleeping %02d:%02d:%02d to target..." "$h" "$m" "$s"
			sleep 1
		done
		printf "\r\033[K"
	else
		printf "Target time passed by %.3f sec; sending now.\n" "$(echo "$target_ts" | awk '{print -$1}')"
	fi

	tx="$(sncast --profile "$PROFILE_BIDDER" --json invoke --contract-address "$PULSE_AUCTION" --function bid --calldata "$max_lo" "$max_hi" | jq -r '.transaction_hash // empty')"
	[ -n "$tx" ] || { echo "submit failed"; exit 1; }
	echo "tx=$tx"

	receipt="$(curl -sS -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"starknet_getTransactionReceipt","params":["'"$tx"'"],"id":1}' "$RPC")"
	block_hash="$(jq -r '.result.block_hash // empty' <<<"$receipt")"
	[ -n "$block_hash" ] || { echo "no receipt yet"; exit 1; }
	block_raw="$(curl -sS -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"starknet_getBlockWithTxs","params":[{"block_hash":"'"$block_hash"'"}],"id":1}' "$RPC")"
	block_ts_hex="$(jq -r '.result.timestamp // "0x0"' <<<"$block_raw")"
	block_ts="$(dec_of_hex "$block_ts_hex")"
	measured_tau="$((block_ts - last_ts))"

	# Decode Sale event from receipt for hammer
	sale_json="$(python3 - "$receipt" <<'PY'
import sys, json
rc=json.loads(sys.argv[1])
evs=rc.get("result",{}).get("events",[])
sale=None
for ev in evs:
    data=ev.get("data",[])
    if len(data)>=7:
        sale=data; break
if sale is None:
    print("{}"); sys.exit(0)
price=int(sale[0],16)+(int(sale[1],16)<<128)
ts=int(sale[2],16)
floor=int(sale[4],16)+(int(sale[5],16)<<128)
epoch=int(sale[6],16)
print(json.dumps({"price":price,"ts":ts,"floor":floor,"epoch":epoch}))
PY
)"
	new_price_wei="$(jq -r '.price' <<<"$sale_json")"
	new_price_strk="$(wei_to_strk "${new_price_wei:-0}")"
	new_floor_strk="${new_price_strk:-$floor_strk}"

	echo "Settled at ts=$block_ts (measured τ=$measured_tau) hammer=${new_price_strk:-?} STRK"

	python3 - "$K_STRK_SECONDS" "$floor_strk" "$measured_tau" "$last_tau_sec" "$new_price_strk" <<'PY'
import sys, decimal
decimal.getcontext().prec=80
k=decimal.Decimal(sys.argv[1]); floor=decimal.Decimal(sys.argv[2]); tau=decimal.Decimal(sys.argv[3])
last_tau = decimal.Decimal(sys.argv[4]) if sys.argv[4] not in ("","None") else None
hammer=decimal.Decimal(sys.argv[5])
if last_tau:
    premium=k/(tau+k/last_tau)
else:
    premium=k/tau
theta_real=(hammer-floor)/floor
resid=(hammer-floor)-premium
print(f"[post-check] premium_exp={premium} theta_real={theta_real} resid={resid}")
PY

	log_path="${PULSE_LOG_PATH:-output/pulse_runs.jsonl}"
	mkdir -p "$(dirname "$log_path")"
	jq -nc \
		--arg epoch "$epoch_index" \
		--arg tx "$tx" \
		--arg floor "$floor_strk" \
		--arg last_tau "${last_tau_sec:-""}" \
		--arg tau "$tau" \
		--arg tau_measured "$measured_tau" \
		--arg hammer "$new_price_strk" \
		--arg theta "$theta_eff" \
		--arg block_ts "$block_ts" \
		'{
			epoch: ($epoch|tonumber),
			tx: $tx,
			floor_strk: ($floor|tonumber),
			last_tau_sec: ($last_tau|tonumber?),
			tau_sec_target: ($tau|tonumber),
			tau_sec_measured: ($tau_measured|tonumber),
			hammer_strk: ($hammer|tonumber),
			theta_effective: ($theta|tonumber),
			block_timestamp: ($block_ts|tonumber)
		}' >>"$log_path"

	# State update for next loop
	last_tau_sec="$measured_tau"
	last_ts="$block_ts"
	floor_strk="$new_floor_strk"
	epoch_index="$((epoch_index + 1))"
done

echo "Done. Logs → ${PULSE_LOG_PATH:-output/pulse_runs.jsonl}"
