# Mainnet runbook

See also:
- [Signing OS runbook](signing-os-runbook.md) for the serious split between Dev OS, CI, and Signing OS.

## A) Preflight checklist
- correct network selected (`mainnet`)
- mainnet policy file configured and reviewed
- rehearsal proof available when policy requires it
- tracked git tree clean before bundle
- Signing OS is prepared separately with:
  - its own `MAINNET_RPC_URL`
  - its own keystore/password refs
  - its own `SIGNING_OS_MARKER_FILE`
- Dev OS does not need Mainnet signing env for `lock-inputs` or `dispatch-bundle`

## B) Execute deploy lane
```bash
npm run evm:compile
npm run evm:test

RUN_ID=mainnet-deploy-$(date -u +%Y%m%dT%H%M%SZ)
PARAMS_FILE=~/.opsec/path/params.mainnet.deploy.json
NETWORK=mainnet LANE=deploy RUN_ID=$RUN_ID INPUT_FILE=$PARAMS_FILE INPUT_KIND=constructor_params PARAMS_SCHEMA=schemas/path.constructor_params.schema.json npm run ops:lock-inputs
NETWORK=mainnet LANE=deploy RUN_ID=$RUN_ID npm run ops:dispatch-bundle

# After the workflow succeeds, fetch the bundle artifact on the Signing OS.
NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:fetch-bundle

# On the Signing OS, switch to the exact pinned commit before local CD.
BUNDLE_SHA=$(jq -r .git_commit bundles/mainnet/$RUN_ID/run.json)
git fetch origin
git checkout "$BUNDLE_SHA"

SIGNING_OS=1 NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:verify
SIGNING_OS=1 NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:approve
SIGNING_OS=1 REHEARSAL_PROOF_RUN_ID=<proof_run_id> NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:apply
SIGNING_OS=1 NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:postconditions
```

Manual override (optional):
```bash
SIGNING_OS=1 POSTCONDITIONS_MODE=manual POSTCONDITIONS_STATUS=pass NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:postconditions
```

## C) Failure handling
- if rehearsal proof gate fails: provide valid `REHEARSAL_PROOF_RUN_ID`
- if verify/apply fails: do not reuse the same bundle after code/policy changes; create a new `RUN_ID`
