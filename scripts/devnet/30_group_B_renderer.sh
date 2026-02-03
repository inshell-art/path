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

TOKEN_ID_DEC="${TOKEN_ID_DEC:-}"
TOKEN_ID_FILE="$ARTIFACTS_DIR/token_id.txt"
if [ -z "$TOKEN_ID_DEC" ] && [ -f "$TOKEN_ID_FILE" ]; then
  TOKEN_ID_DEC="$(cat "$TOKEN_ID_FILE")"
fi
TOKEN_ID_DEC="${TOKEN_ID_DEC:-1}"
read -r TOKEN_LOW TOKEN_HIGH <<<"$(u256_split "$TOKEN_ID_DEC")"

PATH_NFT="$(addr_from_file path_nft)"
[ -n "$PATH_NFT" ] || { echo "Missing path_nft address" >&2; exit 1; }

PATH_LOOK="$(addr_from_file path_look)"
if [ -z "$PATH_LOOK" ]; then
  echo "PathLook missing; deploying renderer"
  "$ROOT_DIR/scripts/devnet/02_deploy_renderer.sh"
  PATH_LOOK="$(addr_from_file path_look)"
fi
[ -n "$PATH_LOOK" ] || { echo "Missing path_look address" >&2; exit 1; }

echo "==> Group B: renderer (PathLook)"

echo "-> call PathLook.generate_svg(token_id=$TOKEN_ID_DEC)"
call_bytearray_to_file "$SVG_DIR/pathlook_token_${TOKEN_ID_DEC}.svg" "$PATH_LOOK" generate_svg "$PATH_NFT" "$TOKEN_LOW" "$TOKEN_HIGH"

echo "-> call PathLook.generate_svg_data_uri(token_id=$TOKEN_ID_DEC)"
call_bytearray_to_file "$SVG_DIR/pathlook_token_${TOKEN_ID_DEC}.data_uri.txt" "$PATH_LOOK" generate_svg_data_uri "$PATH_NFT" "$TOKEN_LOW" "$TOKEN_HIGH"

echo "-> call PathLook.get_token_metadata(token_id=$TOKEN_ID_DEC)"
call_bytearray_to_file "$META_DIR/pathlook_token_${TOKEN_ID_DEC}.json" "$PATH_LOOK" get_token_metadata "$PATH_NFT" "$TOKEN_LOW" "$TOKEN_HIGH"

echo "Group B artifacts:"
ls -1 "$SVG_DIR/pathlook_token_${TOKEN_ID_DEC}.svg" "$SVG_DIR/pathlook_token_${TOKEN_ID_DEC}.data_uri.txt" "$META_DIR/pathlook_token_${TOKEN_ID_DEC}.json" 2>/dev/null || true
