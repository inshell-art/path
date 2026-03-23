# Sepolia runbook

See also:
- [Signing OS Stage 1 runbook](signing-os-stage1-runbook.md)
- [Signing OS Stage 2 runbook](signing-os-stage2-runbook.md)
- [Signing OS Stage 3 runbook](signing-os-stage3-runbook.md)
- [Signing OS runbook](signing-os-runbook.md) for stage selection only

Use this runbook as the default meaning of "deploy on Sepolia" for this repo.
Do not switch to a direct ad hoc Hardhat deploy path unless you are intentionally bypassing the repo-managed ops lane.

Stage semantics for serious rehearsal:
- stage 1: use [Signing OS Stage 1 runbook](signing-os-stage1-runbook.md)
- stage 2: use [Signing OS Stage 2 runbook](signing-os-stage2-runbook.md)
- stage 3: use [Signing OS Stage 3 runbook](signing-os-stage3-runbook.md)

This file is the Dev OS and handoff runbook for Sepolia.
For the Signing OS half, stop here and use the selected stage runbook only.

## A) Preflight checklist
- correct network selected (`sepolia`)
- choose the Signing OS stage first
- if the deploy signer is new or rotated, complete the selected Signing OS stage runbook setup and `signer-enrollment-runbook.md` first; push policy from Dev OS before any serious Dev OS preflight or bundle creation
- choose the intended Signing OS Sepolia provider on Dev OS first; if its host is new, add it to `rpc_host_allowlist` before the first serious run
- constructor params file exists at `~/.opsec/path/params/params.sepolia.deploy.json`
- `ops/policy/lane.sepolia.json` placeholders resolved (RPC allowlist, signer map, fee policy)
- public handoff file prepared on Dev OS at `~/.opsec/path/handoff/path-handoff.sepolia.public.env`
- private runtime handoff file prepared on Dev OS at `~/.opsec/path/handoff/path-handoff.signing-runtime.sepolia.env`
- run `CHECK_GH_AUTH=1 NETWORK=sepolia LANE=deploy npm run ops:preflight:devos` on Dev OS before a serious run; it now also expects the intended Signing OS RPC URL to be loaded so policy sealing is checked
- tracked git tree clean before bundle
- Signing OS is prepared separately from the selected stage runbook
- Dev OS does not need Sepolia signing keystore env for `lock-inputs` or `dispatch-bundle`, but serious preflight now expects the intended Signing OS Sepolia RPC URL in shell env

## B) Dev OS steps
```bash
install -d -m 700 ~/.opsec/path
install -d -m 700 ~/.opsec/path/params
install -d -m 700 ~/.opsec/path/handoff
$EDITOR ~/.opsec/path/params/params.sepolia.deploy.json

# Example params file:
# {
#   "name": "PATH NFT",
#   "symbol": "PATH",
#   "baseUri": "",
#   # Set exactly one of openTime or startDelaySec.
#   "startDelaySec": "600",
#   "k": "600",
#   "genesisPrice": "1000",
#   "genesisFloor": "900",
#   "pts": "1",
#   "firstPublicId": "1",
#   "epochBase": "1",
#   "reservedCap": "3",
#   "paymentToken": "0x0000000000000000000000000000000000000000",
#   "treasury": "0xYourTreasuryAddress"
# }
chmod 600 ~/.opsec/path/params/params.sepolia.deploy.json

$EDITOR ~/.opsec/path/handoff/path-handoff.signing-runtime.sepolia.env
# Keep this file outside the repo. It is the private runtime handoff file.
# Contents:
# SEPOLIA_RPC_URL=https://<your-sepolia-rpc>
chmod 600 ~/.opsec/path/handoff/path-handoff.signing-runtime.sepolia.env

set -a
source ~/.opsec/path/handoff/path-handoff.signing-runtime.sepolia.env
set +a

CHECK_GH_AUTH=1 NETWORK=sepolia LANE=deploy npm run ops:preflight:devos

RUN_ID=sepolia-deploy-$(date -u +%Y%m%dT%H%M%SZ)
PARAMS_FILE=~/.opsec/path/params/params.sepolia.deploy.json
cat > ~/.opsec/path/handoff/path-handoff.sepolia.public.env <<EOF
NETWORK=sepolia
RUN_ID=$RUN_ID
EOF
chmod 600 ~/.opsec/path/handoff/path-handoff.sepolia.public.env
NETWORK=sepolia LANE=deploy RUN_ID=$RUN_ID INPUT_FILE=$PARAMS_FILE INPUT_KIND=constructor_params PARAMS_SCHEMA=schemas/path.constructor_params.schema.json npm run ops:lock-inputs
NETWORK=sepolia LANE=deploy RUN_ID=$RUN_ID npm run ops:dispatch-bundle
cp ~/.opsec/path/handoff/path-handoff.sepolia.public.env /Volumes/<USB>/
cp ~/.opsec/path/handoff/path-handoff.signing-runtime.sepolia.env /Volumes/<USB>/
sync
unset SEPOLIA_RPC_URL
```

## C) Handoff note

Prepare two handoff files under `~/.opsec/path/handoff`.

Public handoff file:

```text
~/.opsec/path/handoff/path-handoff.sepolia.public.env
```

```text
NETWORK=sepolia
RUN_ID=<bundle-run-id>
```

Private runtime handoff file:

```text
~/.opsec/path/handoff/path-handoff.signing-runtime.sepolia.env
```

Contents:

```text
SEPOLIA_RPC_URL=https://<your-sepolia-rpc>
```

For every stage, copy both handoff files to removable media:

```text
/Volumes/<USB>/path-handoff.sepolia.public.env
/Volumes/<USB>/path-handoff.signing-runtime.sepolia.env
```

Rules:
- keep the public handoff file in `~/.opsec/path/handoff/`, not in the repo
- keep the private runtime handoff file out of the repo
- do not put the RPC URL in the public handoff note
- remove both handoff files from removable media after the Signing OS env is created and the public handoff file has been sourced for the run

Next step:
- stop using this Sepolia runbook for execution
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

For a serious stage-1, stage-2, or stage-3 Sepolia rehearsal, the selected stage runbook only counts as passed if:
- `postconditions.json` status is `pass`
- `audit_verify.json` status is `pass`
- `audit_report.json` status is `pass`
- `audit_signoff.json` exists

## E) Capture deployment outputs
- confirm `bundles/sepolia/$RUN_ID/deployments/sepolia-eth.json` exists
- copy promoted deployment metadata to your chosen publishing target if needed

## F) Failure handling
- if verify fails due policy/check mismatch: fix policy or deployment inputs, then create a new `RUN_ID`
- if commit changes after bundle: rerun bundle/verify/approve with a new `RUN_ID`
- if audit fails or is incomplete: do not count the rehearsal as passed; inspect the audit outputs, fix the process on Dev OS, and rerun with a fresh `RUN_ID` when needed
- if the Signing OS runbook proves insufficient during execution: stop the Signing OS run, fix the repo on Dev OS, push, and restart with a fresh run
