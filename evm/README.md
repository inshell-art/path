# Path (EVM / Solidity)

This folder contains the Ethereum Solidity port for the PATH stack in this repo.

Core contracts:

- `evm/src/PathNFT.sol` ports `legacy/cairo/contracts/path_nft/src/path_nft.cairo`
- `evm/src/PathMinter.sol` ports `legacy/cairo/contracts/path_minter/src/path_minter.cairo`
- `evm/src/PathMinterAdapter.sol` ports `legacy/cairo/contracts/path_minter_adapter/src/path_minter_adapter.cairo`
- `evm/src/PulseAuction.sol` ports `vendors/pulse/legacy/cairo/crates/pulse_auction/src/pulse_auction.cairo`

Test mocks:

- `evm/src/mocks/MockMovementMinter.sol`
- `evm/src/mocks/MockERC721Receiver.sol`
- `evm/src/mocks/RejectingERC721Receiver.sol`
- `evm/src/mocks/StubPathMinter.sol`
- `evm/src/mocks/BidBatcher.sol`

## Hardhat

```bash
cd evm
npm install
npm test
npm run estimate:deploy:cost
```

Override pricing assumptions if needed:

```bash
GAS_PRICE_GWEI=20 ETH_USD=3000 npm run estimate:deploy:cost
```

## Local Devnet (ETH Payment)

The local scripts deploy a full ETH-settled stack:

- `PathNFT`
- `PathMinter`
- `PathMinterAdapter`
- `PulseAuction` (`paymentToken = address(0)`)

In one terminal:

```bash
cd evm
npm run node
```

In another terminal:

```bash
cd evm
npm run deploy:local:eth
npm run smoke:local:eth
npm run scenario:local:eth
```

Outputs:

- deployment metadata: `evm/deployments/localhost-eth.json`
- cascade scenario report: `evm/deployments/reports/localhost-path-cascade-eth-report.json`
- guided rehearsal: `docs/evm/localnet-rehearsal.md`

## Notes

- `PathNFT.tokenURI` returns `baseUri + tokenId`.
- This EVM stack has no separate renderer contract.
