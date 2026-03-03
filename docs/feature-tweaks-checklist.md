# Feature Tweaks Prep Checklist

## Path contracts
- [ ] Confirm target branch and spec docs to apply.
- [ ] Re-sync deployment addresses (PathNFT, PathMinter, PathMinterAdapter, PulseAuction).
- [ ] Re-run EVM tests: `npm run evm:test`.
- [ ] Re-run compile check: `npm run evm:compile`.
- [ ] Update EVM docs if wiring or role changes.

## inshell.art UI
- [ ] Pull latest contract addresses (devnet/sepolia) and verify `addresses/*` inputs.
- [ ] Re-run unit tests: `npm run test:unit`.
- [ ] Verify look tab flow with current `PathNFT.tokenURI` metadata.
- [ ] Update `docs/testing.md` if new scripts or views are added.

## Devnet + hand checks
- [ ] Start local Hardhat node.
- [ ] Deploy EVM PATH stack (`npm run evm:deploy:local:eth`).
- [ ] Wire roles and freeze checks pass in deployment output.
- [ ] Mint a PATH via auction flow and validate `tokenURI` + metadata SVG.
- [ ] Run a bid and confirm adapter -> minter -> nft mint pipeline.

## Commit hygiene
- [ ] Keep changes scoped by repo.
- [ ] Record test commands used in commit message or PR notes.
