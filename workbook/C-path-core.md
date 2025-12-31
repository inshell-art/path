# Group C — PATH core (path_nft + minter + adapter)

## C0. Deploy
```bash
source scripts/devnet/00_env.sh
scripts/devnet/03_deploy_path_core.sh
```

Load addresses:
```bash
PATH_NFT=$(jq -r '.path_nft' "$ADDR_FILE")
PATH_MINTER=$(jq -r '.path_minter' "$ADDR_FILE")
PATH_ADAPTER=$(jq -r '.path_minter_adapter' "$ADDR_FILE")
```

---

## C1. Grant MINTER_ROLE to PathMinter
```bash
MINTER_ROLE_ID=$(python3 scripts/devnet/_role_id.py MINTER_ROLE)

sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
  --contract-address "$PATH_NFT" --function grant_role \
  --calldata "$MINTER_ROLE_ID" "$PATH_MINTER"
```
Expected: no revert.

---

## C2. Direct mint via PathNFT (deterministic token id)
This is the simplest way to get a known token id for renderer checks.

```bash
ACCOUNT_ADDR=$(jq -r --arg ns "$ACCOUNTS_NAMESPACE" --arg name "$ACCOUNT" \
  '.[$ns][$name].address' "$ACCOUNTS_FILE")
TOKEN_LOW=1
TOKEN_HIGH=0

# grant MINTER_ROLE to your account
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
  --contract-address "$PATH_NFT" --function grant_role \
  --calldata "$MINTER_ROLE_ID" "$ACCOUNT_ADDR"

# safe_mint(to, token_id, data_len)
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
  --contract-address "$PATH_NFT" --function safe_mint \
  --calldata "$ACCOUNT_ADDR" "$TOKEN_LOW" "$TOKEN_HIGH" 0
```

Verify:
```bash
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" call --url "$RPC" \
  --contract-address "$PATH_NFT" --function owner_of \
  --calldata "$TOKEN_LOW" "$TOKEN_HIGH"

sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json call --url "$RPC" \
  --contract-address "$PATH_NFT" --function token_uri \
  --calldata "$TOKEN_LOW" "$TOKEN_HIGH" \
  | python3 scripts/devnet/_decode_bytearray.py \
  > "$META_DIR/path_nft_token_${TOKEN_LOW}.json"
```
Expected: token owner is your account; metadata JSON contains stage `THOUGHT`.

---

## C3. Optional: mint via PathMinter
If you want the normal mint path:

```bash
SALES_ROLE_ID=$(python3 scripts/devnet/_role_id.py SALES_ROLE)

# allow your account to call mint_public
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
  --contract-address "$PATH_MINTER" --function grant_role \
  --calldata "$SALES_ROLE_ID" "$ACCOUNT_ADDR"

sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
  --contract-address "$PATH_MINTER" --function mint_public \
  --calldata "$ACCOUNT_ADDR" 0
```
Note: `mint_public` returns the token id, but `invoke` does not return it; use direct mint if you need a known id.
