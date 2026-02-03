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
[ -n "$PATH_NFT" ] || { echo "Missing path_nft" >&2; exit 1; }
ACCOUNT_ADDR="$(account_address)"
[ -n "$ACCOUNT_ADDR" ] || { echo "Missing admin address" >&2; exit 1; }

THOUGHT=0x54484f55474854
WILL=0x57494c4c
AWA=0x415741
QUOTA="${MOVEMENT_QUOTA:-1}"

META_PREFIX="$META_DIR/path_nft_token_${TOKEN_ID_DEC}"

# before snapshot
call_bytearray_to_file "${META_PREFIX}_before.json" "$PATH_NFT" token_uri "$TOKEN_LOW" "$TOKEN_HIGH"

# configure movement minters + quota
for MOV in "$THOUGHT" "$WILL" "$AWA"; do
  echo "-> invoke PathNFT.set_movement_config(movement=$MOV, minter=$ACCOUNT_ADDR, quota=$QUOTA)"
  TX_CFG="$(sncast_invoke_json "$PATH_NFT" set_movement_config "$MOV" "$ACCOUNT_ADDR" "$QUOTA" | json_tx_hash)"
  [ -n "$TX_CFG" ] && record_tx "set_movement_config_${MOV}" "$TX_CFG"
done

# consume THOUGHT
echo "-> invoke PathNFT.consume_unit(THOUGHT)"
TX_THOUGHT="$(sncast_invoke_json "$PATH_NFT" consume_unit "$TOKEN_LOW" "$TOKEN_HIGH" "$THOUGHT" "$ACCOUNT_ADDR" | json_tx_hash)"
[ -n "$TX_THOUGHT" ] && record_tx "consume_thought_${TOKEN_ID_DEC}" "$TX_THOUGHT"
sncast_call_json "$PATH_NFT" get_stage "$TOKEN_LOW" "$TOKEN_HIGH" >"${META_PREFIX}_stage_after_thought.json"
call_bytearray_to_file "${META_PREFIX}_after_thought.json" "$PATH_NFT" token_uri "$TOKEN_LOW" "$TOKEN_HIGH"

# consume WILL
echo "-> invoke PathNFT.consume_unit(WILL)"
TX_WILL="$(sncast_invoke_json "$PATH_NFT" consume_unit "$TOKEN_LOW" "$TOKEN_HIGH" "$WILL" "$ACCOUNT_ADDR" | json_tx_hash)"
[ -n "$TX_WILL" ] && record_tx "consume_will_${TOKEN_ID_DEC}" "$TX_WILL"
sncast_call_json "$PATH_NFT" get_stage "$TOKEN_LOW" "$TOKEN_HIGH" >"${META_PREFIX}_stage_after_will.json"
call_bytearray_to_file "${META_PREFIX}_after_will.json" "$PATH_NFT" token_uri "$TOKEN_LOW" "$TOKEN_HIGH"

# consume AWA
echo "-> invoke PathNFT.consume_unit(AWA)"
TX_AWA="$(sncast_invoke_json "$PATH_NFT" consume_unit "$TOKEN_LOW" "$TOKEN_HIGH" "$AWA" "$ACCOUNT_ADDR" | json_tx_hash)"
[ -n "$TX_AWA" ] && record_tx "consume_awa_${TOKEN_ID_DEC}" "$TX_AWA"
sncast_call_json "$PATH_NFT" get_stage "$TOKEN_LOW" "$TOKEN_HIGH" >"${META_PREFIX}_stage_after_awa.json"
call_bytearray_to_file "${META_PREFIX}_after_awa.json" "$PATH_NFT" token_uri "$TOKEN_LOW" "$TOKEN_HIGH"

# final snapshot
call_bytearray_to_file "${META_PREFIX}_final.json" "$PATH_NFT" token_uri "$TOKEN_LOW" "$TOKEN_HIGH"

echo "Group E artifacts:"
ls -1 "${META_PREFIX}"_after_*.json "${META_PREFIX}"_stage_after_*.json "${META_PREFIX}"_final.json 2>/dev/null || true
