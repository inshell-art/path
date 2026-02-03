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

if [ "${SKIP_DEPLOY:-0}" != "1" ]; then
  "$ROOT_DIR/scripts/devnet/01_deploy_utils.sh"
  "$ROOT_DIR/scripts/devnet/02_deploy_renderer.sh"
  "$ROOT_DIR/scripts/devnet/03_deploy_path_core.sh"
  "$ROOT_DIR/scripts/devnet/04_deploy_pulse.sh"
fi

PATH_NFT="${PATH_NFT:-$(addr_from_file path_nft)}"
PATH_MINTER="${PATH_MINTER:-$(addr_from_file path_minter)}"
PATH_ADAPTER="${PATH_ADAPTER:-$(addr_from_file path_minter_adapter)}"
PATH_LOOK="${PATH_LOOK:-$(addr_from_file path_look)}"
PULSE_AUCTION="${PULSE_AUCTION:-$(addr_from_file pulse_auction)}"

[ -n "$PATH_NFT" ] || { echo "Missing path_nft address" >&2; exit 1; }
[ -n "$PATH_MINTER" ] || { echo "Missing path_minter address" >&2; exit 1; }
[ -n "$PATH_ADAPTER" ] || { echo "Missing path_minter_adapter address" >&2; exit 1; }
[ -n "$PATH_LOOK" ] || { echo "Missing path_look address" >&2; exit 1; }
[ -n "$PULSE_AUCTION" ] || { echo "Missing pulse_auction address" >&2; exit 1; }

ADMIN_ADDR="${ADMIN_ADDRESS:-$(account_address)}"
[ -n "$ADMIN_ADDR" ] || { echo "Missing admin address" >&2; exit 1; }

MINTER_ROLE_ID="${MINTER_ROLE_ID:-$(role_id MINTER_ROLE)}"
SALES_ROLE_ID="${SALES_ROLE_ID:-$(role_id SALES_ROLE)}"

echo "==> Configure roles + adapter"
TX1="$(sncast_invoke_json "$PATH_NFT" grant_role "$MINTER_ROLE_ID" "$PATH_MINTER" | json_tx_hash)"
[ -n "$TX1" ] && record_tx config_grant_minter "$TX1"
TX2="$(sncast_invoke_json "$PATH_MINTER" grant_role "$SALES_ROLE_ID" "$PATH_ADAPTER" | json_tx_hash)"
[ -n "$TX2" ] && record_tx config_grant_sales "$TX2"
TX3="$(sncast_invoke_json "$PATH_ADAPTER" set_minter "$PATH_MINTER" | json_tx_hash)"
[ -n "$TX3" ] && record_tx config_set_minter "$TX3"
TX4="$(sncast_invoke_json "$PATH_ADAPTER" set_auction "$PULSE_AUCTION" | json_tx_hash)"
[ -n "$TX4" ] && record_tx config_set_auction "$TX4"

TOKEN_ID_DEC="${TOKEN_ID_DEC:-1}"
read -r TOKEN_LOW TOKEN_HIGH <<<"$(u256_split "$TOKEN_ID_DEC")"

# grant MINTER_ROLE to admin for a deterministic token id
sncast_invoke_json "$PATH_NFT" grant_role "$MINTER_ROLE_ID" "$ADMIN_ADDR" >/dev/null
sncast_invoke_json "$PATH_NFT" safe_mint "$ADMIN_ADDR" "$TOKEN_LOW" "$TOKEN_HIGH" 0 >/dev/null

META_OUT="$META_DIR/token_${TOKEN_ID_DEC}.json"
SVG_OUT="$SVG_DIR/token_${TOKEN_ID_DEC}.svg"
call_bytearray_to_file "$META_OUT" "$PATH_NFT" token_uri "$TOKEN_LOW" "$TOKEN_HIGH"
call_bytearray_to_file "$SVG_OUT" "$PATH_LOOK" generate_svg "$PATH_NFT" "$TOKEN_LOW" "$TOKEN_HIGH"

echo "Saved metadata -> $META_OUT"
echo "Saved svg      -> $SVG_OUT"

RUN_BID="${RUN_BID:-0}"
if [ "$RUN_BID" = "1" ]; then
  PARAMS_EXAMPLE="$ROOT_DIR/scripts/params.devnet.example"
  PARAMS_LOCAL="$ROOT_DIR/scripts/params.devnet.local"
  [ -f "$PARAMS_EXAMPLE" ] && source "$PARAMS_EXAMPLE"
  [ -f "$PARAMS_LOCAL" ] && source "$PARAMS_LOCAL"

  PAYTOKEN="${PAYTOKEN:-}"
  [ -n "$PAYTOKEN" ] || { echo "Missing PAYTOKEN" >&2; exit 1; }

  BIDDER_ACCOUNT="${BIDDER_ACCOUNT:-dev_bidder1}"
  BIDDER_ADDR="$(jq -r --arg ns "$ACCOUNTS_NAMESPACE" --arg name "$BIDDER_ACCOUNT" '.[$ns][$name].address // empty' "$ACCOUNTS_FILE")"
  [ -n "$BIDDER_ADDR" ] || { echo "Missing bidder address" >&2; exit 1; }

  echo "==> Bid via Pulse (account=$BIDDER_ACCOUNT)"
  ASK_JSON="$(sncast --account "$BIDDER_ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json call --url "$RPC" \
    --contract-address "$PULSE_AUCTION" --function get_current_price)"
  ASK_LOW="$(jq -r '.response_raw[0] // .response[0] // empty' <<<"$ASK_JSON")"
  ASK_HIGH="$(jq -r '.response_raw[1] // .response[1] // empty' <<<"$ASK_JSON")"
  [ -n "$ASK_LOW" ] || { echo "Missing ask price" >&2; exit 1; }

  ALLOW_DEC="${ALLOW_DEC:-1000000000000000000000}"
  read -r ALLOW_LOW ALLOW_HIGH <<<"$(u256_split "$ALLOW_DEC")"

  sncast --account "$BIDDER_ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
    --contract-address "$PAYTOKEN" --function approve \
    --calldata "$PULSE_AUCTION" "$ALLOW_LOW" "$ALLOW_HIGH" >/dev/null

  sncast --account "$BIDDER_ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
    --contract-address "$PULSE_AUCTION" --function bid \
    --calldata "$ASK_LOW" "$ASK_HIGH" >/dev/null

  echo "Bid submitted with max_price=$ASK_LOW $ASK_HIGH"
fi
