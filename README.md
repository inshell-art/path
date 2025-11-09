# path Protocol – Dev Runbook

Protocol deployment + config steps that used to live in `inshell.art/README.md`.
Run these from the `../path` repo (sibling to the FE repo) before syncing data
back into the frontend.

## 1) Declare classes (build → declare → class hashes)

```bash
./scripts/declare-devnet.sh
# Outputs:
#   output/classes.devnet.json   # { "path_nft": "<class_hash>", ... }
#   output/classes.env           # export CLASS_* envs

# Usage:
source output/classes.env
```

Declares four packages: `path_nft`, `path_minter`, `path_minter_adapter`,
`pulse_auction` and records class hashes.

## 2) Deploy contracts (uses class hashes + params)

```bash
./scripts/deploy-devnet.sh
# Outputs:
#   output/addresses.devnet.json # { "path_nft": "<addr>", "path_minter": "...", "path_minter_adapter": "...", "pulse_auction": "..." }
#   output/addresses.env         # export PATH_NFT, PATH_MINTER, PATH_ADAPTER, PULSE_AUCTION, RPC_URL, PROFILE

# Next: load addresses & profile into the shell
source output/addresses.env
```

Constructor calldata is encoded (ByteArray/u256). Deployment order:
`PathNFT` → `PathMinter` → `PathMinterAdapter` → `PulseAuction`.

## 3) Configure roles & wiring (idempotent-friendly)

```bash
./scripts/config-devnet.sh
# Verifies / sets:
#   - NFT.grant(MINTER_ROLE, MINTER)
#   - MINTER.grant(SALES_ROLE, ADAPTER)
#   - Adapter.set_minter, Adapter.set_auction
#   - Adapter.get_config() matches expected addresses
# Exits non-zero only on definite mismatches.
```

## 4) (Optional) Smoke / Seed bids for FE data

**Smoke (simple sanity, N bids with approval):**

```bash
./scripts/smoke.sh
# Produces JSONL log in output/smoke_*.jsonl
```

**Seeder (quote-driven, one bid per block):**

```bash
./scripts/seed-bids.sh
# Produces JSONL log in output/seed_bids_*.jsonl
# Uses get_current_price -> add premium bps -> ensure allowance -> bid
```
