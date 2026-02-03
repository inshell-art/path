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
need curl

TOKEN_ID_DEC="${TOKEN_ID_DEC:-1}"
read -r TOKEN_LOW TOKEN_HIGH <<<"$(u256_split "$TOKEN_ID_DEC")"
TOKEN_ID_FILE="$ARTIFACTS_DIR/token_id.txt"

is_deployed() {
  local addr="$1"
  [ -n "$addr" ] || return 1
  local payload resp
  payload="$(jq -nc --arg addr "$addr" '{jsonrpc:"2.0",method:"starknet_getClassHashAt",params:{block_id:"latest",contract_address:$addr},id:1}')"
  resp="$(curl -s -H 'Content-Type: application/json' -d "$payload" "$RPC" || true)"
  jq -e '.result? // empty' <<<"$resp" >/dev/null 2>&1
}

# Ensure PathLook exists (PathNFT constructor requires it)
PATH_LOOK_ADDR="$(addr_from_file path_look)"
if ! is_deployed "$PATH_LOOK_ADDR"; then
  echo "PathLook missing or not deployed; deploying renderer first"
  "$ROOT_DIR/scripts/devnet/02_deploy_renderer.sh"
fi

PATH_LOOK_ADDR="$(addr_from_file path_look)"
[ -n "$PATH_LOOK_ADDR" ] || { echo "Missing path_look address" >&2; exit 1; }

echo "==> Group C: PATH core (PathNFT + PathMinter + Adapter)"
"$ROOT_DIR/scripts/devnet/03_deploy_path_core.sh"

PATH_NFT="$(addr_from_file path_nft)"
PATH_MINTER="$(addr_from_file path_minter)"
PATH_ADAPTER="$(addr_from_file path_minter_adapter)"
[ -n "$PATH_NFT" ] || { echo "Missing path_nft" >&2; exit 1; }
[ -n "$PATH_MINTER" ] || { echo "Missing path_minter" >&2; exit 1; }
[ -n "$PATH_ADAPTER" ] || { echo "Missing path_minter_adapter" >&2; exit 1; }

MINTER_ROLE_ID="$(role_id MINTER_ROLE)"
ACCOUNT_ADDR="$(account_address)"

echo "-> invoke PathNFT.grant_role(MINTER_ROLE, PathMinter)"
TX1="$(sncast_invoke_json "$PATH_NFT" grant_role "$MINTER_ROLE_ID" "$PATH_MINTER" | json_tx_hash)"
[ -n "$TX1" ] && record_tx path_nft_grant_minter "$TX1"

# Grant MINTER_ROLE to admin for deterministic mint
if [ -n "$ACCOUNT_ADDR" ]; then
  echo "-> invoke PathNFT.grant_role(MINTER_ROLE, admin)"
  TX2="$(sncast_invoke_json "$PATH_NFT" grant_role "$MINTER_ROLE_ID" "$ACCOUNT_ADDR" | json_tx_hash)"
  [ -n "$TX2" ] && record_tx path_nft_grant_admin_minter "$TX2"
else
  echo "Missing admin address; cannot mint" >&2
  exit 1
fi

# safe_mint with known token id
printf "%s" "$TOKEN_ID_DEC" >"$TOKEN_ID_FILE"

echo "-> invoke PathNFT.safe_mint(to=$ACCOUNT_ADDR, token_id=$TOKEN_ID_DEC)"
TX3="$(sncast_invoke_json "$PATH_NFT" safe_mint "$ACCOUNT_ADDR" "$TOKEN_LOW" "$TOKEN_HIGH" 0 | json_tx_hash)"
[ -n "$TX3" ] && record_tx path_nft_safe_mint "$TX3"

# Verify owner and metadata
OWNER_JSON="$(sncast_call_json "$PATH_NFT" owner_of "$TOKEN_LOW" "$TOKEN_HIGH")"
OWNER_ADDR="$(jq -r '.response_raw[0] // .response[0] // empty' <<<"$OWNER_JSON" 2>/dev/null || true)"

echo "owner_of($TOKEN_ID_DEC) = ${OWNER_ADDR:-<empty>}"

META_OUT="$META_DIR/path_nft_token_${TOKEN_ID_DEC}.json"
call_bytearray_to_file "$META_OUT" "$PATH_NFT" token_uri "$TOKEN_LOW" "$TOKEN_HIGH"

echo "Group C artifacts:"
ls -1 "$META_OUT" "$TOKEN_ID_FILE" 2>/dev/null || true
