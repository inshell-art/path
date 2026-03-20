# Signing OS Stage 2 runbook

This is the self-contained Signing OS handbook for Stage 2.
Use this file alone for the Signing OS half when you are doing the Stage 2 rehearsal.

Stage 2 means:
- separate local macOS account on the same machine
- separate home directory and shell history
- authority-shape rehearsal

Use Stage 2 when:
- Stage 1 has already passed
- you want Sepolia to reflect the intended treasury/admin target shape more closely
- you want the Signing OS boundary to include a separate macOS home and shell history

## A) Stage-2 path model

Use the Signing OS account's own paths:
- repo checkout: `~/Projects/path`
- local secrets root: `~/.opsec`
- marker file: `~/.opsec/path/signing_os.marker`
- env files:
  - `~/.opsec/path/env/sepolia.env`
  - `~/.opsec/path/env/mainnet.env`

Do not reference:
- the Dev OS home directory
- the Stage-1 workspace under `~/Projects/SIGNING_OS`

## B) Trust boundary

Dev OS does:
- policy edits
- compile/test
- `ops:lock-inputs`
- `ops:dispatch-bundle`

Signing OS does:
- local-only keystore/password handling in the dedicated Signing OS account
- bundle fetch
- pinned checkout
- `ops:verify`
- `ops:approve`
- `ops:apply`
- `ops:postconditions`
- post-run audit

Never do serious Sepolia/Mainnet `apply` from Dev OS.
Never patch repo code, policy, or runbook content on Signing OS during an active run.

## C) Stage-2 account setup

Create and use a dedicated local macOS Signing OS account:
1. open `System Settings -> Users & Groups`
2. add a new local user
3. choose a distinct account name for Signing OS work
4. do not reuse the normal development account

After logging into the new account, verify:
- `pwd` starts under the new account home
- `echo $HOME` is the new account home
- `ls ~/Projects` does not rely on the old account's checkout
- `ls ~/.opsec` does not rely on the old account's secrets

Install required tools:

```bash
node --version
npm --version
git --version
gh --version
jq --version
python3 --version
make --version
cast --version
```

Create or update the Signing OS checkout in the new account:

```bash
mkdir -p ~/Projects
cd ~/Projects
if [[ ! -d path/.git ]]; then
  git clone git@github.com:inshell-art/path.git path
fi
cd path
git fetch origin
git checkout main
git pull --ff-only origin main
```

Authenticate GitHub CLI:

```bash
gh auth status || gh auth login
```

Install repo dependencies:

```bash
npm --prefix evm ci
```

## D) Create local-only Stage-2 storage

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

## E) Provision keystore, password file, and env

Generate or import only encrypted keystore material on Signing OS.
Never paste a raw private key into the shell.

If generating a fresh signer locally with Foundry:

```bash
cast wallet new ~/.opsec/sepolia/signers/deploy_sw_a keystore.json
cast wallet new ~/.opsec/mainnet/signers/deploy_sw_a keystore.json
chmod 600 ~/.opsec/sepolia/signers/deploy_sw_a/keystore.json
chmod 600 ~/.opsec/mainnet/signers/deploy_sw_a/keystore.json
```

Create password files locally:

```bash
$EDITOR ~/.opsec/sepolia/password-files/deploy_sw_a.password.txt
$EDITOR ~/.opsec/mainnet/password-files/deploy_sw_a.password.txt
chmod 600 ~/.opsec/sepolia/password-files/deploy_sw_a.password.txt
chmod 600 ~/.opsec/mainnet/password-files/deploy_sw_a.password.txt
```

Create local env files:

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
- password file is preferred over password env for serious operator use

## F) If the deploy signer is new or rotated

Do this before any serious Dev OS preflight or bundle creation.

Sepolia current mapping:

```bash
jq -r '.signer_alias_map.SEPOLIA_DEPLOY_SW_A // empty' ops/policy/lane.sepolia.json
```

Mainnet current mapping:

```bash
jq -r '.signer_alias_map.MAINNET_DEPLOY_SW_A // empty' ops/policy/lane.mainnet.json
```

Derive the actual address from the local keystore.

Sepolia:

```bash
cast wallet address \
  --keystore ~/.opsec/sepolia/signers/deploy_sw_a/keystore.json \
  --password-file ~/.opsec/sepolia/password-files/deploy_sw_a.password.txt
```

Mainnet:

```bash
cast wallet address \
  --keystore ~/.opsec/mainnet/signers/deploy_sw_a/keystore.json \
  --password-file ~/.opsec/mainnet/password-files/deploy_sw_a.password.txt
```

Derive it twice and confirm the same result.

If the derived address differs from policy:
- stop the serious run flow
- carry only the public handoff note to Dev OS
- wait for Dev OS to update policy, validate, commit, and push
- pull latest `main` in this account before continuing

```bash
git fetch origin
git checkout main
git pull --ff-only origin main
```

## G) What you carry from Dev OS to Signing OS

Carry only:
- `NETWORK`
- `RUN_ID`
- optionally `RUN_DB_ID`
- for Mainnet only, `REHEARSAL_PROOF_RUN_ID` if required

Do not carry:
- private keys
- mnemonic/seed
- CI secrets
- ad hoc calldata or handwritten addresses

## H) Integrated Signing OS preflight

Before the first serious fetch for a network/lane, run:

```bash
CHECK_GH_AUTH=1 NETWORK=sepolia LANE=deploy npm run ops:preflight:signingos
CHECK_GH_AUTH=1 NETWORK=mainnet LANE=deploy npm run ops:preflight:signingos
```

This preflight checks:
- required toolchain
- clean tracked git state
- policy initialization for the target lane
- Signing OS env + marker presence
- deploy keystore/password presence
- signer binding against lane policy
- optional GitHub auth for bundle fetch

## I) Fetch bundle on Signing OS

From the Stage-2 repo root:

```bash
cd ~/Projects/path
git fetch origin
git checkout main
git pull --ff-only origin main
git diff --quiet && git diff --cached --quiet || { echo "tracked tree is dirty"; exit 1; }
```

Fetch the CI bundle:

```bash
NETWORK=<sepolia|mainnet>
RUN_ID=<bundle-run-id>
GH_REPO=inshell-art/path
npm run ops:fetch-bundle
```

Or with `RUN_DB_ID` if you already have it.

## J) Checkout the exact pinned commit

```bash
BUNDLE_SHA=$(jq -r .git_commit "bundles/$NETWORK/$RUN_ID/run.json")
git fetch origin
git checkout "$BUNDLE_SHA"
git diff --quiet && git diff --cached --quiet || { echo "tracked tree is dirty"; exit 1; }
```

## K) Load local Stage-2 env

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

## L) Execute the Signing OS lane

Before `ops:verify`, check:
- `RUN_ID` matches the intended CI bundle
- `git rev-parse HEAD` matches `run.json.git_commit`
- tracked tree is clean
- loaded env file is the Signing OS env file
- `SIGNING_OS_MARKER_FILE` points to the local marker file

Before `ops:approve`, check:
- bundle path is intended
- inputs summary matches intended deploy params
- signer address expected by policy is the one you intend to use

Before `ops:apply`, check:
- you are on the Stage-2 Signing OS checkout
- `SIGNING_OS=1` is present
- the keystore path and password file are local-only
- you understand the network and `RUN_ID`

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

## M) Audit after postconditions

Run the post-run audit from the same repo checkout that holds the completed bundle:

```bash
AUDIT_ID=$NETWORK-audit-$(date -u +%Y%m%dT%H%M%SZ)
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID RUN_IDS=$RUN_ID npm run ops:audit:plan
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID npm run ops:audit:collect
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID npm run ops:audit:verify
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID npm run ops:audit:report
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID AUDIT_APPROVER=<name> npm run ops:audit:signoff
```

## N) Failure rules

If `ops:verify` says commit mismatch:
- fetch latest refs
- checkout `run.json.git_commit`

If code or policy changed after CI bundle:
- do not reuse that bundle
- create a fresh `RUN_ID`
- rebuild the CI bundle

If audit fails or is incomplete:
- do not count the run as passed
- fix the process on Dev OS
- rerun with a fresh `RUN_ID` if run evidence must change

If any Signing OS step reveals a process or documentation gap:
- stop the run
- do not patch locally on Signing OS
- return to Dev OS
- fix the repo and push the fix
- restart with a fresh run when needed

## O) Stage-2 pass criteria

Stage 2 only counts as passed if:
- a separate macOS account was actually used
- the Signing OS checkout lived under that account's own home directory
- no ad hoc fixes were made on Signing OS during execution
- `postconditions.json` is `pass`
- `audit_verify.json` is `pass`
- `audit_report.json` is `pass`
- `audit_signoff.json` exists
- treasury in deploy params was the real Sepolia Treasury Safe
- Admin Safe target was identified for handoff
- any temporary second-owner stand-in remained Sepolia-only and honestly named
