# Mainnet runbook

See also:
- [Signing OS runbook](signing-os-runbook.md) for the serious split between Dev OS, CI, and Signing OS.

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
NETWORK=mainnet LANE=deploy RUN_ID=$RUN_ID INPUT_FILE=$PARAMS_FILE INPUT_KIND=constructor_params PARAMS_SCHEMA=schemas/path.constructor_params.schema.json npm run ops:lock-inputs
NETWORK=mainnet LANE=deploy RUN_ID=$RUN_ID npm run ops:dispatch-bundle

# After the workflow succeeds, fetch the bundle artifact on the Signing OS.
RUN_DB_ID=<github-actions-run-id>
NETWORK=mainnet RUN_DB_ID=$RUN_DB_ID npm run ops:fetch-bundle

# On the Signing OS, switch to the exact pinned commit before local CD.
BUNDLE_SHA=$(jq -r .git_commit bundles/mainnet/$RUN_ID/run.json)
git fetch origin
git checkout "$BUNDLE_SHA"

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
