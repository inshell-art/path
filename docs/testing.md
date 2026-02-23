# Testing Path

## EVM / Solidity (primary)

- `npm run evm:test`
- `npm run evm:compile`
- `npm run evm:estimate:deploy:cost`

Local ETH scenario:

- Terminal 1: `npm run evm:node`
- Terminal 2: `npm run evm:local:eth`

## Cairo / Starknet (legacy)

Legacy Cairo code location: `legacy/cairo/`.

Unit suite:

- `npm run cairo:test:unit`
  - Runs `path_nft`, `path_minter`, `path_minter_adapter`
  - Runs PathLook tests from `legacy/cairo/contracts/path_look/contracts`

Full suite:

- `npm run cairo:test:full`
  - Includes unit suite + e2e tests + legacy pulse tests

Package-level forge runs:

- `snforge test --package path_nft`
- `snforge test --package path_minter`
- `snforge test --package path_minter_adapter`
- `snforge test --package path_pulse_e2e`
- `snforge test --package pulse_auction`

PathLook only:

- `cd legacy/cairo/contracts/path_look/contracts && scarb test`
