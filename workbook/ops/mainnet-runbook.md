# Mainnet runbook

See also:
- [Signing OS runbook](signing-os-runbook.md) for the serious split between Dev OS, CI, and Signing OS.

Use this runbook as the default meaning of "deploy on Mainnet" for this repo.
Do not switch to a direct ad hoc Hardhat deploy path unless you are intentionally bypassing the repo-managed ops lane.

## A) Preflight checklist
- correct network selected (`mainnet`)
- mainnet policy file configured and reviewed
- rehearsal proof available when policy requires it
- tracked git tree clean before bundle
- constructor params file exists at `~/.opsec/path/params.mainnet.deploy.json`
- Signing OS is prepared separately with:
  - its own `MAINNET_RPC_URL`
  - its own keystore/password refs
  - its own `SIGNING_OS_MARKER_FILE`
- Dev OS does not need Mainnet signing env for `lock-inputs` or `dispatch-bundle`

## B) Dev OS steps
```bash
install -d -m 700 ~/.opsec/path
$EDITOR ~/.opsec/path/params.mainnet.deploy.json
chmod 600 ~/.opsec/path/params.mainnet.deploy.json

npm run evm:compile
npm run evm:test

RUN_ID=mainnet-deploy-$(date -u +%Y%m%dT%H%M%SZ)
PARAMS_FILE=~/.opsec/path/params.mainnet.deploy.json
NETWORK=mainnet LANE=deploy RUN_ID=$RUN_ID INPUT_FILE=$PARAMS_FILE INPUT_KIND=constructor_params PARAMS_SCHEMA=schemas/path.constructor_params.schema.json npm run ops:lock-inputs
NETWORK=mainnet LANE=deploy RUN_ID=$RUN_ID npm run ops:dispatch-bundle
printf 'NETWORK=%s\nRUN_ID=%s\n' mainnet "$RUN_ID"
```

## C) Handoff note

Carry only:

```text
NETWORK=mainnet
RUN_ID=<bundle-run-id>
REHEARSAL_PROOF_RUN_ID=<accepted-proof-run-id>
```

## D) Signing OS steps

On the Signing OS, from the repo root:

```bash
NETWORK=mainnet
RUN_ID=<bundle-run-id>
GH_REPO=inshell-art/path

# After the workflow succeeds, fetch the bundle artifact on the Signing OS.
git fetch origin
git checkout main
git pull origin main
git diff --quiet && git diff --cached --quiet || { echo "tracked tree is dirty"; exit 1; }

npm run ops:fetch-bundle

BUNDLE_SHA=$(jq -r .git_commit bundles/mainnet/$RUN_ID/run.json)
git fetch origin
git checkout "$BUNDLE_SHA"
git diff --quiet && git diff --cached --quiet || { echo "tracked tree is dirty"; exit 1; }

set -a
source ~/.opsec/path/mainnet.env
set +a
unset MAINNET_PRIVATE_KEY

SIGNING_OS=1 NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:verify
SIGNING_OS=1 NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:approve
SIGNING_OS=1 REHEARSAL_PROOF_RUN_ID=<proof_run_id> NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:apply
SIGNING_OS=1 NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:postconditions
```

Manual override (optional):
```bash
SIGNING_OS=1 POSTCONDITIONS_MODE=manual POSTCONDITIONS_STATUS=pass NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:postconditions
```

## E) Failure handling
- if rehearsal proof gate fails: provide valid `REHEARSAL_PROOF_RUN_ID`
- if verify/apply fails: do not reuse the same bundle after code/policy changes; create a new `RUN_ID`
