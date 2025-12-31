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
need python3

PATH_LOOK_DIR="$ROOT_DIR/contracts/path_look/contracts"

meta="$(cd "$PATH_LOOK_DIR" && scarb metadata --format-version 1)"
PPRF_ROOT="$(jq -r '.packages[] | select(.name=="glyph_pprf") | .root' <<<"$meta" | head -n1)"
STEP_CURVE_ROOT="$(jq -r '.packages[] | select(.name=="step_curve") | .root' <<<"$meta" | head -n1)"

[ -n "$PPRF_ROOT" ] || { echo "Missing glyph_pprf root" >&2; exit 1; }
[ -n "$STEP_CURVE_ROOT" ] || { echo "Missing step_curve root" >&2; exit 1; }

echo "==> Declare + deploy glyph_pprf"
PPRF_DECL="$(sncast_declare_json_dir "$PPRF_ROOT" Pprf)"
CLASS_PPRF="$(printf '%s\n' "$PPRF_DECL" | json_class_hash)"
TX_PPRF_DECL="$(printf '%s\n' "$PPRF_DECL" | json_tx_hash)"
[ -n "$CLASS_PPRF" ] || CLASS_PPRF="$(class_hash_from_dir "$PPRF_ROOT" Pprf)"
[ -n "$CLASS_PPRF" ] || { echo "No class hash for glyph_pprf" >&2; exit 1; }
record_address glyph_pprf_class_hash "$CLASS_PPRF"
[ -n "$TX_PPRF_DECL" ] && record_tx glyph_pprf_declare "$TX_PPRF_DECL"

PPRF_DEP="$(sncast_deploy_json "$CLASS_PPRF")"
ADDR_PPRF="$(printf '%s\n' "$PPRF_DEP" | json_contract_address)"
TX_PPRF_DEP="$(printf '%s\n' "$PPRF_DEP" | json_tx_hash)"
[ -n "$ADDR_PPRF" ] || { echo "No deploy address for glyph_pprf" >&2; exit 1; }
record_address glyph_pprf "$ADDR_PPRF"
[ -n "$TX_PPRF_DEP" ] && record_tx glyph_pprf_deploy "$TX_PPRF_DEP"

echo "==> Declare + deploy step_curve"
STEP_DECL="$(sncast_declare_json_dir "$STEP_CURVE_ROOT" StepCurve)"
CLASS_STEP="$(printf '%s\n' "$STEP_DECL" | json_class_hash)"
TX_STEP_DECL="$(printf '%s\n' "$STEP_DECL" | json_tx_hash)"
[ -n "$CLASS_STEP" ] || CLASS_STEP="$(class_hash_from_dir "$STEP_CURVE_ROOT" StepCurve)"
[ -n "$CLASS_STEP" ] || { echo "No class hash for step_curve" >&2; exit 1; }
record_address step_curve_class_hash "$CLASS_STEP"
[ -n "$TX_STEP_DECL" ] && record_tx step_curve_declare "$TX_STEP_DECL"

STEP_DEP="$(sncast_deploy_json "$CLASS_STEP")"
ADDR_STEP="$(printf '%s\n' "$STEP_DEP" | json_contract_address)"
TX_STEP_DEP="$(printf '%s\n' "$STEP_DEP" | json_tx_hash)"
[ -n "$ADDR_STEP" ] || { echo "No deploy address for step_curve" >&2; exit 1; }
record_address step_curve "$ADDR_STEP"
[ -n "$TX_STEP_DEP" ] && record_tx step_curve_deploy "$TX_STEP_DEP"

echo "PPRF=$ADDR_PPRF"
echo "STEP_CURVE=$ADDR_STEP"
