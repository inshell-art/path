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

echo "==> Group A: utilities (pprf + step-curve)"
"$ROOT_DIR/scripts/devnet/01_deploy_utils.sh"

PPRF_ADDR="$(addr_from_file glyph_pprf)"
STEP_ADDR="$(addr_from_file step_curve)"
[ -n "$PPRF_ADDR" ] || { echo "Missing glyph_pprf address" >&2; exit 1; }
[ -n "$STEP_ADDR" ] || { echo "Missing step_curve address" >&2; exit 1; }

echo "-> call glyph_pprf.metadata @ $PPRF_ADDR"
sncast_call_json "$PPRF_ADDR" metadata | decode_bytearray_json >"$META_DIR/pprf_metadata.json"

echo "-> call glyph_pprf.render(seed=1,2,3) @ $PPRF_ADDR"
sncast_call_json "$PPRF_ADDR" render 3 1 2 3 >"$META_DIR/pprf_render_123.json"

echo "-> call step_curve.metadata @ $STEP_ADDR"
sncast_call_json "$STEP_ADDR" metadata | decode_bytearray_json >"$META_DIR/step_curve_metadata.json"

echo "-> call step_curve.render (2 points) @ $STEP_ADDR"
call_bytearray_to_file "$SVG_DIR/stepcurve_case_1.d.txt" "$STEP_ADDR" render 5 5 0 0 100 100

echo "-> call step_curve.render (multi-point) @ $STEP_ADDR"
call_bytearray_to_file "$SVG_DIR/stepcurve_case_2.d.txt" "$STEP_ADDR" render 9 5 0 0 50 100 100 0 150 100

echo "Group A artifacts:"
ls -1 "$SVG_DIR"/stepcurve_case_*.d.txt "$META_DIR"/pprf_metadata.json "$META_DIR"/pprf_render_123.json "$META_DIR"/step_curve_metadata.json 2>/dev/null || true
