#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"

# Idempotent enough: build -> declare -> write output files for Sepolia.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

# ---- env & deps ----
[ -f scripts/.env.example ] && . scripts/.env.example
[ -f scripts/.env.sepolia.local ] && . scripts/.env.sepolia.local
[ -f scripts/params.sepolia.local ] && . scripts/params.sepolia.local

need() { command -v "$1" >/dev/null 2>&1 || {
	echo "Missing dependency: $1" >&2
	exit 1
}; }
need scarb
need sncast
need jq
need tee
need curl
need python3

RPC="${RPC_URL:?set RPC_URL in scripts/.env.sepolia.local}"
PROFILE="${DECLARE_PROFILE:-${PROFILE:-}}"
[ -n "$PROFILE" ] || { echo "DECLARE_PROFILE/PROFILE is empty" >&2; exit 1; }

ACCOUNTS_FILE="${SNCAST_ACCOUNTS_FILE:?set SNCAST_ACCOUNTS_FILE in scripts/.env.sepolia.local}"
ACCOUNT_NAME="${SNCAST_ACCOUNT_NAME:-$PROFILE}"
SNCAST_ACCOUNTS_NAMESPACE="${SNCAST_ACCOUNTS_NAMESPACE:-alpha-sepolia}"
USE_PY_DECLARE_V3="${USE_PY_DECLARE_V3:-}"
if [ -z "$USE_PY_DECLARE_V3" ] && [[ "$RPC" == *"/v0_10/"* ]]; then
	USE_PY_DECLARE_V3="1"
fi
ACCOUNTS_FILE_ABS="$(
	python3 - "$ACCOUNTS_FILE" <<'PY'
import os
import sys
print(os.path.abspath(sys.argv[1]))
PY
)"

OUT_DIR="output/sepolia"
OUT_DIR_ABS="$(pwd)/$OUT_DIR"
mkdir -p "$OUT_DIR" "$OUT_DIR/scarb-cache"
: >"$OUT_DIR/.gitkeep"
CLASSES_FILE="$OUT_DIR/classes.sepolia.json"
ENV_FILE="$OUT_DIR/classes.sepolia.env"

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
	sncast utils class-hash --package "$pkg" --contract-name "$cname" |
		awk '/Class Hash:/ {print $3}' |
		tail -n1
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

# declare_pkg_v3 <ENV_VAR> <package> <ContractName> <target_dir>
declare_pkg_v3() {
	local envvar="$1" pkg="$2" cname="$3" target_dir="$4"
	local ts out ch sierra casm
	echo "==> Declare ${pkg}::${cname} (v3)"
	ts="$(date +%F-%H%M%S)"
	out="$OUT_DIR/declare_${cname}_${ts}.json"
	sierra="${target_dir}/${pkg}_${cname}.contract_class.json"
	casm="${target_dir}/${pkg}_${cname}.compiled_contract_class.json"

	[ -f "$sierra" ] || { echo "!! Missing sierra artifact: $sierra" >&2; exit 1; }
	[ -f "$casm" ] || { echo "!! Missing casm artifact: $casm" >&2; exit 1; }

	ch="$(
		python3 scripts/sepolia_declare_v3.py \
			--rpc "$RPC" \
			--accounts-file "$ACCOUNTS_FILE_ABS" \
			--namespace "$SNCAST_ACCOUNTS_NAMESPACE" \
			--account "$ACCOUNT_NAME" \
			--sierra "$sierra" \
			--casm "$casm" \
			--chain sepolia |
			tee "$out" |
			jq -r '.class_hash // empty' |
			tail -n1
	)"

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

# declare_pkg <ENV_VAR> <package> <ContractName>
declare_pkg() {
	local envvar="$1" pkg="$2" cname="$3"
	local ts out ch
	echo "==> Declare ${pkg}::${cname}"
	ts="$(date +%F-%H%M%S)"
	out="$OUT_DIR/declare_${cname}_${ts}.json"

	ch="$(
		set +e
		sncast --profile "$PROFILE" --json declare --url "$RPC" \
			--package "$pkg" --contract-name "$cname" |
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
scarb build >/dev/null

# ---- explicit declarations ----
if [ "$USE_PY_DECLARE_V3" = "1" ]; then
	if [ -n "${CLASS_NFT:-}" ]; then
		echo "==> Using existing path_nft class hash"
		json_put "path_nft" "$CLASS_NFT"
	else
		declare_pkg_v3 CLASS_NFT path_nft PathNFT "$(pwd)/target/dev"
	fi

	if [ -n "${CLASS_MINTER:-}" ]; then
		echo "==> Using existing path_minter class hash"
		json_put "path_minter" "$CLASS_MINTER"
	else
		declare_pkg_v3 CLASS_MINTER path_minter PathMinter "$(pwd)/target/dev"
	fi

	if [ -n "${CLASS_ADAPTER:-}" ]; then
		echo "==> Using existing path_minter_adapter class hash"
		json_put "path_minter_adapter" "$CLASS_ADAPTER"
	else
		declare_pkg_v3 CLASS_ADAPTER path_minter_adapter PathMinterAdapter "$(pwd)/target/dev"
	fi
else
	if [ -n "${CLASS_NFT:-}" ]; then
		echo "==> Using existing path_nft class hash"
		json_put "path_nft" "$CLASS_NFT"
	else
		declare_pkg CLASS_NFT path_nft PathNFT
	fi
	if [ -n "${CLASS_MINTER:-}" ]; then
		echo "==> Using existing path_minter class hash"
		json_put "path_minter" "$CLASS_MINTER"
	else
		declare_pkg CLASS_MINTER path_minter PathMinter
	fi
	if [ -n "${CLASS_ADAPTER:-}" ]; then
		echo "==> Using existing path_minter_adapter class hash"
		json_put "path_minter_adapter" "$CLASS_ADAPTER"
	else
		declare_pkg CLASS_ADAPTER path_minter_adapter PathMinterAdapter
	fi
fi

if [ -n "${CLASS_PULSE:-}" ]; then
	echo "==> Using existing pulse_auction class hash"
	json_put "pulse_auction" "$CLASS_PULSE"
else
	if [ "$USE_PY_DECLARE_V3" = "1" ]; then
		declare_pkg_v3 CLASS_PULSE pulse_auction PulseAuction "$(pwd)/target/dev"
	else
		declare_pkg CLASS_PULSE pulse_auction PulseAuction
	fi
fi

# ---- path_look + deps (separate Scarb project) ----
PATH_LOOK_DIR="contracts/path_look/contracts"
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

if [ "$USE_PY_DECLARE_V3" = "1" ]; then
	target_dir="$OUT_DIR_ABS/scarb-cache/path_look"
	(
		cd "$PATH_LOOK_DIR" &&
			SCARB_TARGET_DIR="$target_dir" scarb build >/dev/null
	)
	target_release="$target_dir/dev"

	if [ -z "${PPRF_ADDR:-}" ]; then
		declare_pkg_v3 CLASS_PPRF glyph_pprf Pprf "$target_release"
	else
		echo "==> Skipping glyph_pprf declare (PPRF_ADDR set)"
	fi

	if [ -z "${STEP_CURVE_ADDR:-}" ]; then
		declare_pkg_v3 CLASS_STEP_CURVE step_curve StepCurve "$target_release"
	else
		echo "==> Skipping step_curve declare (STEP_CURVE_ADDR set)"
	fi

	if [ -n "${CLASS_PATH_LOOK:-}" ]; then
		echo "==> Using existing path_look class hash"
		json_put "path_look" "$CLASS_PATH_LOOK"
	else
		declare_pkg_v3 CLASS_PATH_LOOK path_look PathLook "$target_release"
	fi
else
	declare_dir CLASS_PPRF glyph_pprf Pprf "$PPRF_ROOT"
	declare_dir CLASS_STEP_CURVE step_curve StepCurve "$STEP_CURVE_ROOT"
	if [ -n "${CLASS_PATH_LOOK:-}" ]; then
		echo "==> Using existing path_look class hash"
		json_put "path_look" "$CLASS_PATH_LOOK"
	else
		declare_dir CLASS_PATH_LOOK path_look PathLook "$PATH_LOOK_DIR"
	fi
fi

# ---- write a sourceable env file for later shells ----
cat >"$ENV_FILE" <<EOF
# generated by scripts/declare-sepolia.sh
export CLASS_NFT=${CLASS_NFT}
export CLASS_MINTER=${CLASS_MINTER}
export CLASS_ADAPTER=${CLASS_ADAPTER}
export CLASS_PULSE=${CLASS_PULSE}
export CLASS_PPRF=${CLASS_PPRF-}
export CLASS_STEP_CURVE=${CLASS_STEP_CURVE-}
export CLASS_PATH_LOOK=${CLASS_PATH_LOOK}
EOF

echo
echo "Declared class hashes ledger → $CLASSES_FILE"
jq -S '.' "$CLASSES_FILE" || true
echo "Env exports → $ENV_FILE"
echo 'Load into your current shell with:  source output/sepolia/classes.sepolia.env'
