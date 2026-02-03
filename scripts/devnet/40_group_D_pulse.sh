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

RUN_BID="${RUN_BID:-1}"
ALLOW_DEC="${ALLOW_DEC:-1000000000000000000000}"
BIDDER_ACCOUNT="${BIDDER_ACCOUNT:-dev_bidder1}"

# Load params for PAYTOKEN/TREASURY if present
PARAMS_EXAMPLE="$ROOT_DIR/scripts/params.devnet.example"
PARAMS_LOCAL="$ROOT_DIR/scripts/params.devnet.local"
[ -f "$PARAMS_EXAMPLE" ] && source "$PARAMS_EXAMPLE"
[ -f "$PARAMS_LOCAL" ] && source "$PARAMS_LOCAL"

PAYTOKEN="${PAYTOKEN:-}"
TREASURY="${TREASURY:-}"
[ -n "$PAYTOKEN" ] || { echo "Missing PAYTOKEN (set in scripts/params.devnet.local or env)" >&2; exit 1; }
[ -n "$TREASURY" ] || { echo "Missing TREASURY (set in scripts/params.devnet.local or env)" >&2; exit 1; }

echo "==> Group D: Pulse auction"
"$ROOT_DIR/scripts/devnet/04_deploy_pulse.sh"

PULSE_AUCTION="$(addr_from_file pulse_auction)"
PATH_ADAPTER="$(addr_from_file path_minter_adapter)"
[ -n "$PULSE_AUCTION" ] || { echo "Missing pulse_auction" >&2; exit 1; }
[ -n "$PATH_ADAPTER" ] || { echo "Missing path_minter_adapter" >&2; exit 1; }

echo "-> invoke Adapter.set_auction($PULSE_AUCTION)"
TX1="$(sncast_invoke_json "$PATH_ADAPTER" set_auction "$PULSE_AUCTION" | json_tx_hash)"
[ -n "$TX1" ] && record_tx adapter_set_auction "$TX1"

# Snapshot state
sncast_call_json "$PULSE_AUCTION" get_current_price >"$META_DIR/pulse_current_price_before.json"
sncast_call_json "$PULSE_AUCTION" get_state >"$META_DIR/pulse_state_before.json"
sncast_call_json "$PULSE_AUCTION" get_config >"$META_DIR/pulse_config.json"

if [ "$RUN_BID" = "1" ]; then
  BIDDER_ADDR="$(jq -r --arg ns "$ACCOUNTS_NAMESPACE" --arg name "$BIDDER_ACCOUNT" '.[$ns][$name].address // empty' "$ACCOUNTS_FILE")"
  [ -n "$BIDDER_ADDR" ] || { echo "Missing bidder address for $BIDDER_ACCOUNT" >&2; exit 1; }

  ASK_JSON="$(sncast --account "$BIDDER_ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json call --url "$RPC" \
    --contract-address "$PULSE_AUCTION" --function get_current_price)"
  ASK_LOW="$(jq -r '.response_raw[0] // .response[0] // empty' <<<"$ASK_JSON")"
  ASK_HIGH="$(jq -r '.response_raw[1] // .response[1] // empty' <<<"$ASK_JSON")"
  [ -n "$ASK_LOW" ] || { echo "Missing ask price" >&2; exit 1; }

  read -r ALLOW_LOW ALLOW_HIGH <<<"$(u256_split "$ALLOW_DEC")"

  echo "-> invoke ERC20.approve(auction, allowance)"
  sncast --account "$BIDDER_ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
    --contract-address "$PAYTOKEN" --function approve \
    --calldata "$PULSE_AUCTION" "$ALLOW_LOW" "$ALLOW_HIGH" >/dev/null

  echo "-> invoke PulseAuction.bid(max_price=ask)"
  sncast --account "$BIDDER_ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
    --contract-address "$PULSE_AUCTION" --function bid \
    --calldata "$ASK_LOW" "$ASK_HIGH" >/dev/null
fi

# Snapshot after
sncast_call_json "$PULSE_AUCTION" get_current_price >"$META_DIR/pulse_current_price_after.json"
sncast_call_json "$PULSE_AUCTION" get_state >"$META_DIR/pulse_state_after.json"

echo "Group D artifacts:"
ls -1 "$META_DIR"/pulse_*_*.json 2>/dev/null || true
