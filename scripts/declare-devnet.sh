#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"

# Idempotent enough: build -> declare -> write output files
set -euo pipefail
LOCALNET_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
PATH_REPO="${PATH_REPO:-$LOCALNET_DIR/../path}"
cd -- "$LOCALNET_DIR"

# ---- env & deps ----
[ -f scripts/.env.example ] && . scripts/.env.example
[ -f scripts/.env.local ] && . scripts/.env.local

need() { command -v "$1" >/dev/null 2>&1 || {
	echo "Missing dependency: $1" >&2
	exit 1
}; }
need scarb
need sncast
need jq
need tee
need curl

RPC="${RPC_URL:-http://127.0.0.1:5050/rpc}"
PROFILE="${PROFILE:-dev_deployer}"
ACCOUNTS_FILE="${SNCAST_ACCOUNTS_FILE:-/Users/bigu/Projects/localnet/.accounts/devnet_oz_accounts.json}"
ACCOUNT_NAME="${SNCAST_ACCOUNT_NAME:-${PROFILE:-dev_deployer}}"
ACCOUNTS_FILE_ABS="$(
	python3 - "$ACCOUNTS_FILE" <<'PY'
import os
import sys
print(os.path.abspath(sys.argv[1]))
PY
)"

OUT_DIR="output"
OUT_DIR_ABS="$(pwd)/$OUT_DIR"
mkdir -p "$OUT_DIR"
: >"$OUT_DIR/.gitkeep"
mkdir -p "$OUT_DIR/scarb-cache"
CLASSES_FILE="$OUT_DIR/classes.devnet.json"
ENV_FILE="$OUT_DIR/classes.env"

json_put() {
	# json_put key value -> writes to $CLASSES_FILE
	local key="$1" val="$2" tmp
	tmp="$(mktemp)"
	if [ -f "$CLASSES_FILE" ]; then
		jq -S --arg k "$key" --arg v "$val" '.[$k]=$v' "$CLASSES_FILE" >"$tmp"
	else
		jq -S -n --arg k "$key" --arg v "$val" '{($k):$v}' >"$tmp"
	fi
	mv "$tmp" "$CLASSES_FILE"
}

# class_hash_from_pkg <package> <ContractName>
class_hash_from_pkg() {
	local pkg="$1" cname="$2"
	(
		cd "$PATH_REPO" &&
			sncast utils class-hash --package "$pkg" --contract-name "$cname" |
				awk '/Class Hash:/ {print $3}' |
				tail -n1
	)
}

# class_hash_from_dir <dir> <ContractName>
class_hash_from_dir() {
	local dir="$1" cname="$2"
	(
		cd "$dir" &&
			sncast utils class-hash --contract-name "$cname" |
				awk '/Class Hash:/ {print $3}' |
				tail -n1
	)
}

# declare_pkg <ENV_VAR> <package> <ContractName>
declare_pkg() {
	local envvar="$1" pkg="$2" cname="$3"
	local ts out ch
	echo "==> Declare ${pkg}::${cname}"
	ts="$(date +%F-%H%M%S)"
	out="$OUT_DIR/declare_${cname}_${ts}.json"

	# Stream style: sncast -> tee (save raw) -> jq picks last non-empty class_hash
	ch="$(
		set +e
		(
			cd "$PATH_REPO" &&
				sncast --profile "$PROFILE" --json declare \
					--package "$pkg" --contract-name "$cname"
		) |
			tee "$out" |
			jq -r '.class_hash // .declare.class_hash // empty' |
			tail -n1
		exit 0
	)"

	if [ -z "$ch" ]; then
		ch="$(class_hash_from_pkg "$pkg" "$cname")"
	fi

	[ -n "$ch" ] || {
		echo "!! No class_hash parsed for ${pkg}::${cname}" >&2
		exit 1
	}

	# export ENV var and update ledger keyed by package
	printf -v "$envvar" '%s' "$ch"
	export "$envvar"
	json_put "$pkg" "$ch"
	printf "%s=%s\n" "$envvar" "$ch"
	echo "Class hash written to $out as $ch for ${pkg}::${cname}"
}

# declare_dir <ENV_VAR> <package> <ContractName> <dir>
declare_dir() {
	local envvar="$1" pkg="$2" cname="$3" dir="$4"
	local ts out ch target_dir
	echo "==> Declare ${pkg}::${cname}"
	ts="$(date +%F-%H%M%S)"
	out="$OUT_DIR/declare_${cname}_${ts}.json"
	target_dir="$OUT_DIR_ABS/scarb-cache/${pkg}"

	ch="$(
		set +e
		(
			cd "$dir" &&
				SCARB_TARGET_DIR="$target_dir" sncast --json \
					--account "$ACCOUNT_NAME" \
					--accounts-file "$ACCOUNTS_FILE_ABS" \
					declare --contract-name "$cname" --url "$RPC"
		) |
			tee "$out" |
			jq -r '.class_hash // .declare.class_hash // empty' |
			tail -n1
		exit 0
	)"

	if [ -z "$ch" ]; then
		ch="$(SCARB_TARGET_DIR="$target_dir" class_hash_from_dir "$dir" "$cname")"
	fi

	[ -n "$ch" ] || {
		echo "!! No class_hash parsed for ${pkg}::${cname}" >&2
		exit 1
	}

	printf -v "$envvar" '%s' "$ch"
	export "$envvar"
	json_put "$pkg" "$ch"
	printf "%s=%s\n" "$envvar" "$ch"
	echo "Class hash written to $out as $ch for ${pkg}::${cname}"
}

echo "==> Building workspace"
(cd "$PATH_REPO" && scarb build >/dev/null)

# ---- explicit declarations (stream-based) ----
declare_pkg CLASS_NFT path_nft PathNFT
declare_pkg CLASS_MINTER path_minter PathMinter
declare_pkg CLASS_ADAPTER path_minter_adapter PathMinterAdapter
declare_pkg CLASS_PULSE pulse_auction PulseAuction

# ---- path_look + deps (separate Scarb project) ----
PATH_LOOK_DIR="$PATH_REPO/contracts/path_look/contracts"
PATH_LOOK_META="$(cd "$PATH_LOOK_DIR" && scarb metadata --format-version 1)"
PPRF_ROOT="$(jq -r '.packages[] | select(.name=="glyph_pprf") | .root' <<<"$PATH_LOOK_META" | head -n1)"
STEP_CURVE_ROOT="$(jq -r '.packages[] | select(.name=="step_curve") | .root' <<<"$PATH_LOOK_META" | head -n1)"

[ -n "$PPRF_ROOT" ] || {
	echo "!! Could not resolve glyph_pprf from ${PATH_LOOK_DIR}" >&2
	exit 1
}
[ -n "$STEP_CURVE_ROOT" ] || {
	echo "!! Could not resolve step_curve from ${PATH_LOOK_DIR}" >&2
	exit 1
}

declare_dir CLASS_PPRF glyph_pprf Pprf "$PPRF_ROOT"
declare_dir CLASS_STEP_CURVE step_curve StepCurve "$STEP_CURVE_ROOT"
declare_dir CLASS_PATH_LOOK path_look PathLook "$PATH_LOOK_DIR"

# ---- write a sourceable env file for later shells ----
cat >"$ENV_FILE" <<EOF
# generated by scripts/declare-devnet.sh
export CLASS_NFT=${CLASS_NFT}
export CLASS_MINTER=${CLASS_MINTER}
export CLASS_ADAPTER=${CLASS_ADAPTER}
export CLASS_PULSE=${CLASS_PULSE}
export CLASS_PPRF=${CLASS_PPRF}
export CLASS_STEP_CURVE=${CLASS_STEP_CURVE}
export CLASS_PATH_LOOK=${CLASS_PATH_LOOK}
EOF

echo
echo "Declared class hashes ledger → $CLASSES_FILE"
jq -S '.' "$CLASSES_FILE" || true
echo "Env exports → $ENV_FILE"
echo 'Load into your current shell with:  source output/classes.env'
