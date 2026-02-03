#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/devnet/00_env.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/devnet/_helpers.sh"

need sncast
need jq
need python3

PARAMS_EXAMPLE="$ROOT_DIR/scripts/params.devnet.example"
PARAMS_LOCAL="$ROOT_DIR/scripts/params.devnet.local"
[ -f "$PARAMS_EXAMPLE" ] && source "$PARAMS_EXAMPLE"
[ -f "$PARAMS_LOCAL" ] && source "$PARAMS_LOCAL"

OPEN_DELAY="${OPEN_DELAY:-0}"
K_DEC="${K_DEC:-1000000}"
GENESIS_P_DEC="${GENESIS_P_DEC:-10000}"
FLOOR_DEC="${FLOOR_DEC:-1000}"
PTS="${PTS:-1}"
PAYTOKEN="${PAYTOKEN:-}"
TREASURY="${TREASURY:-}"

[ -n "$PAYTOKEN" ] || { echo "Missing PAYTOKEN" >&2; exit 1; }
[ -n "$TREASURY" ] || { echo "Missing TREASURY" >&2; exit 1; }

ADAPTER_ADDR="${PATH_ADAPTER:-$(addr_from_file path_minter_adapter)}"
[ -n "$ADAPTER_ADDR" ] || { echo "Missing path_minter_adapter address" >&2; exit 1; }

K_FRI="$(to_fri "$K_DEC")"
GP_FRI="$(to_fri "$GENESIS_P_DEC")"
FL_FRI="$(to_fri "$FLOOR_DEC")"
PTS_FRI="$(to_fri "$PTS")"
read -r K_LOW K_HIGH <<<"$(u256_split "$K_FRI")"
read -r GP_LOW GP_HIGH <<<"$(u256_split "$GP_FRI")"
read -r FL_LOW FL_HIGH <<<"$(u256_split "$FL_FRI")"

PULSE_DECL="$(sncast_declare_json_pkg pulse_auction PulseAuction)"
CLASS_PULSE="$(printf '%s\n' "$PULSE_DECL" | json_class_hash)"
TX_PULSE_DECL="$(printf '%s\n' "$PULSE_DECL" | json_tx_hash)"
[ -n "$CLASS_PULSE" ] || CLASS_PULSE="$(class_hash_from_pkg pulse_auction PulseAuction)"
[ -n "$CLASS_PULSE" ] || { echo "No class hash for PulseAuction" >&2; exit 1; }
record_address pulse_auction_class_hash "$CLASS_PULSE"
[ -n "$TX_PULSE_DECL" ] && record_tx pulse_auction_declare "$TX_PULSE_DECL"

PULSE_DEP="$(sncast_deploy_json "$CLASS_PULSE" "$OPEN_DELAY" "$K_LOW" "$K_HIGH" "$GP_LOW" "$GP_HIGH" "$FL_LOW" "$FL_HIGH" "$PTS_FRI" "$PAYTOKEN" "$TREASURY" "$ADAPTER_ADDR")"
ADDR_PULSE="$(printf '%s\n' "$PULSE_DEP" | json_contract_address)"
TX_PULSE_DEP="$(printf '%s\n' "$PULSE_DEP" | json_tx_hash)"
[ -n "$ADDR_PULSE" ] || { echo "No deploy address for PulseAuction" >&2; exit 1; }
record_address pulse_auction "$ADDR_PULSE"
[ -n "$TX_PULSE_DEP" ] && record_tx pulse_auction_deploy "$TX_PULSE_DEP"

echo "PULSE_AUCTION=$ADDR_PULSE"
