# Devnet runbook

## A) Preflight checklist
- correct network selected (`devnet`)
- local EVM node reachable (`http://127.0.0.1:8545`)
- tracked git tree clean before bundle/apply
- signer context ready for `SIGNING_OS=1` apply step

## B) Execute rehearsal
Terminal 1:
```bash
npm run evm:node
```

Terminal 2:
```bash
npm run evm:compile
npm run evm:test

RUN_ID=devnet-deploy-$(date -u +%Y%m%dT%H%M%SZ)
NETWORK=devnet LANE=deploy RUN_ID=$RUN_ID npm run ops:bundle
NETWORK=devnet RUN_ID=$RUN_ID npm run ops:verify
NETWORK=devnet RUN_ID=$RUN_ID npm run ops:approve
SIGNING_OS=1 NETWORK=devnet RUN_ID=$RUN_ID npm run ops:apply
NETWORK=devnet RUN_ID=$RUN_ID npm run ops:postconditions
```

Manual override (optional):
```bash
POSTCONDITIONS_MODE=manual POSTCONDITIONS_STATUS=pass NETWORK=devnet RUN_ID=$RUN_ID npm run ops:postconditions
```

## C) Verification
- verify command exits `0`
- `bundles/devnet/$RUN_ID/` contains:
  - `run.json`, `intent.json`, `checks.json`, `bundle_manifest.json`
  - `approval.json`, `txs.json`, `postconditions.json`
  - `deployments/localhost-eth.json` (for deploy lane)

## D) Optional audit
```bash
AUDIT_ID=$(date -u +%Y%m%dT%H%M%SZ)-devnet-audit
NETWORK=devnet AUDIT_ID=$AUDIT_ID RUN_IDS=$RUN_ID npm run ops:audit:plan
NETWORK=devnet AUDIT_ID=$AUDIT_ID npm run ops:audit:collect
NETWORK=devnet AUDIT_ID=$AUDIT_ID npm run ops:audit:verify
NETWORK=devnet AUDIT_ID=$AUDIT_ID npm run ops:audit:report
NETWORK=devnet AUDIT_ID=$AUDIT_ID AUDIT_APPROVER=<name> npm run ops:audit:signoff
```
