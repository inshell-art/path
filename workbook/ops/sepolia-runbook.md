# Sepolia runbook

## A) Preflight checklist
- correct network selected (`sepolia`)
- `SEPOLIA_RPC_URL` and `SEPOLIA_PRIVATE_KEY` loaded from local env (not committed)
- `ops/policy/lane.sepolia.json` placeholders resolved (RPC allowlist, signer map, fee policy)
- tracked git tree clean before bundle/apply

## B) Execute deploy lane
```bash
npm run evm:compile
npm run evm:test

RUN_ID=sepolia-deploy-$(date -u +%Y%m%dT%H%M%SZ)
NETWORK=sepolia LANE=deploy RUN_ID=$RUN_ID npm run ops:bundle
NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:verify
NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:approve
SIGNING_OS=1 NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:apply
NETWORK=sepolia RUN_ID=$RUN_ID POSTCONDITIONS_STATUS=pass npm run ops:postconditions
```

## C) Capture deployment outputs
- confirm `bundles/sepolia/$RUN_ID/deployments/sepolia-eth.json` exists
- copy promoted deployment metadata to your chosen publishing target if needed

## D) Failure handling
- if verify fails due policy/check mismatch: fix policy or deployment inputs, then create a new `RUN_ID`
- if commit changes after bundle: rerun bundle/verify/approve with a new `RUN_ID`
