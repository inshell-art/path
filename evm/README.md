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

Optional deploy parameter overrides (constructor inputs):

- Environment variables (`DEPLOY_*`)
- npm run args (`--deploy-*`), which map to script params
- JSON params file (`DEPLOY_PARAMS_FILE=...` or `--deploy-params-file=...`)

Precedence: npm args (`--deploy-*`) > env vars > params file > built-in defaults.

Examples:

```bash
# Override by env vars
DEPLOY_FIRST_PUBLIC_ID=7 DEPLOY_EPOCH_BASE=7 DEPLOY_RESERVED_CAP=5 npm run deploy:local:eth

# Override by npm args
npm run deploy:local:eth --deploy-first-public-id=7 --deploy-epoch-base=7 --deploy-reserved-cap=5 --deploy-name="PATH NFT Custom"

# Override via params file
cat > /tmp/path.deploy.local.json <<'JSON'
{
  "name": "PATH NFT Local",
  "symbol": "PATHL",
  "firstPublicId": "1",
  "epochBase": "1",
  "reservedCap": "3",
  "genesisPrice": "1000",
  "genesisFloor": "900",
  "k": "600",
  "pts": "1",
  "paymentToken": "0x0000000000000000000000000000000000000000"
}
JSON
DEPLOY_PARAMS_FILE=/tmp/path.deploy.local.json npm run deploy:local:eth
```

Outputs:

- deployment metadata: `evm/deployments/localhost-eth.json`
- cascade scenario report: `evm/deployments/reports/localhost-path-cascade-eth-report.json`
- guided rehearsal: `docs/evm/localnet-rehearsal.md`

## Notes

- `PathNFT.tokenURI` returns on-chain metadata as a data URL: `data:application/json;base64,<...>`, with embedded image at `image = data:image/svg+xml;base64,<...>`.
- `PathNFT` emits EIP-4906 `MetadataUpdate(tokenId)` on progression (`consumeUnit`) so indexers can refresh metadata.
- `PathNFT.contractURI` is available for optional contract-level collection metadata.
- This EVM stack has no separate renderer contract.
