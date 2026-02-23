# PATH Legacy Cairo Workspace

This folder contains the legacy Starknet/Cairo implementation that predates the Solidity/EVM migration.

Layout:
- `legacy/cairo/contracts/`
- `legacy/cairo/interfaces/`
- `legacy/cairo/crates/`

Run legacy tests from repo root:

```bash
npm run cairo:test:unit
npm run cairo:test:full
```

Legacy Sepolia deploy flow from repo root:

```bash
npm run legacy:declare:sepolia
npm run legacy:deploy:sepolia
npm run legacy:config:sepolia
npm run legacy:verify:sepolia
```

Note: root `contracts/`, `interfaces/`, and `crates/` paths are compatibility symlinks to this directory.
