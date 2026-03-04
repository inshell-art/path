# PATH Protocol

Primary implementation is now Solidity/EVM in `evm/`.

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

Ops-lanes template is synced as a git subtree at `opsec-ops-lanes-template/`, and downstream instance files live at:

- `ops/` (policy, tools, runbooks)
- `artifacts/` (generated evidence)
- `bundles/` (immutable CI/CD bundles)

Upstream source: `https://github.com/inshell-art/opsec-ops-lanes-template` at commit `77d3e7f`.

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

Quick local audit (devnet):

```bash
AUDIT_ID=$(date -u +%Y%m%dT%H%M%SZ)-devnet-audit
NETWORK=devnet AUDIT_ID=$AUDIT_ID RUN_IDS=<run1,run2> npm run ops:audit:plan
NETWORK=devnet AUDIT_ID=$AUDIT_ID npm run ops:audit:collect
NETWORK=devnet AUDIT_ID=$AUDIT_ID npm run ops:audit:verify
NETWORK=devnet AUDIT_ID=$AUDIT_ID npm run ops:audit:report
NETWORK=devnet AUDIT_ID=$AUDIT_ID AUDIT_APPROVER=<name> npm run ops:audit:signoff
```
