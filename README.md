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


## Devnet deploy + bids (moved)

Devnet deploy/config/smoke scripts now live in `../localnet/scripts/`.
Run them from the localnet repo (they default to using the sibling `../path` repo).

Suggested flow:
- `../localnet/scripts/declare-devnet.sh`
- `../localnet/scripts/deploy-devnet.sh`
- `../localnet/scripts/config-devnet.sh`
- `../localnet/scripts/smoke.sh`
- `../localnet/scripts/bid.sh`
