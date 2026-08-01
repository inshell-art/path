# PATH artifact preview

`index.html` is the repository-owned preview for exact `PathNFT.tokenURI`
artifacts. It does not recreate contract artwork in frontend code.

Regenerate the embedded local snapshots from the current compiled contracts:

```bash
npm run evm:preview:generate
npm run evm:preview:verify
```

The generator deploys `PathNFT`, `PathPulseAdapter`, and `PulseAuction` on an
ephemeral Hardhat chain, freezes the canonical public mint path, configures
movement quotas `1 / 10 / 1`, mints through the auction, consumes representative
movement states, and records exact `tokenURI.image` data URLs.

Open `index.html` directly. No RPC, wallet, font installation, package install,
or web server is required after generation.
