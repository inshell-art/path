# Testing Path

## Unit suite (fast)

- `./scripts/test-unit.sh`
  - Runs core contract unit tests (`path_nft`, `path_minter`, `path_minter_adapter`)
  - Runs PathLook tests from `contracts/path_look/contracts`

## Full suite (slower)

- `./scripts/test-full.sh`
  - Includes unit suite + e2e tests + vendor pulse tests

## Package-level runs

- `scarb run test -p path_nft`
- `scarb run test -p path_minter`
- `scarb run test -p path_minter_adapter`
- `scarb run test -p path_pulse_e2e`

## PathLook only

- `cd contracts/path_look/contracts && scarb test`
