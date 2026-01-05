#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
# Deploy contracts to Sepolia using class hashes from output/sepolia/classes.sepolia.env.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

# ---- env & deps ----
[ -f scripts/.env.example ] && . scripts/.env.example
[ -f scripts/.env.sepolia.local ] && . scripts/.env.sepolia.local
[ -f scripts/params.sepolia.example ] && . scripts/params.sepolia.example
[ -f scripts/params.sepolia.local ] && . scripts/params.sepolia.local
[ -f output/sepolia/classes.sepolia.env ] && . output/sepolia/classes.sepolia.env

need() { command -v "$1" >/dev/null 2>&1 || {
	echo "Missing: $1" >&2
	exit 1
}; }
need sncast
need jq
need tee
need python3

RPC="${RPC_URL:?set RPC_URL in scripts/.env.sepolia.local}"
PROFILE="${DEPLOY_PROFILE:-${PROFILE:-}}"
[ -n "$PROFILE" ] || { echo "DEPLOY_PROFILE/PROFILE is empty" >&2; exit 1; }
FRI_PER_STRK="${FRI_PER_STRK:-1000000000000000000}"

OUT_DIR="output/sepolia"
mkdir -p "$OUT_DIR"
: >"$OUT_DIR/.gitkeep"
ADDR_FILE="$OUT_DIR/addresses.sepolia.json"
ENV_FILE="$OUT_DIR/addresses.sepolia.env"

require_nonempty() { [ -n "$2" ] || {
	echo "!! $1 is empty" >&2
	exit 1
}; }

json_put() {
	# json_put file key value
	local file="$1" key="$2" val="$3" tmp
	tmp="$(mktemp)"
	if [ -s "$file" ]; then
		jq -S --arg k "$key" --arg v "$val" '(.[$k]=$v)' "$file" >"$tmp"
	else
		jq -S -n --arg k "$key" --arg v "$val" '{($k):$v}' >"$tmp"
	fi
	mv "$tmp" "$file"
}

# encode a UTF-8 string into Cairo ByteArray ABI:
# [num_full_31B_words, pending_word_felt, pending_len]
encode_bytearray() {
	python3 - "$1" <<'PY'
import sys
b = sys.argv[1].encode('utf-8')
full = len(b) // 31
rem  = len(b) % 31
out = []
out.append(str(full))
for i in range(full):
    chunk = b[i*31:(i+1)*31]
    out.append(hex(int.from_bytes(chunk, 'big')))
out.append(hex(int.from_bytes(b[-rem:], 'big')) if rem else "0")
out.append(str(rem))
print(" ".join(out))
PY
}

# decimal/hex → u256 (low high)
u256() {
	python3 - "$1" <<'PY'
import sys
n=int(sys.argv[1],0)
low=n & ((1<<128)-1); high=n>>128
print(low, high)
PY
}

to_fri() { # decimal STRK -> fri (wei-like)
	python3 - "$1" "$FRI_PER_STRK" <<'PY'
import sys
from decimal import Decimal, InvalidOperation, getcontext

raw = sys.argv[1].strip().replace("_", "")
mult = Decimal(sys.argv[2])

if raw.lower().startswith("0x"):
    print(int(raw, 16))
    sys.exit(0)

try:
    if any(c in raw for c in ".eE"):
        getcontext().prec = 80
        val = Decimal(raw)
    else:
        val = Decimal(int(raw, 10))
except (InvalidOperation, ValueError):
    print(f"Invalid STRK amount: {raw}", file=sys.stderr)
    sys.exit(1)

amt = int((val * mult).to_integral_value())
print(amt)
PY
}

# Map sncast profile -> account address in OZ accounts JSON
profile_addr() {
	local name="$1"
	local file="${SNCAST_ACCOUNTS_FILE:?set in scripts/.env.sepolia.local}"
	local ns="${SNCAST_ACCOUNTS_NAMESPACE:-alpha-sepolia}"
	jq -r --arg ns "$ns" --arg name "$name" '.[$ns][$name].address' "$file"
}

# If ADMIN_ADDRESS is blank, derive it from ADMIN_PROFILE
if [ -z "${ADMIN_ADDRESS:-}" ] && [ -n "${ADMIN_PROFILE:-}" ]; then
	ADMIN_ADDRESS="$(profile_addr "$ADMIN_PROFILE")"
fi

require_nonempty ADMIN_ADDRESS "${ADMIN_ADDRESS:-}"
require_nonempty PAYTOKEN "${PAYTOKEN:-}"
require_nonempty TREASURY "${TREASURY:-}"

# ---- require class hashes (already declared) ----
: "${CLASS_NFT:?source output/sepolia/classes.sepolia.env first (missing CLASS_NFT)}"
: "${CLASS_MINTER:?source output/sepolia/classes.sepolia.env first (missing CLASS_MINTER)}"
: "${CLASS_ADAPTER:?source output/sepolia/classes.sepolia.env first (missing CLASS_ADAPTER)}"
: "${CLASS_PULSE:?source output/sepolia/classes.sepolia.env first (missing CLASS_PULSE)}"
: "${CLASS_PATH_LOOK:?source output/sepolia/classes.sepolia.env first (missing CLASS_PATH_LOOK)}"

if [ -z "${PPRF_ADDR:-}" ]; then
	: "${CLASS_PPRF:?source output/sepolia/classes.sepolia.env first (missing CLASS_PPRF)}"
fi
if [ -z "${STEP_CURVE_ADDR:-}" ]; then
	: "${CLASS_STEP_CURVE:?source output/sepolia/classes.sepolia.env first (missing CLASS_STEP_CURVE)}"
fi

# deploy_one VAR_NAME package ContractName class_hash <calldata...>
deploy_one() {
	local envvar="$1" pkg="$2" cname="$3" class="$4"
	shift 4
	local ts out addr
	echo "==> Deploy ${pkg}::${cname}"
	ts="$(date +%F-%H%M%S)"
	out="$OUT_DIR/deploy_${cname}_${ts}.json"

	if [ "$#" -gt 0 ]; then
		addr="$(
			sncast --profile "$PROFILE" --json deploy --url "$RPC" \
				--class-hash "$class" --constructor-calldata "$@" |
				tee "$out" |
				jq -r '.. | objects | (.contract_address? // .deploy?.contract_address? // empty)' |
				head -n1
		)"
	else
		addr="$(
			sncast --profile "$PROFILE" --json deploy --url "$RPC" \
				--class-hash "$class" |
				tee "$out" |
				jq -r '.. | objects | (.contract_address? // .deploy?.contract_address? // empty)' |
				head -n1
		)"
	fi

	[ -n "$addr" ] || {
		echo "!! No contract_address parsed for ${pkg}::${cname} (see $out)" >&2
		exit 1
	}

	printf -v "$envvar" '%s' "$addr"
	export "$envvar"
	json_put "$ADDR_FILE" "$pkg" "$addr"
	printf "%s=%s\n" "$envvar" "$addr"
}

# ---- encode calldata ----
read -r NFT_NAME_C <<<"$(encode_bytearray "$NFT_NAME")"
read -r NFT_SYMBOL_C <<<"$(encode_bytearray "$NFT_SYMBOL")"
read -r NFT_BASEURI_C <<<"$(encode_bytearray "$NFT_BASE_URI")"
read -r FIRST_LOW FIRST_HIGH <<<"$(u256 "$FIRST_TOKEN_ID")"
K_FRI="$(to_fri "$K_DEC")"
GP_FRI="$(to_fri "$GENESIS_P_DEC")"
FL_FRI="$(to_fri "$FLOOR_DEC")"
PTS_FRI="$(to_fri "$PTS")"
read -r K_LOW K_HIGH <<<"$(u256 "$K_FRI")"
read -r GP_LOW GP_HIGH <<<"$(u256 "$GP_FRI")"
read -r FL_LOW FL_HIGH <<<"$(u256 "$FL_FRI")"

# ---- deploy in order ----
if [ -n "${PPRF_ADDR:-}" ]; then
	ADDR_PPRF="$PPRF_ADDR"
	echo "==> Using existing glyph_pprf at $ADDR_PPRF"
else
	deploy_one ADDR_PPRF glyph_pprf Pprf "$CLASS_PPRF"
fi

if [ -n "${STEP_CURVE_ADDR:-}" ]; then
	ADDR_STEP_CURVE="$STEP_CURVE_ADDR"
	echo "==> Using existing step_curve at $ADDR_STEP_CURVE"
else
	deploy_one ADDR_STEP_CURVE step_curve StepCurve "$CLASS_STEP_CURVE"
fi

deploy_one ADDR_LOOK path_look PathLook "$CLASS_PATH_LOOK" "$ADDR_PPRF" "$ADDR_STEP_CURVE"
PATH_LOOK="$ADDR_LOOK"

deploy_one ADDR_NFT path_nft PathNFT "$CLASS_NFT" \
	"$ADMIN_ADDRESS" $NFT_NAME_C $NFT_SYMBOL_C $NFT_BASEURI_C "$PATH_LOOK"

deploy_one ADDR_MINTER path_minter PathMinter "$CLASS_MINTER" \
	"$ADMIN_ADDRESS" "$ADDR_NFT" "$FIRST_LOW" "$FIRST_HIGH" "$RESERVED_CAP"

deploy_one ADDR_ADAPTER path_minter_adapter PathMinterAdapter "$CLASS_ADAPTER" \
	"$ADMIN_ADDRESS" "0x0" "$ADDR_MINTER"

deploy_one ADDR_PULSE pulse_auction PulseAuction "$CLASS_PULSE" \
	"$OPEN_DELAY" "$K_LOW" "$K_HIGH" "$GP_LOW" "$GP_HIGH" "$FL_LOW" "$FL_HIGH" \
	"$PTS_FRI" "$PAYTOKEN" "$TREASURY" "$ADDR_ADAPTER"

# ---- exports for your shell ----
cat >"$ENV_FILE" <<EOF
# generated by scripts/deploy-sepolia.sh
export PATH_NFT=${ADDR_NFT}
export PATH_MINTER=${ADDR_MINTER}
export PATH_ADAPTER=${ADDR_ADAPTER}
export PULSE_AUCTION=${ADDR_PULSE}
export PATH_LOOK=${PATH_LOOK}
export PATH_PPRF=${ADDR_PPRF-}
export PATH_STEP_CURVE=${ADDR_STEP_CURVE-}
export RPC_URL=${RPC}
export PROFILE=${PROFILE}
EOF

echo
echo "Deployed addresses ledger → $ADDR_FILE"
jq -S '.' "$ADDR_FILE" || true
echo "Env exports → $ENV_FILE"
echo 'Load into your current shell with:  source output/sepolia/addresses.sepolia.env'

# ---- generate a deploy params file for reference ----
jq -n \
	--arg admin "$ADMIN_ADDRESS" \
	--arg name "$NFT_NAME" \
	--arg sym "$NFT_SYMBOL" \
	--arg base "$NFT_BASE_URI" \
	--arg path_look "$PATH_LOOK" \
	--argjson first_low "$FIRST_LOW" --argjson first_high "$FIRST_HIGH" \
	--argjson k_low "$K_LOW" --argjson k_high "$K_HIGH" \
	--argjson gp_low "$GP_LOW" --argjson gp_high "$GP_HIGH" \
	--argjson fl_low "$FL_LOW" --argjson fl_high "$FL_HIGH" \
	--arg pts "$PTS" --arg pay "$PAYTOKEN" --arg tre "$TREASURY" \
	--arg salt_nft "${SALT_NFT-}" \
	--arg salt_minter "${SALT_MINTER-}" \
	--arg salt_adapter "${SALT_ADAPTER-}" \
	--arg salt_pulse "${SALT_PULSE-}" \
	'{
     admin: $admin,
     nft:   { name:$name, symbol:$sym, base_uri:$base, path_look:$path_look },
     minter:{ first_token_id:{low:$first_low, high:$first_high} },
     pulse: { k:{low:$k_low, high:$k_high},
              genesis_price:{low:$gp_low, high:$gp_high},
              floor:{low:$fl_low, high:$fl_high},
              pts:$pts, payment_token:$pay, treasury:$tre },
     salts: { nft:$salt_nft, minter:$salt_minter, adapter:$salt_adapter, pulse:$salt_pulse }
   }' >"$OUT_DIR/deploy.params.sepolia.json"
