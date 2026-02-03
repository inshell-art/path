# Group E — Movement minting (THOUGHT / WILL / AWA)

These checks use `PathNFT.consume_unit` to advance movement progress.

## E0. Prep
```bash
source scripts/devnet/00_env.sh
PATH_NFT=$(jq -r '.path_nft' "$ADDR_FILE")
ACCOUNT_ADDR=$(jq -r --arg ns "$ACCOUNTS_NAMESPACE" --arg name "$ACCOUNT" \
  '.[$ns][$name].address' "$ACCOUNTS_FILE")
TOKEN_LOW=1
TOKEN_HIGH=0
```

Movement tags:
```bash
THOUGHT=0x54484f55474854
WILL=0x57494c4c
AWA=0x415741
```

---

## E1. Configure movement minter + quota (admin)
```bash
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
  --contract-address "$PATH_NFT" --function set_movement_config \
  --calldata "$THOUGHT" "$ACCOUNT_ADDR" 1

sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
  --contract-address "$PATH_NFT" --function set_movement_config \
  --calldata "$WILL" "$ACCOUNT_ADDR" 1

sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
  --contract-address "$PATH_NFT" --function set_movement_config \
  --calldata "$AWA" "$ACCOUNT_ADDR" 1
```

---

## E2. Consume in order
```bash
# THOUGHT
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
  --contract-address "$PATH_NFT" --function consume_unit \
  --calldata "$TOKEN_LOW" "$TOKEN_HIGH" "$THOUGHT" "$ACCOUNT_ADDR"

# WILL
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
  --contract-address "$PATH_NFT" --function consume_unit \
  --calldata "$TOKEN_LOW" "$TOKEN_HIGH" "$WILL" "$ACCOUNT_ADDR"

# AWA
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
  --contract-address "$PATH_NFT" --function consume_unit \
  --calldata "$TOKEN_LOW" "$TOKEN_HIGH" "$AWA" "$ACCOUNT_ADDR"
```

Verify stage after each step:
```bash
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" call --url "$RPC" \
  --contract-address "$PATH_NFT" --function get_stage \
  --calldata "$TOKEN_LOW" "$TOKEN_HIGH"
```
Expected stages (with quota=1): 1 (WILL), 2 (AWA), 3 (COMPLETE).

Re-check metadata after full progression:
```bash
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json call --url "$RPC" \
  --contract-address "$PATH_NFT" --function token_uri \
  --calldata "$TOKEN_LOW" "$TOKEN_HIGH" \
  | python3 scripts/devnet/_decode_bytearray.py \
  > "$META_DIR/path_nft_token_${TOKEN_LOW}_final.json"
```
