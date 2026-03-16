# Signing OS runbook

This runbook is the serious Sepolia/Mainnet operator path.
It is written to work for a human operator without any agent help.
That is the target operating model.

Use it when:
- the bundle is built remotely in CI
- signing happens on a separate machine
- you want Sepolia rehearsal to mirror mainnet shape as closely as possible
- the Signing OS starts as a cold machine with no repo context loaded

Target rule:
- operate the Signing OS from this runbook alone
- do not depend on an agent on the Signing OS
- if the Signing OS run blocks, stop there
- bring the failure back to Dev OS
- fix repo code, policy, or docs on Dev OS
- commit and push the fix
- start a fresh run only after the fix is published

For a same-machine stage-1 rehearsal:
- use a second checkout, for example `~/Projects/SIGNING_OS/path`
- use a separate secrets root, for example `~/Projects/SIGNING_OS/.opsec`
- replace `~/.opsec/...` below with that alternate root

## A) Rehearsal ladder

Use this order and do not skip ahead:

1. Stage 1: dedicated signer workspace on the same macOS account
- repo example: `~/Projects/SIGNING_OS/path`
- secrets example: `~/Projects/SIGNING_OS/.opsec`
- goal: prove the process split with a separate checkout and separate secrets root

2. Stage 2: separate local macOS account on the same machine
- use a different macOS user account
- use that account's own `~/Projects/path` and `~/.opsec`
- goal: prove home-directory and shell-history separation

3. Stage 3: real Signing OS machine
- separate machine
- separate home directory
- separate local-only secrets storage
- goal: match mainnet operating shape

Progression rule:
- do not move to the next stage until the previous stage completes a full Sepolia deploy run, then a post-run audit pass/signoff, with the current runbook and no ad hoc fixes during execution
- do not count agent intervention on the Signing OS as a passing run

## B) Stage 2: separate local macOS account

This stage proves the process split with a separate home directory and separate shell history on the same machine.

Recommended account model:
- create a dedicated local macOS user for Signing OS work
- prefer a Standard account for routine use
- use an administrator account only to install tools or change machine settings

Create the account from macOS Settings:
1. open `System Settings -> Users & Groups`
2. add a new local user
3. choose a distinct account name for Signing OS work
4. do not reuse the normal development account

After creating it:
1. log out of the development account
2. log into the new Signing OS account
3. open a fresh Terminal session
4. treat that account's home directory as the only valid Signing OS home

Stage-2 filesystem expectations:
- repo checkout: `~/Projects/path`
- local secrets root: `~/.opsec`
- no references back to the development account home directory

Stage-2 first-login checklist:
- `pwd` starts under the new account home
- `echo $HOME` is the new account home
- `ls ~/Projects` does not rely on the old account's checkout
- `ls ~/.opsec` does not rely on the old account's secrets

Once those checks hold, use the rest of this runbook exactly as written.
Do not special-case stage 2 after account creation.

## C) Trust boundary

Dev OS does:
- code and policy edits
- `npm run evm:compile`
- `npm run evm:test`
- `npm run ops:lock-inputs`
- `npm run ops:dispatch-bundle`

Remote CI does:
- checkout pinned commit
- build bundle artifact only
- no signing
- no keystore
- no password material

Signing OS does:
- clone/update the repo locally
- keep keystore/password material local-only
- fetch bundle artifact
- checkout the exact commit pinned in `run.json`
- `ops:verify`
- `ops:approve`
- `ops:apply`
- `ops:postconditions`

Never do serious Sepolia/Mainnet `apply` from the Dev OS.
Never patch repo code, policy, or runbook content on the Signing OS during an active run.

## D) Cold-start bootstrap on Signing OS

Install required tools using the machine's package manager:
- `node`
- `npm`
- `git`
- `gh`

Verify they are present:

```bash
node --version
npm --version
git --version
gh --version
```

Clone the repo:

```bash
mkdir -p ~/Projects
cd ~/Projects
git clone git@github.com:inshell-art/path.git
cd path
git checkout main
git pull origin main
```

Authenticate GitHub CLI for bundle download:

```bash
gh auth status || gh auth login
```

Install repo dependencies:

```bash
npm --prefix evm ci
```

Operator rule on the Signing OS:
- follow the runbook only
- do not improvise alternate commands during an active run
- do not invent a local workaround on the Signing OS
- if a step fails, capture the error and return to Dev OS for any fix

## E) Create local-only Signing OS storage

Create local-only operator directories:

```bash
install -d -m 700 ~/.opsec/path
install -d -m 700 ~/.opsec/path/env
install -d -m 700 ~/.opsec/path/params
install -d -m 700 ~/.opsec/sepolia/signers/deploy_sw_a
install -d -m 700 ~/.opsec/sepolia/password-files
install -d -m 700 ~/.opsec/mainnet/signers/deploy_sw_a
install -d -m 700 ~/.opsec/mainnet/password-files
touch ~/.opsec/path/signing_os.marker
chmod 600 ~/.opsec/path/signing_os.marker
```

These paths are outside the repo and must never be committed.
The marker file is the local machine-role gate for Sepolia/Mainnet deploy-side ops.

## F) Provision keystore and password with opsec discipline

Preferred rule:
- transfer or generate only encrypted keystore JSON on the Signing OS
- never paste a raw private key into the shell
- never put a raw private key in repo files, env files, shell history, or chat

Acceptable ways to get the keystore onto the Signing OS:
- transfer an encrypted keystore file from a trusted wallet/tool
- generate/import the wallet using a local wallet UI/tool that writes encrypted keystore locally

Do not use this runbook to move raw private keys around.

If you want to generate a fresh encrypted keystore directly on the Signing OS with Foundry, use `cast wallet new` and let it prompt for the keystore password locally:

```bash
cast wallet new ~/.opsec/sepolia/signers/deploy_sw_a keystore.json
cast wallet new ~/.opsec/mainnet/signers/deploy_sw_a keystore.json
```

This writes encrypted keystore files at:

```bash
~/.opsec/sepolia/signers/deploy_sw_a/keystore.json
~/.opsec/mainnet/signers/deploy_sw_a/keystore.json
```

Rules for the Foundry path:
- use the default hidden password prompt on the Signing OS
- do not use `--unsafe-password`
- record the resulting address and verify it matches the intended signer before funding or use
- if you need an existing deploy identity rather than a fresh one, import it through a trusted procedure that still ends with an encrypted keystore file on the Signing OS

Place the encrypted keystore under the local-only directory, for example:

```bash
~/.opsec/sepolia/signers/deploy_sw_a/keystore.json
~/.opsec/mainnet/signers/deploy_sw_a/keystore.json
```

Lock permissions:

```bash
chmod 600 ~/.opsec/sepolia/signers/deploy_sw_a/keystore.json
chmod 600 ~/.opsec/mainnet/signers/deploy_sw_a/keystore.json
```

If you need password-file mode, create the password file locally on the Signing OS using an editor, not a shell literal, and keep it separate from the keystore path:

```bash
$EDITOR ~/.opsec/sepolia/password-files/deploy_sw_a.password.txt
$EDITOR ~/.opsec/mainnet/password-files/deploy_sw_a.password.txt
chmod 600 ~/.opsec/sepolia/password-files/deploy_sw_a.password.txt
chmod 600 ~/.opsec/mainnet/password-files/deploy_sw_a.password.txt
```

Why:
- avoids storing secrets in shell history
- avoids echoing secrets in terminal logs
- keeps password files out of the keystore directory by default
- matches `apply_bundle.sh` explicit password-file mode

## G) Create Signing OS env files

Create local-only network env files:

```bash
$EDITOR ~/.opsec/path/env/sepolia.env
$EDITOR ~/.opsec/path/env/mainnet.env
chmod 600 ~/.opsec/path/env/sepolia.env
chmod 600 ~/.opsec/path/env/mainnet.env
```

Sepolia env shape:

```bash
SEPOLIA_RPC_URL=https://<your-sepolia-rpc>
SEPOLIA_DEPLOY_KEYSTORE_JSON=~/.opsec/sepolia/signers/deploy_sw_a/keystore.json
SEPOLIA_DEPLOY_KEYSTORE_PASSWORD_FILE=~/.opsec/sepolia/password-files/deploy_sw_a.password.txt
SIGNING_OS_MARKER_FILE=~/.opsec/path/signing_os.marker
```

Mainnet env shape:

```bash
MAINNET_RPC_URL=https://<your-mainnet-rpc>
MAINNET_DEPLOY_KEYSTORE_JSON=~/.opsec/mainnet/signers/deploy_sw_a/keystore.json
MAINNET_DEPLOY_KEYSTORE_PASSWORD_FILE=~/.opsec/mainnet/password-files/deploy_sw_a.password.txt
SIGNING_OS_MARKER_FILE=~/.opsec/path/signing_os.marker
```

Rules:
- no raw `SEPOLIA_PRIVATE_KEY`
- no raw `MAINNET_PRIVATE_KEY`
- password file is preferred over password env for a serious operator machine

Optional local sanity checks:

```bash
[[ -f "${HOME}/.opsec/sepolia/signers/deploy_sw_a/keystore.json" ]] && echo "sepolia keystore ok"
[[ -f "${HOME}/.opsec/sepolia/password-files/deploy_sw_a.password.txt" ]] && echo "sepolia password file ok"
[[ -f "${HOME}/.opsec/mainnet/signers/deploy_sw_a/keystore.json" ]] && echo "mainnet keystore ok"
[[ -f "${HOME}/.opsec/mainnet/password-files/deploy_sw_a.password.txt" ]] && echo "mainnet password file ok"
[[ -f "${HOME}/.opsec/path/env/sepolia.env" ]] && echo "sepolia env ok"
[[ -f "${HOME}/.opsec/path/env/mainnet.env" ]] && echo "mainnet env ok"
[[ -f "${HOME}/.opsec/path/signing_os.marker" ]] && echo "signing os marker ok"
```

## H) What you carry from Dev OS to Signing OS

Carry only these identifiers:
- `NETWORK`
- `RUN_ID`
- optionally `RUN_DB_ID`
- for mainnet only, rehearsal proof run id if required:
  - `REHEARSAL_PROOF_RUN_ID`

Do not carry:
- private keys
- mnemonic/seed
- CI secrets
- ad hoc calldata or handwritten addresses

## I) Fetch bundle on Signing OS

From the Signing OS repo root:

```bash
cd ~/Projects/path
git fetch origin
git checkout main
git pull origin main
git diff --quiet && git diff --cached --quiet || { echo "tracked tree is dirty"; exit 1; }
```

Fetch the CI bundle:

```bash
NETWORK=<sepolia|mainnet>
RUN_ID=<bundle-run-id>
GH_REPO=inshell-art/path
npm run ops:fetch-bundle
```

Preferred handoff is `NETWORK + RUN_ID` only.
The helper resolves the matching GitHub Actions run from exact artifact name `ops-bundle-<network>-<run_id>`, then installs the artifact under:

```bash
bundles/<network>/<run_id>/
```

If you already have the GitHub run id, this also works:

```bash
NETWORK=<sepolia|mainnet>
RUN_DB_ID=<github-actions-run-id>
GH_REPO=inshell-art/path
npm run ops:fetch-bundle
```

Set `RUN_ID` explicitly from the fetched bundle before continuing:

```bash
RUN_ID=$(find "bundles/$NETWORK" -maxdepth 2 -name run.json -print | sort | tail -n 1 | xargs jq -r .run_id)
echo "$RUN_ID"
```

If you want an explicit cross-check:

```bash
find "bundles/$NETWORK" -maxdepth 2 -name run.json | sort
```

## J) Checkout the exact pinned commit

Do not assume latest `main` is correct.

Read the bundle-pinned commit and switch to it:

```bash
BUNDLE_SHA=$(jq -r .git_commit "bundles/$NETWORK/$RUN_ID/run.json")
git fetch origin
git checkout "$BUNDLE_SHA"
git diff --quiet && git diff --cached --quiet || { echo "tracked tree is dirty"; exit 1; }
```

Why:
- `ops:verify` requires `run.json.git_commit == HEAD`
- `ops:apply` refuses dirty tracked state

## K) Load local Signing OS env

Sepolia:

```bash
set -a
source ~/.opsec/path/env/sepolia.env
set +a
unset SEPOLIA_PRIVATE_KEY
```

Mainnet:

```bash
set -a
source ~/.opsec/path/env/mainnet.env
set +a
unset MAINNET_PRIVATE_KEY
```

Optional sanity checks:

```bash
gh auth status
```

```bash
[[ -f "${SEPOLIA_DEPLOY_KEYSTORE_JSON/#\~/$HOME}" ]] && echo "keystore ok"
[[ -f "${SEPOLIA_DEPLOY_KEYSTORE_PASSWORD_FILE/#\~/$HOME}" ]] && echo "password file ok"
```

Adapt variable names for mainnet as needed.

## L) Local CD on Signing OS

Before `ops:verify`, check:
- `RUN_ID` matches the intended CI bundle
- `git rev-parse HEAD` matches `run.json.git_commit` after checkout
- tracked tree is clean
- the loaded env file is the Signing OS env file, not the Dev OS env file
- `SIGNING_OS_MARKER_FILE` points to the local marker file

Before `ops:approve`, check:
- bundle path is the intended one
- inputs summary matches intended deploy params
- signer address expected by policy is the one you intend to use

Before `ops:apply`, check:
- you are on the Signing OS checkout
- `SIGNING_OS=1` is present
- the keystore path and password file are local-only
- you understand the network and `RUN_ID`
- you are satisfied with the approval and bundle pin

Before accepting `postconditions`, check:
- `postconditions.json` exists under the expected bundle directory
- `mode` is `auto` unless you intentionally used manual mode
- `status` is `pass`
- deployment output files exist where expected

Before accepting the run as a passed rehearsal or release record, check:
- the completed run has a fresh `AUDIT_ID`
- `audit_verify.json` status is `pass`
- `audit_report.json` status is `pass`
- `audit_signoff.json` exists

Sepolia:

```bash
SIGNING_OS=1 NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:verify
SIGNING_OS=1 NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:approve
SIGNING_OS=1 NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:apply
SIGNING_OS=1 NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:postconditions
jq '{mode,status,checks}' "bundles/sepolia/$RUN_ID/postconditions.json"
```

Mainnet:

```bash
SIGNING_OS=1 NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:verify
SIGNING_OS=1 NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:approve
SIGNING_OS=1 REHEARSAL_PROOF_RUN_ID=<proof_run_id> NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:apply
SIGNING_OS=1 NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:postconditions
jq '{mode,status,checks}' "bundles/mainnet/$RUN_ID/postconditions.json"
```

Expected final shape:
- `postconditions.json`
  - `"mode": "auto"`
  - `"status": "pass"`

## M) Audit after postconditions

Audit is not part of the authority path for `verify`, `approve`, `apply`, or `postconditions`.
It is the read-only review layer for accepting the completed run as valid rehearsal or release evidence.

Run audit from the same repo checkout that holds the completed bundle:

```bash
AUDIT_ID=$NETWORK-audit-$(date -u +%Y%m%dT%H%M%SZ)
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID RUN_IDS=$RUN_ID npm run ops:audit:plan
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID npm run ops:audit:collect
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID npm run ops:audit:verify
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID npm run ops:audit:report
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID AUDIT_APPROVER=<name> npm run ops:audit:signoff
```

Use `workbook/ops/audit-runbook.md` as the detailed audit procedure.

Stage completion rule:
- for stage 1 and stage 2 Sepolia rehearsals, do not mark the stage passed until:
  - `postconditions.json` is `pass`
  - `audit_verify.json` is `pass`
  - `audit_report.json` is `pass`
  - `audit_signoff.json` is written

For mainnet:
- treat audit the same way
- the deployment is already on-chain after `apply`
- audit does not undo the run
- audit decides whether the completed run is accepted as valid release evidence

## N) Mainnet-specific gate

Current mainnet deploy policy requires rehearsal proof.

Operational meaning:
- serious mainnet `apply` needs:
  - a valid mainnet bundle
  - local keystore on Signing OS
  - `REHEARSAL_PROOF_RUN_ID` set to an accepted rehearsal bundle id

## O) Failure rules

If `ops:verify` says commit mismatch:
- fetch latest refs
- checkout `run.json.git_commit`
- do not keep using a different `HEAD`

If code or policy changed after CI bundle:
- do not reuse that bundle
- create a fresh `RUN_ID`
- rebuild remote CI bundle

If `ops:apply` fails on-chain but code did not change:
- you may usually retry the same `RUN_ID`
- examples:
  - insufficient funds
  - temporary RPC/provider failure

If `ops:postconditions` fails because of probe logic:
- fix the probe logic
- commit the fix
- start a fresh bundle flow if commit pin changes

If audit fails or is incomplete:
- do not count the run as passed rehearsal or accepted release evidence
- inspect `audit_verify.json` and `audit_report.json`
- fix the repo, policy, or runbook on Dev OS if the gap is process-related
- rerun with a fresh `RUN_ID` if the generated run evidence must change

If any Signing OS step reveals a process or documentation gap:
- stop the run
- do not patch locally on the Signing OS
- return to Dev OS
- fix the repo and push the fix
- restart from the appropriate earlier boundary with a fresh run when needed

## P) Minimal serious sequence

This is the shortest serious operator flow:

1. Dev OS:
- compile/test
- lock inputs
- dispatch CI bundle

2. Signing OS:
- clone repo
- create local-only `.opsec`
- place encrypted keystore and local password file
- create network env file
- fetch CI bundle
- checkout `run.json.git_commit`
- verify
- approve
- apply
- postconditions
- audit
- signoff

## Q) Optional Codex assistance

This runbook does not require Codex.
Codex is not part of the target Signing OS process.

If you do use Codex on the Signing OS:
- keep it in the local repo checkout only
- do not paste secrets into chat
- do not ask it to print secret values
- keep it in a guide-and-review role for sensitive steps

Preferred rule:
- for stage 2 and stage 3, do not use Codex on the Signing OS
- if the runbook is insufficient, treat that as a Dev OS documentation/process bug
- fix it on Dev OS, push, and retry

Good first prompt:

```text
Read workbook/ops/signing-os-runbook.md and guide me through the Signing OS half for NETWORK=sepolia and RUN_ID=<bundle-run-id>. Do not print secrets.
```

Good prompts later:
- `fetch the bundle for run id X and verify it`
- `show me the pinned commit in run.json and switch to it`
- `run ops:verify and summarize the failing check`
- `run ops:apply and summarize the deployment output`

Bad prompts:
- anything asking to print private keys
- anything asking to rewrite env files with secret literals in the repo

Sensitive steps that still deserve explicit operator review:
- creating or editing local env files
- placing keystore/password files
- sourcing the network env file
- setting `SIGNING_OS=1`
- running `ops:approve`
- running `ops:apply`
- accepting final audit signoff as sufficient evidence
