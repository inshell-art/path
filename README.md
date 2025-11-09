# path Protocol – Dev Runbook

Protocol deployment + config steps that used to live in `inshell.art/README.md`.
Run these from the `../path` repo (sibling to the FE repo) before syncing data
back into the frontend.

## 0) Start Starknet Devnet

```bash
starknet-devnet --host 127.0.0.1 --port 5050 --seed 0 --allow-mint
```

Any equivalent devnet command works; the important bits are:

- RPC listening at `http://127.0.0.1:5050/rpc` (scripts default to this URL).
- Faucet enabled (`--allow-mint`) if you want to fund bidder accounts via `/mint`.
- Deterministic seed so addresses match `.accounts/devnet_oz_accounts.json`.

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

**Smoke (genesis sanity, single bid with approval):**

```bash
./scripts/smoke.sh
# Produces JSONL log in output/smoke_*.jsonl
# Runs only if the Pulse auction's genesis bid is still open.
```

Fund the bidder before running the smoke script (10 000 STRK = `1e4 * 10^18` fri on devnet).
If you’re running Starknet Devnet with the faucet enabled (`--allow-mint` or equivalent), you can use:

```bash
curl -X POST http://127.0.0.1:5050/mint \
  -H 'Content-Type: application/json' \
  -d '{"address":"0x04f348398f859a55a0c80b1446c5fdc37edb3a8478a32f10764659fc241027d3","amount":"10000000000000000000000"}'
```

**Seeder (quote-driven, one bid per block):**

```bash
./scripts/seed-bids.sh
# Produces JSONL log in output/seed_bids_*.jsonl
# Uses get_current_price -> add premium bps -> ensure allowance -> bid
```
