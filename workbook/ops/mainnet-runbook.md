# Mainnet runbook

See also:
- [Signing OS Stage 1 runbook](signing-os-stage1-runbook.md)
- [Signing OS Stage 2 runbook](signing-os-stage2-runbook.md)
- [Signing OS Stage 3 runbook](signing-os-stage3-runbook.md)
- [Signing OS runbook](signing-os-runbook.md) for stage selection only

Use this runbook as the default meaning of "deploy on Mainnet" for this repo.
Do not switch to a direct ad hoc Hardhat deploy path unless you are intentionally bypassing the repo-managed ops lane.

This file is the Dev OS and handoff runbook for Mainnet.
For the Signing OS half, stop here and use the selected stage runbook only.

## A) Preflight checklist
- correct network selected (`mainnet`)
- choose the Signing OS stage first
- if the deploy signer is new or rotated, complete the selected Signing OS stage runbook setup and `signer-enrollment-runbook.md` first; push policy from Dev OS before any serious Dev OS preflight or bundle creation
- mainnet policy file configured and reviewed
- rehearsal proof available when policy requires it
- run `CHECK_GH_AUTH=1 NETWORK=mainnet LANE=deploy npm run ops:preflight:devos` on Dev OS before a serious run; it checks toolchain, clean git state, policy readiness, full secret scan, compile/test, params presence, and optional GitHub auth
- tracked git tree clean before bundle
- constructor params file exists at `~/.opsec/path/params/params.mainnet.deploy.json`
- Signing OS is prepared separately from the selected stage runbook
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

Next step:
- stop using this Mainnet runbook for execution
- open the selected Signing OS stage runbook
- execute the Signing OS half from that stage runbook only

The selected stage runbook contains:
- Signing OS preflight
- bundle fetch
- pinned checkout
- env load
- `ops:verify`
- `ops:approve`
- `ops:apply`
- `ops:postconditions`
- audit
- stage-specific pass criteria

## D) Acceptance rule

Do not treat a completed Mainnet run as accepted release evidence until the selected stage runbook completes and:
- `postconditions.json` status is `pass`
- `audit_verify.json` status is `pass`
- `audit_report.json` status is `pass`
- `audit_signoff.json` exists

## E) Failure handling
- if rehearsal proof gate fails: provide valid `REHEARSAL_PROOF_RUN_ID`
- if verify/apply fails: do not reuse the same bundle after code/policy changes; create a new `RUN_ID`
- if audit fails or is incomplete: the run is already on-chain, but do not accept it as clean release evidence until the audit gap is resolved through the documented process
- if the Signing OS runbook proves insufficient during execution: stop the Signing OS run, fix the repo on Dev OS, push, and restart with a fresh run
