# Path Look - On-Chain SVG Generator for Starknet

Path Look is an on-chain SVG generation contract built on Starknet using Cairo 2. The Scarb package is `path_look` and the deployed contract name is `PathLook`. Path rendering is delegated to the external [`step-curve`](https://github.com/inshell-art/step-curve) contract.

## Quick Start

### Prerequisites
- Rust (for Scarb build)
- sncast (Starknet Foundry CLI)
- Local Starknet Devnet (running on `http://127.0.0.1:5050`)
- Python 3 (for the helper scripts)

### Build

```bash
cd contracts
scarb build
```

### Deploy (devnet)

Use the helper scripts from the repo root:

```bash
./contracts/scripts/devnet_deploy.sh      # declare + deploy pprf, step-curve, path-look
./contracts/scripts/devnet_smoke.sh       # call PathLook + StepCurve once deployed
```

Addresses and class hashes are written to `devnet-deploy.json`.
Defaults assume a funded account `dev_deployer` in `~/.starknet_accounts/devnet_oz_accounts.json`; override with `ACCOUNT_NAME`/`ACCOUNTS_FILE` if needed.

Manual steps (if you prefer):
1. Deploy `Pprf`.
2. Deploy `StepCurve`.
3. Deploy `PathLook` with constructor calldata `[pprf_address, step_curve_address]`.

### Call the Contract

Generate an SVG with custom parameters:

```bash
sncast call \
  --contract-address 0x04add2e03e6c61bde38205a88f2f0bc5da68f46d8d5c101bd3629d6d9436684c \
  --function generate_svg \
  --calldata 1 1 0 0 \
  --url http://127.0.0.1:5050
```

Parameters (calldata):
- `token_id` (u32): Token identifier
- `thought_rank` (u8): 0 if unminted, otherwise 1–3 (lower is earlier minted)
- `will_rank` (u8): 0 if unminted, otherwise 1–3
- `awa_rank` (u8): 0 if unminted, otherwise 1–3

### Extract SVG Output

The contract returns an SVG string. Extract it from the response:

```bash
sncast call \
  --contract-address 0x04add2e03e6c61bde38205a88f2f0bc5da68f46d8d5c101bd3629d6d9436684c \
  --function generate_svg \
  --calldata 1 1 0 0 \
  --url http://127.0.0.1:5050 | \
  sed -n '/<svg/,/<\/svg>/p' | \
  sed -e '/Account address/d' -e '/Private key/d'
```

## Project Structure

- `contracts/src/PathLook.cairo` - Main contract (uses the external `step-curve` contract for path rendering)
- `contracts/src/rng.cairo` - Poseidon PRF utilities
- `contracts/src/lib.cairo` - Module exports
- `contract_hashes.json` - Deployed contract addresses and class hashes
- `accounts.devnet.json` - Predeployed account credentials (for devnet)

## Development

See `snfoundry.toml` for Starknet Foundry configuration.

## License

MIT
