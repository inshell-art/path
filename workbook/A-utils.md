# Group A — Utilities (pprf + step-curve)

## A0. Prep
```bash
source scripts/devnet/00_env.sh
```

Deploy both utility contracts:
```bash
scripts/devnet/01_deploy_utils.sh
```

Load addresses from artifacts:
```bash
PPRF=$(jq -r '.glyph_pprf' "$ADDR_FILE")
STEP_CURVE=$(jq -r '.step_curve' "$ADDR_FILE")
```

---

## A1. pprf checks

### A1.1 metadata()
```bash
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" call --url "$RPC" \
  --contract-address "$PPRF" --function metadata
```
Expected: a short ASCII metadata span describing pprf.

### A1.2 render() determinism
Use a stable param list (seed + salt + index). Example:
```bash
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" call --url "$RPC" \
  --contract-address "$PPRF" --function render \
  --calldata 3 1 2 3
```
Expected: a single felt `v` in `[0, 999_999]`. Re-run with the same params and expect the same result.

---

## A2. step-curve checks

### A2.1 metadata()
```bash
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" call --url "$RPC" \
  --contract-address "$STEP_CURVE" --function metadata
```
Expected: metadata includes `name=step_curve` and `params=handle_scale,xy_pairs`.

### A2.2 render() basic (2 points)
`render` params layout:
```
[handle_scale, x0, y0, x1, y1, x2, y2, ...]
```
Example with two points (0,0) → (100,100):
```bash
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json call --url "$RPC" \
  --contract-address "$STEP_CURVE" --function render \
  --calldata 5 5 0 0 100 100 \
  | python3 scripts/devnet/_decode_bytearray.py \
  > "$SVG_DIR/stepcurve_case_1.d.txt"
```
Expected: a valid SVG `d` string in `stepcurve_case_1.d.txt`.

### A2.3 render() multi-point
```bash
sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json call --url "$RPC" \
  --contract-address "$STEP_CURVE" --function render \
  --calldata 9 5 0 0 50 100 100 0 150 100 \
  | python3 scripts/devnet/_decode_bytearray.py \
  > "$SVG_DIR/stepcurve_case_2.d.txt"
```
Expected: a longer `d` string with multiple curve segments.

---

Artifacts created:
- `workbook/artifacts/devnet/svg/stepcurve_case_1.d.txt`
- `workbook/artifacts/devnet/svg/stepcurve_case_2.d.txt`
