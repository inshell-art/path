# PATH Protocol

Primary implementation is now Solidity/EVM in `evm/`.
Legacy Cairo/Starknet contracts and scripts are still available for maintenance and historical deploys.

## EVM (primary)

Quickstart:

```bash
npm run evm:install
npm run evm:compile
npm run evm:test
npm run evm:estimate:deploy:cost
```

Primary repo-level entrypoints:

```bash
npm test
npm run deploy
npm run smoke
npm run scenario
```

Local ETH cascade rehearsal:

Terminal 1:

```bash
npm run evm:node
```

Terminal 2:

```bash
npm run evm:local:eth
# or use root helper scripts:
./scripts/deploy-eth-local.sh
./scripts/smoke-eth-local.sh
./scripts/serial-bids-eth-local.sh
./scripts/scenario-eth-local.sh
```

EVM details live in `evm/README.md`.

## Ops Lanes (Ethereum)

Ops-lanes template is vendored at `opsec-ops-lanes-template/` and downstream instance files live at:

- `ops/` (policy, tools, runbooks)
- `artifacts/` (generated evidence)
- `bundles/` (immutable CI/CD bundles)

Vendored source: `https://github.com/inshell-art/opsec-ops-lanes-template` at commit `c274fda`.

Quick rehearsal (bundle + verify only):

```bash
NETWORK=sepolia LANE=plan RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)-local npm run ops:bundle
NETWORK=sepolia RUN_ID=<same_run_id> npm run ops:verify
```

Apply path (Signing OS only):

```bash
NETWORK=sepolia RUN_ID=<same_run_id> npm run ops:approve
SIGNING_OS=1 NETWORK=sepolia RUN_ID=<same_run_id> npm run ops:apply
NETWORK=sepolia RUN_ID=<same_run_id> POSTCONDITIONS_STATUS=pass npm run ops:postconditions
```

Local ops env variable examples are in `ops/env.example` (do not commit secrets).

## Cairo/Starknet (legacy)

Legacy Cairo sources now live under `legacy/cairo/`:

- `legacy/cairo/contracts`
- `legacy/cairo/interfaces`
- `legacy/cairo/crates`

### Tests

```bash
npm run cairo:test:unit
npm run cairo:test:full
```

### Sepolia runbook (legacy local deploy)

Set local env/params (not committed):

```bash
cat > scripts/.env.sepolia.local <<'EOF'
RPC_URL="https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_10/<key>"
SNCAST_ACCOUNTS_FILE="$HOME/.starknet_accounts/sepolia_accounts.json"
SNCAST_ACCOUNTS_NAMESPACE="alpha-sepolia"
DECLARE_PROFILE="main-sep"
DEPLOY_PROFILE="main-sep"
CONFIG_PROFILE="pathnft_owner"
ADMIN_PROFILE="PathNFT-owner"
EOF

cat > scripts/params.sepolia.local <<'EOF'
PAYTOKEN="<STRK_SEPOLIA_ADDRESS>"
TREASURY="<TREASURY_ADDRESS>"
PPRF_ADDR=""
STEP_CURVE_ADDR=""
EOF
```

Declare + deploy + configure:

```bash
CLASS_PULSE="<pulse_class_hash>" npm run legacy:declare:sepolia
npm run legacy:deploy:sepolia
npm run legacy:config:sepolia
npm run legacy:verify:sepolia
```

Artifacts:
- `output/sepolia/classes.sepolia.json`
- `output/sepolia/addresses.sepolia.json`
- `output/sepolia/addresses.sepolia.env`
- `output/sepolia/deploy.params.sepolia.json`
