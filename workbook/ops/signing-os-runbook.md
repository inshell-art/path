# Signing OS runbook

This runbook is the serious Sepolia/Mainnet operator path.

Use it when:
- the bundle is built remotely in CI
- signing happens on a separate machine
- you want Sepolia rehearsal to mirror mainnet shape as closely as possible
- the Signing OS starts as a cold machine with no repo context loaded

For a same-machine level-2 rehearsal:
- use a second checkout, for example `/Users/bigu/Projects/SIGNING_OS/path`
- use a separate secrets root, for example `/Users/bigu/Projects/SIGNING_OS/.opsec`
- replace `~/.opsec/...` below with that alternate root

## A) Trust boundary

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

## B) Cold-start bootstrap on Signing OS

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

## C) Create local-only Signing OS storage

Create local-only operator directories:

```bash
install -d -m 700 ~/.opsec/path
install -d -m 700 ~/.opsec/sepolia/deploy_sw_a
install -d -m 700 ~/.opsec/mainnet/deploy_sw_a
```

These paths are outside the repo and must never be committed.

## D) Provision keystore and password with opsec discipline

Preferred rule:
- transfer or generate only encrypted keystore JSON on the Signing OS
- never paste a raw private key into the shell
- never put a raw private key in repo files, env files, shell history, or chat

Acceptable ways to get the keystore onto the Signing OS:
- transfer an encrypted keystore file from a trusted wallet/tool
- generate/import the wallet using a local wallet UI/tool that writes encrypted keystore locally

Do not use this runbook to move raw private keys around.

Place the encrypted keystore under the local-only directory, for example:

```bash
~/.opsec/sepolia/deploy_sw_a/keystore.json
~/.opsec/mainnet/deploy_sw_a/keystore.json
```

Lock permissions:

```bash
chmod 600 ~/.opsec/sepolia/deploy_sw_a/keystore.json
chmod 600 ~/.opsec/mainnet/deploy_sw_a/keystore.json
```

Create the password file locally on the Signing OS using an editor, not a shell literal:

```bash
$EDITOR ~/.opsec/sepolia/deploy_sw_a/password.txt
$EDITOR ~/.opsec/mainnet/deploy_sw_a/password.txt
chmod 600 ~/.opsec/sepolia/deploy_sw_a/password.txt
chmod 600 ~/.opsec/mainnet/deploy_sw_a/password.txt
```

Why:
- avoids storing secrets in shell history
- avoids echoing secrets in terminal logs
- matches `apply_bundle.sh` keystore mode

## E) Create Signing OS env files

Create local-only network env files:

```bash
$EDITOR ~/.opsec/path/sepolia.env
$EDITOR ~/.opsec/path/mainnet.env
chmod 600 ~/.opsec/path/sepolia.env
chmod 600 ~/.opsec/path/mainnet.env
```

Sepolia env shape:

```bash
SEPOLIA_RPC_URL=https://<your-sepolia-rpc>
SEPOLIA_DEPLOY_KEYSTORE_JSON=~/.opsec/sepolia/deploy_sw_a/keystore.json
SEPOLIA_DEPLOY_KEYSTORE_PASSWORD_FILE=~/.opsec/sepolia/deploy_sw_a/password.txt
```

Mainnet env shape:

```bash
MAINNET_RPC_URL=https://<your-mainnet-rpc>
MAINNET_DEPLOY_KEYSTORE_JSON=~/.opsec/mainnet/deploy_sw_a/keystore.json
MAINNET_DEPLOY_KEYSTORE_PASSWORD_FILE=~/.opsec/mainnet/deploy_sw_a/password.txt
```

Rules:
- no raw `SEPOLIA_PRIVATE_KEY`
- no raw `MAINNET_PRIVATE_KEY`
- password file is preferred over password env for a serious operator machine

Optional local sanity checks:

```bash
[[ -f "${HOME}/.opsec/sepolia/deploy_sw_a/keystore.json" ]] && echo "sepolia keystore ok"
[[ -f "${HOME}/.opsec/sepolia/deploy_sw_a/password.txt" ]] && echo "sepolia password file ok"
[[ -f "${HOME}/.opsec/mainnet/deploy_sw_a/keystore.json" ]] && echo "mainnet keystore ok"
[[ -f "${HOME}/.opsec/mainnet/deploy_sw_a/password.txt" ]] && echo "mainnet password file ok"
```

## F) Start Codex on the Signing OS

Starting Codex on the Signing OS is acceptable if:
- it operates in the local repo checkout only
- keystore/password stay local to the machine
- you do not paste secrets into chat
- you do not ask it to print secret values
- you keep the agent in a guide-and-review role for sensitive steps

Good first prompt on the Signing OS:

```text
Read workbook/ops/signing-os-runbook.md and guide me through the Signing OS half for NETWORK=sepolia and RUN_DB_ID=<github-actions-run-id>. Do not print secrets.
```

Good prompts later:
- `fetch the bundle for run id X and verify it`
- `show me the pinned commit in run.json and switch to it`
- `run ops:verify and summarize the failing check`
- `run ops:apply and summarize the deployment output`

Bad prompts:
- anything asking to print private keys
- anything asking to rewrite env files with secret literals in the repo

## G) Operator-controlled mode on Signing OS

Use Codex as a local guide, not as an unreviewed signer.

Recommended control model:
- Codex may read repo state, bundle files, and runbooks
- Codex may prepare exact commands and summarize outputs
- Codex may run non-sensitive read steps
- you inspect and approve each sensitive step before it runs

Sensitive steps that deserve explicit operator review:
- creating or editing local env files
- placing keystore/password files
- sourcing the network env file
- running `ops:approve`
- running `ops:apply`
- accepting final `postconditions` as sufficient evidence

For each sensitive step, require Codex to give:
- the exact command
- what file(s) it will read
- what file(s) it will write
- what success should look like
- what would make it unsafe or wrong

Good interaction pattern:
1. ask Codex to inspect and summarize
2. read the proposed command yourself
3. run or approve the command
4. ask Codex to interpret the output

Example prompt pattern:

```text
Guide me step by step from the Signing OS runbook. For each sensitive step, stop and show:
1. exact command
2. files read/written
3. what I should check before continuing
Do not print secrets.
```

## H) What you carry from Dev OS to Signing OS

Carry only these identifiers:
- `NETWORK`
- `RUN_DB_ID`
- optionally `RUN_ID`
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
RUN_DB_ID=<github-actions-run-id>
GH_REPO=inshell-art/path
npm run ops:fetch-bundle
```

The helper derives the bundle run id from `run.json` and installs the artifact under:

```bash
bundles/<network>/<run_id>/
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
source ~/.opsec/path/sepolia.env
set +a
unset SEPOLIA_PRIVATE_KEY
```

Mainnet:

```bash
set -a
source ~/.opsec/path/mainnet.env
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

Sepolia:

```bash
NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:verify
NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:approve
SIGNING_OS=1 NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:apply
NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:postconditions
jq '{mode,status,checks}' "bundles/sepolia/$RUN_ID/postconditions.json"
```

Mainnet:

```bash
NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:verify
NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:approve
SIGNING_OS=1 REHEARSAL_PROOF_RUN_ID=<proof_run_id> NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:apply
NETWORK=mainnet RUN_ID=$RUN_ID npm run ops:postconditions
jq '{mode,status,checks}' "bundles/mainnet/$RUN_ID/postconditions.json"
```

Expected final shape:
- `postconditions.json`
  - `"mode": "auto"`
  - `"status": "pass"`

## M) Mainnet-specific gate

Current mainnet deploy policy requires rehearsal proof.

Operational meaning:
- serious mainnet `apply` needs:
  - a valid mainnet bundle
  - local keystore on Signing OS
  - `REHEARSAL_PROOF_RUN_ID` set to an accepted rehearsal bundle id

## N) Failure rules

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

## O) Minimal serious sequence

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
