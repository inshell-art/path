# Group C — Reserved mint (mint_sparker) by hand

This section covers the reserved mint flow:
Sparker (caller with RESERVED_ROLE) → PathMinter.mint_sparker → PathNFT.safe_mint

## Prereq
- PathNFT + PathMinter deployed (Group C)
- PathMinter has MINTER_ROLE on PathNFT
- You have a caller address that will be granted RESERVED_ROLE on PathMinter

## 1) Load env + addresses
```bash
source scripts/devnet/00_env.sh

PATH_NFT=$(jq -r '.path_nft' "$ADDR_FILE")
PATH_MINTER=$(jq -r '.path_minter' "$ADDR_FILE")
```

## 2) Grant RESERVED_ROLE to your account
```bash
ACCOUNT_ADDR=$(jq -r --arg ns "$ACCOUNTS_NAMESPACE" --arg name "$ACCOUNT" \
  '.[$ns][$name].address' "$ACCOUNTS_FILE")

RESERVED_ROLE_ID=$(python3 scripts/devnet/_role_id.py RESERVED_ROLE)

sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
  --contract-address "$PATH_MINTER" --function grant_role \
  --calldata "$RESERVED_ROLE_ID" "$ACCOUNT_ADDR"
```

## 3) Mint a reserved token
```bash
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" invoke --url "$RPC" \
  --contract-address "$PATH_MINTER" --function mint_sparker \
  --calldata "$ACCOUNT_ADDR" 0
```
Note: `invoke` doesn’t print return values, but the minted token id is deterministic:
`2^256 - 2` for the first reserved mint, then `2^256 - 3`, etc.

## 4) Verify by owner_of (optional)
If you want to query ownership, you need the token id split into low/high u128.
The first reserved id is:

```
token_id = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE
```

Split:
```
low  = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE
high = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE
```

Owner check:
```bash
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" call --url "$RPC" \
  --contract-address "$PATH_NFT" --function owner_of \
  --calldata 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE
```
