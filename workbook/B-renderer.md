# Group B — Renderer (path-look)

## B0. Prep
```bash
source scripts/devnet/00_env.sh
```

Deploy PathLook (requires pprf + step_curve from Group A):
```bash
scripts/devnet/02_deploy_renderer.sh
```

Load addresses:
```bash
PATH_LOOK=$(jq -r '.path_look' "$ADDR_FILE")
```

PathLook reads stage from a PathNFT contract. For the calls below, use a real PathNFT + minted token (from Group C).

---

## B1. generate_svg()
```bash
PATH_NFT=$(jq -r '.path_nft' "$ADDR_FILE")
TOKEN_LOW=1
TOKEN_HIGH=0

sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json call --url "$RPC" \
  --contract-address "$PATH_LOOK" --function generate_svg \
  --calldata "$PATH_NFT" "$TOKEN_LOW" "$TOKEN_HIGH" \
  | python3 scripts/devnet/_decode_bytearray.py \
  > "$SVG_DIR/pathlook_token_${TOKEN_LOW}.svg"
```
Expected: `pathlook_token_1.svg` begins with `<svg` and renders correctly when opened.

---

## B2. generate_svg_data_uri()
```bash
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json call --url "$RPC" \
  --contract-address "$PATH_LOOK" --function generate_svg_data_uri \
  --calldata "$PATH_NFT" "$TOKEN_LOW" "$TOKEN_HIGH" \
  | python3 scripts/devnet/_decode_bytearray.py \
  > "$SVG_DIR/pathlook_token_${TOKEN_LOW}.data_uri.txt"
```
Expected: output starts with `data:image/svg+xml`.

---

## B3. get_token_metadata()
```bash
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json call --url "$RPC" \
  --contract-address "$PATH_LOOK" --function get_token_metadata \
  --calldata "$PATH_NFT" "$TOKEN_LOW" "$TOKEN_HIGH" \
  | python3 scripts/devnet/_decode_bytearray.py \
  > "$META_DIR/pathlook_token_${TOKEN_LOW}.json"
```
Expected: JSON with `token`, `stage`, and movement flags.
