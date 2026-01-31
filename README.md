# path Protocol – Dev Runbook

Protocol deployment + config steps that used to live in `inshell.art/README.md`.
Run these from the `../path` repo (sibling to the FE repo) before syncing data
back into the frontend.

## Sepolia Runbook (local deploy)

Set local env/params (these are not committed):

```bash
# Required env
cat > scripts/.env.sepolia.local <<'EOF'
RPC_URL="https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_10/<key>"
SNCAST_ACCOUNTS_FILE="$HOME/.starknet_accounts/sepolia_accounts.json"
SNCAST_ACCOUNTS_NAMESPACE="alpha-sepolia"
DECLARE_PROFILE="main-sep"
DEPLOY_PROFILE="main-sep"
CONFIG_PROFILE="pathnft_owner"
ADMIN_PROFILE="PathNFT-owner"
EOF

# Required params
cat > scripts/params.sepolia.local <<'EOF'
PAYTOKEN="<STRK_SEPOLIA_ADDRESS>"
TREASURY="<TREASURY_ADDRESS>"
# Optional reuse of glyph deployments
PPRF_ADDR=""
STEP_CURVE_ADDR=""
EOF
```

Declare + deploy + configure:

```bash
# Pulse class should be declared in the pulse repo; export CLASS_PULSE if already declared.
CLASS_PULSE="<pulse_class_hash>" ./scripts/declare-sepolia.sh
./scripts/deploy-sepolia.sh
./scripts/config-sepolia.sh
./scripts/verify-sepolia.sh
```

Artifacts:
- `output/sepolia/classes.sepolia.json`
- `output/sepolia/addresses.sepolia.json`
- `output/sepolia/addresses.sepolia.env`
- `output/sepolia/deploy.params.sepolia.json`

## 0) Devnet (managed in ../localnet)

Devnet is managed in the dedicated local repo at `../localnet`.

- Start/stop and watchdog docs: `../localnet/README.md`
- RPC should be available at `http://127.0.0.1:5050/rpc`
- Use seed `0` so addresses match:
  `/Users/bigu/Projects/localnet/.accounts/devnet_oz_accounts.json`


## 1) Declare classes (build → declare → class hashes)

```bash
./scripts/declare-devnet.sh
# Outputs:
#   output/classes.devnet.json   # { "path_nft": "<class_hash>", ... }
#   output/classes.env           # export CLASS_* envs

# Usage:
source output/classes.env
```

Declares packages: `path_nft`, `path_minter`, `path_minter_adapter`, `pulse_auction`,
plus `glyph_pprf`, `step_curve`, and `path_look` (PathLook + deps).

## 2) Deploy contracts (uses class hashes + params)

```bash
./scripts/deploy-devnet.sh
# Outputs:
#   output/addresses.devnet.json # { "path_nft": "<addr>", "path_minter": "...", "path_minter_adapter": "...", "pulse_auction": "...", "path_look": "...", "glyph_pprf": "...", "step_curve": "..." }
#   output/addresses.env         # export PATH_NFT, PATH_MINTER, PATH_ADAPTER, PULSE_AUCTION, PATH_LOOK, PATH_PPRF, PATH_STEP_CURVE, RPC_URL, PROFILE

# Next: load addresses & profile into the shell
source output/addresses.env
```

Constructor calldata is encoded (ByteArray/u256). Deployment order:
`Pprf` → `StepCurve` → `PathLook` → `PathNFT` → `PathMinter` → `PathMinterAdapter` → `PulseAuction`.

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

**Pulse bidding loop (trigger rule from the spec in `docs/specs/PULSE_Bid_Trigger_Spec.md`):**

```bash
# One-time approve (example amount = 1e25 wei) for the bidder profile
source output/addresses.env
export PAYTOKEN=$(awk -F= '/^PAYTOKEN=/{gsub(/"/,"");print $2}' scripts/params.devnet.example)
sncast --profile dev_bidder1 invoke \
  --contract-address "$PAYTOKEN" \
  --function approve \
  --calldata "$PULSE_AUCTION" 10000000000000000000000000 0

# Run N triggered bids (θ sampled each bid from clipped Normal)
./scripts/bid.sh 5
```

The loop derives the last sale from on-chain events, computes τ/hammer from k/θ/floor/D, waits until the scheduled time, bids with a max_price guard, and logs pre/post curve checks plus settlement info to `output/pulse_runs.jsonl`. It aborts early if the devnet RPC is down or allowance is insufficient.
