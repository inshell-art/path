# Mainnet runbook

See also:
- [Signing OS runbook](signing-os-runbook.md) for the serious split between Dev OS, CI, and Signing OS.

Use this runbook as the default meaning of "deploy on Mainnet" for this repo.
Do not switch to a direct ad hoc Hardhat deploy path unless you are intentionally bypassing the repo-managed ops lane.

## A) Preflight checklist
- correct network selected (`mainnet`)
- mainnet policy file configured and reviewed
- rehearsal proof available when policy requires it
- run `CHECK_GH_AUTH=1 NETWORK=mainnet LANE=deploy npm run ops:preflight:devos` on Dev OS before a serious run; it checks toolchain, clean git state, policy readiness, full secret scan, compile/test, params presence, and optional GitHub auth
- if using a new or rotated signer, `signer-enrollment-runbook.md` completed and policy pushed from Dev OS
- tracked git tree clean before bundle
- constructor params file exists at `~/.opsec/path/params/params.mainnet.deploy.json`
- Signing OS is prepared separately with:
  - its own `MAINNET_RPC_URL`
  - its own keystore/password refs
  - its own `SIGNING_OS_MARKER_FILE`
- Dev OS does not need Mainnet signing env for `lock-inputs` or `dispatch-bundle`

## B) Dev OS steps
```bash
install -d -m 700 ~/.opsec/path
install -d -m 700 ~/.opsec/path/params
$EDITOR ~/.opsec/path/params/params.mainnet.deploy.json
chmod 600 ~/.opsec/path/params/params.mainnet.deploy.json

CHECK_GH_AUTH=1 NETWORK=mainnet LANE=deploy npm run ops:preflight:devos

RUN_ID=mainnet-deploy-$(date -u +%Y%m%dT%H%M%SZ)
PARAMS_FILE=~/.opsec/path/params/params.mainnet.deploy.json
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

Target Signing OS rule:
- execute the Signing OS half from the runbook only
- if any Signing OS step fails because the process or docs are insufficient, stop and return to Dev OS for the fix

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

CHECK_GH_AUTH=1 NETWORK=mainnet LANE=deploy npm run ops:preflight:signingos

npm run ops:fetch-bundle

BUNDLE_SHA=$(jq -r .git_commit bundles/mainnet/$RUN_ID/run.json)
git fetch origin
git checkout "$BUNDLE_SHA"
git diff --quiet && git diff --cached --quiet || { echo "tracked tree is dirty"; exit 1; }

set -a
source ~/.opsec/path/env/mainnet.env
set +a
unset MAINNET_PRIVATE_KEY

SIGNING_OS=1 NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:verify
SIGNING_OS=1 NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:approve
SIGNING_OS=1 REHEARSAL_PROOF_RUN_ID=<proof_run_id> NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:apply
SIGNING_OS=1 NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:postconditions
```

Stage-1 same-machine note:
- if Signing OS secrets live under `~/Projects/SIGNING_OS/.opsec`, prepend `OPSEC_ROOT=~/Projects/SIGNING_OS/.opsec` to the preflight command

Manual override (optional):
```bash
SIGNING_OS=1 POSTCONDITIONS_MODE=manual POSTCONDITIONS_STATUS=pass NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:postconditions
```

## E) Audit the completed run

Do not treat a completed mainnet run as accepted release evidence until the post-run audit passes and signoff is written:

```bash
AUDIT_ID=mainnet-audit-$(date -u +%Y%m%dT%H%M%SZ)
NETWORK=mainnet AUDIT_ID=$AUDIT_ID RUN_IDS=$RUN_ID npm run ops:audit:plan
NETWORK=mainnet AUDIT_ID=$AUDIT_ID npm run ops:audit:collect
NETWORK=mainnet AUDIT_ID=$AUDIT_ID npm run ops:audit:verify
NETWORK=mainnet AUDIT_ID=$AUDIT_ID npm run ops:audit:report
NETWORK=mainnet AUDIT_ID=$AUDIT_ID AUDIT_APPROVER=<name> npm run ops:audit:signoff
```

Detailed audit procedure:
- `audit-runbook.md`

Acceptance rule:
- `postconditions.json` status is `pass`
- `audit_verify.json` status is `pass`
- `audit_report.json` status is `pass`
- `audit_signoff.json` exists

## F) Failure handling
- if rehearsal proof gate fails: provide valid `REHEARSAL_PROOF_RUN_ID`
- if verify/apply fails: do not reuse the same bundle after code/policy changes; create a new `RUN_ID`
- if audit fails or is incomplete: the run is already on-chain, but do not accept it as clean release evidence until the audit gap is resolved through the documented process
- if the Signing OS runbook proves insufficient during execution: stop the Signing OS run, fix the repo on Dev OS, push, and restart with a fresh run
