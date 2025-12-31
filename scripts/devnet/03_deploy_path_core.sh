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

NFT_NAME="${NFT_NAME:-PATH}"
NFT_SYMBOL="${NFT_SYMBOL:-PATH}"
NFT_BASE_URI="${NFT_BASE_URI:-}"
FIRST_TOKEN_ID="${FIRST_TOKEN_ID:-1}"
RESERVED_CAP="${RESERVED_CAP:-0}"

PATH_LOOK_ADDR="${PATH_LOOK_ADDR:-$(addr_from_file path_look)}"
[ -n "$PATH_LOOK_ADDR" ] || { echo "Missing path_look address" >&2; exit 1; }

ADMIN_ADDRESS="${ADMIN_ADDRESS:-$(account_address)}"
[ -n "$ADMIN_ADDRESS" ] || { echo "Missing admin address" >&2; exit 1; }

read -r NAME_C <<<"$(encode_bytearray "$NFT_NAME")"
read -r SYMBOL_C <<<"$(encode_bytearray "$NFT_SYMBOL")"
read -r BASEURI_C <<<"$(encode_bytearray "$NFT_BASE_URI")"
read -r FIRST_LOW FIRST_HIGH <<<"$(u256_split "$FIRST_TOKEN_ID")"

# Declare classes
NFT_DECL="$(sncast_declare_json_pkg path_nft PathNFT)"
CLASS_NFT="$(printf '%s\n' "$NFT_DECL" | json_class_hash)"
TX_NFT_DECL="$(printf '%s\n' "$NFT_DECL" | json_tx_hash)"
[ -n "$CLASS_NFT" ] || CLASS_NFT="$(class_hash_from_pkg path_nft PathNFT)"
[ -n "$CLASS_NFT" ] || { echo "No class hash for PathNFT" >&2; exit 1; }
record_address path_nft_class_hash "$CLASS_NFT"
[ -n "$TX_NFT_DECL" ] && record_tx path_nft_declare "$TX_NFT_DECL"

MINTER_DECL="$(sncast_declare_json_pkg path_minter PathMinter)"
CLASS_MINTER="$(printf '%s\n' "$MINTER_DECL" | json_class_hash)"
TX_MINTER_DECL="$(printf '%s\n' "$MINTER_DECL" | json_tx_hash)"
[ -n "$CLASS_MINTER" ] || CLASS_MINTER="$(class_hash_from_pkg path_minter PathMinter)"
[ -n "$CLASS_MINTER" ] || { echo "No class hash for PathMinter" >&2; exit 1; }
record_address path_minter_class_hash "$CLASS_MINTER"
[ -n "$TX_MINTER_DECL" ] && record_tx path_minter_declare "$TX_MINTER_DECL"

ADAPTER_DECL="$(sncast_declare_json_pkg path_minter_adapter PathMinterAdapter)"
CLASS_ADAPTER="$(printf '%s\n' "$ADAPTER_DECL" | json_class_hash)"
TX_ADAPTER_DECL="$(printf '%s\n' "$ADAPTER_DECL" | json_tx_hash)"
[ -n "$CLASS_ADAPTER" ] || CLASS_ADAPTER="$(class_hash_from_pkg path_minter_adapter PathMinterAdapter)"
[ -n "$CLASS_ADAPTER" ] || { echo "No class hash for PathMinterAdapter" >&2; exit 1; }
record_address path_minter_adapter_class_hash "$CLASS_ADAPTER"
[ -n "$TX_ADAPTER_DECL" ] && record_tx path_minter_adapter_declare "$TX_ADAPTER_DECL"

# Deploy PathNFT
NFT_DEP="$(sncast_deploy_json "$CLASS_NFT" "$ADMIN_ADDRESS" $NAME_C $SYMBOL_C $BASEURI_C "$PATH_LOOK_ADDR")"
ADDR_NFT="$(printf '%s\n' "$NFT_DEP" | json_contract_address)"
TX_NFT_DEP="$(printf '%s\n' "$NFT_DEP" | json_tx_hash)"
[ -n "$ADDR_NFT" ] || { echo "No deploy address for PathNFT" >&2; exit 1; }
record_address path_nft "$ADDR_NFT"
[ -n "$TX_NFT_DEP" ] && record_tx path_nft_deploy "$TX_NFT_DEP"

# Deploy PathMinter
MINTER_DEP="$(sncast_deploy_json "$CLASS_MINTER" "$ADMIN_ADDRESS" "$ADDR_NFT" "$FIRST_LOW" "$FIRST_HIGH" "$RESERVED_CAP")"
ADDR_MINTER="$(printf '%s\n' "$MINTER_DEP" | json_contract_address)"
TX_MINTER_DEP="$(printf '%s\n' "$MINTER_DEP" | json_tx_hash)"
[ -n "$ADDR_MINTER" ] || { echo "No deploy address for PathMinter" >&2; exit 1; }
record_address path_minter "$ADDR_MINTER"
[ -n "$TX_MINTER_DEP" ] && record_tx path_minter_deploy "$TX_MINTER_DEP"

# Deploy PathMinterAdapter (auction=0x0 for now)
ADAPTER_DEP="$(sncast_deploy_json "$CLASS_ADAPTER" "$ADMIN_ADDRESS" 0x0 "$ADDR_MINTER")"
ADDR_ADAPTER="$(printf '%s\n' "$ADAPTER_DEP" | json_contract_address)"
TX_ADAPTER_DEP="$(printf '%s\n' "$ADAPTER_DEP" | json_tx_hash)"
[ -n "$ADDR_ADAPTER" ] || { echo "No deploy address for PathMinterAdapter" >&2; exit 1; }
record_address path_minter_adapter "$ADDR_ADAPTER"
[ -n "$TX_ADAPTER_DEP" ] && record_tx path_minter_adapter_deploy "$TX_ADAPTER_DEP"

echo "PATH_NFT=$ADDR_NFT"
echo "PATH_MINTER=$ADDR_MINTER"
echo "PATH_ADAPTER=$ADDR_ADAPTER"
