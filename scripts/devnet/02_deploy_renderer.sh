#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/devnet/00_env.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/devnet/_helpers.sh"

need scarb
need sncast
need jq

PPRF_ADDR="${PPRF_ADDR:-$(addr_from_file glyph_pprf)}"
STEP_ADDR="${STEP_ADDR:-$(addr_from_file step_curve)}"
[ -n "$PPRF_ADDR" ] || { echo "Missing glyph_pprf address" >&2; exit 1; }
[ -n "$STEP_ADDR" ] || { echo "Missing step_curve address" >&2; exit 1; }

PATH_LOOK_DIR="$PATH_REPO/contracts/path_look/contracts"

echo "==> Declare + deploy path_look"
LOOK_DECL="$(sncast_declare_json_dir "$PATH_LOOK_DIR" PathLook)"
CLASS_LOOK="$(printf '%s\n' "$LOOK_DECL" | json_class_hash)"
TX_LOOK_DECL="$(printf '%s\n' "$LOOK_DECL" | json_tx_hash)"
[ -n "$CLASS_LOOK" ] || CLASS_LOOK="$(class_hash_from_dir "$PATH_LOOK_DIR" PathLook)"
[ -n "$CLASS_LOOK" ] || { echo "No class hash for path_look" >&2; exit 1; }
record_address path_look_class_hash "$CLASS_LOOK"
[ -n "$TX_LOOK_DECL" ] && record_tx path_look_declare "$TX_LOOK_DECL"

LOOK_DEP="$(sncast_deploy_json "$CLASS_LOOK" "$PPRF_ADDR" "$STEP_ADDR")"
ADDR_LOOK="$(printf '%s\n' "$LOOK_DEP" | json_contract_address)"
TX_LOOK_DEP="$(printf '%s\n' "$LOOK_DEP" | json_tx_hash)"
[ -n "$ADDR_LOOK" ] || { echo "No deploy address for path_look" >&2; exit 1; }
record_address path_look "$ADDR_LOOK"
[ -n "$TX_LOOK_DEP" ] && record_tx path_look_deploy "$TX_LOOK_DEP"

echo "PATH_LOOK=$ADDR_LOOK"
