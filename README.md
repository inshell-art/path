# path Protocol – Dev Runbook

Protocol deployment + config steps that used to live in `inshell.art/README.md`.
Run these from the `../path` repo (sibling to the FE repo) before syncing data
back into the frontend.

## 0) Start Starknet Devnet

```bash
# Include --allow-mint only if your devnet build supports the faucet flag.
starknet-devnet --host 127.0.0.1 --port 5050 --seed 0
```

Any equivalent devnet command works; the important bits are:

- RPC listening at `http://127.0.0.1:5050/rpc` (scripts default to this URL).
- Faucet endpoint (via `--allow-mint` or the flag your build provides) if you want to fund bidder accounts through `/mint`. On builds without that flag, fund via manual ERC-20 transfers instead.
- Deterministic seed so addresses match `.accounts/devnet_oz_accounts.json`.

### Watchdog loop (nohup-friendly)

To keep devnet running while you log out, launch the watchdog under `nohup` (or drop it into `tmux` if you prefer). The script auto-restores dumps via the `devnet_load` RPC and restarts on crash:

```bash
nohup ./scripts/devnet_watchdog.sh >output/devnet/watchdog.log 2>&1 &
```

Key knobs can be overridden via env vars before launching:

| Variable | Meaning |
| --- | --- |
| `DEVNET_HOST` / `DEVNET_PORT` | RPC bind address (defaults `127.0.0.1:5050`). |
| `DEVNET_INITIAL_BALANCE` | Funds per preloaded account (fri). |
| `DEVNET_DUMP_FILE` | Where dumps are written/read (`output/devnet/devnet.dump.json`). |
| `DEVNET_ADDITIONAL_ARGS` | Extra flags passed verbatim to `starknet-devnet` (e.g. `--initial-balance` or `--allow-mint`). |
| `DEVNET_LOAD_ON_START` | Set `0` to skip automatic `devnet_load`. |
| `DEVNET_INIT_WAIT` | Seconds to wait before polling `/is_alive` (default `5`). |

Watchdog logs: `output/devnet/devnet.log`. Stop it with `pkill -f scripts/devnet_watchdog.sh`.

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

Fund the bidder before running the smoke script (the genesis ask is ~10 000 STRK by default).
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
