# Mainnet runbook

## A) Preflight checklist
- correct network selected (`mainnet`)
- mainnet policy file configured and reviewed
- `MAINNET_RPC_URL` loaded from local env (not committed)
- deploy signer keystore env is present:
  - `MAINNET_DEPLOY_KEYSTORE_JSON` (path or inline JSON)
  - and one of `MAINNET_DEPLOY_KEYSTORE_PASSWORD` or `MAINNET_DEPLOY_KEYSTORE_PASSWORD_FILE`
- `MAINNET_PRIVATE_KEY` is not pre-set in shell
- rehearsal proof available when policy requires it
- tracked git tree clean before bundle/apply
- signing context isolated (`SIGNING_OS=1`)

## B) Execute deploy lane
```bash
npm run evm:compile
npm run evm:test

RUN_ID=mainnet-deploy-$(date -u +%Y%m%dT%H%M%SZ)
PARAMS_FILE=~/.opsec/path/params.mainnet.deploy.json
NETWORK=mainnet LANE=deploy RUN_ID=$RUN_ID INPUT_FILE=$PARAMS_FILE INPUT_KIND=constructor_params PARAMS_SCHEMA=opsec-ops-lanes-template/examples/inputs/params.constructor_params.schema.example.json npm run ops:lock-inputs
INPUTS_TEMPLATE=artifacts/mainnet/current/inputs/inputs.$RUN_ID.json NETWORK=mainnet LANE=deploy RUN_ID=$RUN_ID npm run ops:bundle
NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:verify
NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:approve
SIGNING_OS=1 REHEARSAL_PROOF_RUN_ID=<proof_run_id> NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:apply
NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:postconditions
```

Manual override (optional):
```bash
POSTCONDITIONS_MODE=manual POSTCONDITIONS_STATUS=pass NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:postconditions
```

## C) Failure handling
- if rehearsal proof gate fails: provide valid `REHEARSAL_PROOF_RUN_ID`
- if verify/apply fails: do not reuse the same bundle after code/policy changes; create a new `RUN_ID`
