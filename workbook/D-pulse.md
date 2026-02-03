# Group D — Pulse auction + issuance

## D0. Deploy Pulse
```bash
source scripts/devnet/00_env.sh
scripts/devnet/04_deploy_pulse.sh
```

Load addresses:
```bash
PULSE_AUCTION=$(jq -r '.pulse_auction' "$ADDR_FILE")
PATH_ADAPTER=$(jq -r '.path_minter_adapter' "$ADDR_FILE")
```

---

## D1. Wire adapter to auction
```bash
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
  --contract-address "$PATH_ADAPTER" --function set_auction \
  --calldata "$PULSE_AUCTION"
```

---

## D2. Read auction state
```bash
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" call --url "$RPC" \
  --contract-address "$PULSE_AUCTION" --function get_current_price

sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" call --url "$RPC" \
  --contract-address "$PULSE_AUCTION" --function get_state

sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" call --url "$RPC" \
  --contract-address "$PULSE_AUCTION" --function get_config
```
Expected: `get_current_price` returns a u256 (low/high). `get_state` reports epoch, anchor, floor, curve_active.

---

## D3. Place a bid (manual)
This uses a bidder account (default `dev_bidder1`).

```bash
BIDDER_ACCOUNT=dev_bidder1
BIDDER_ADDR=$(jq -r --arg ns "$ACCOUNTS_NAMESPACE" --arg name "$BIDDER_ACCOUNT" \
  '.[$ns][$name].address' "$ACCOUNTS_FILE")

# read current ask
ASK_JSON=$(sncast --account "$BIDDER_ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json call --url "$RPC" \
  --contract-address "$PULSE_AUCTION" --function get_current_price)
ASK_LOW=$(jq -r '.response_raw[0] // .response[0] // empty' <<<"$ASK_JSON")
ASK_HIGH=$(jq -r '.response_raw[1] // .response[1] // empty' <<<"$ASK_JSON")

# approve payment token (see scripts/params.devnet.* for PAYTOKEN)
PAYTOKEN=$(grep -E '^PAYTOKEN=' scripts/params.devnet.example | cut -d= -f2-)
ALLOW_DEC=1000000000000000000000
read -r ALLOW_LOW ALLOW_HIGH <<<"$(python3 - <<PY
n=int("$ALLOW_DEC",0)
print(n & ((1<<128)-1), n>>128)
PY
)"

sncast --account "$BIDDER_ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
  --contract-address "$PAYTOKEN" --function approve \
  --calldata "$PULSE_AUCTION" "$ALLOW_LOW" "$ALLOW_HIGH"

# bid with max_price = ask
sncast --account "$BIDDER_ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
  --contract-address "$PULSE_AUCTION" --function bid \
  --calldata "$ASK_LOW" "$ASK_HIGH"
```
Expected: bid succeeds; `get_state` should show epoch changes / curve activation.

Optional: use `scripts/devnet/05_smoke_e2e.sh` with `RUN_BID=1` for a genesis bid.
