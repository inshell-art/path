# Mainnet runbook

## A) Preflight checklist
- correct network selected (`mainnet`)
- mainnet policy file configured and reviewed
- rehearsal proof available when policy requires it
- tracked git tree clean before bundle/apply
- signing context isolated (`SIGNING_OS=1`)

## B) Execute deploy lane
```bash
npm run evm:compile
npm run evm:test

RUN_ID=mainnet-deploy-$(date -u +%Y%m%dT%H%M%SZ)
NETWORK=mainnet LANE=deploy RUN_ID=$RUN_ID npm run ops:bundle
NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:verify
NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:approve
SIGNING_OS=1 REHEARSAL_PROOF_RUN_ID=<proof_run_id> NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:apply
NETWORK=mainnet RUN_ID=$RUN_ID POSTCONDITIONS_STATUS=pass npm run ops:postconditions
```

## C) Failure handling
- if rehearsal proof gate fails: provide valid `REHEARSAL_PROOF_RUN_ID`
- if verify/apply fails: do not reuse the same bundle after code/policy changes; create a new `RUN_ID`
