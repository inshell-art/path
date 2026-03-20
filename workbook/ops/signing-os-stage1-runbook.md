# Signing OS Stage 1 runbook

This is the self-contained Signing OS handbook for Stage 1.
Use this file alone for the Signing OS half when you are doing the Stage 1 rehearsal.

Stage 1 means:
- same macOS account
- separate signer workspace
- separate local-only secrets root
- procedure rehearsal first, not final authority-shape proof

Use Stage 1 when:
- you want to prove the full Dev OS -> CI -> Signing OS -> audit flow quickly
- you want a separate checkout and separate secrets root before moving to stronger isolation
- temporary EOA treasury/admin is still acceptable for this rehearsal

Do not present Stage 1 as proof of:
- final Safe treasury custody
- final Admin Safe handoff shape
- final production signer topology

## A) Stage-1 path model

Use these paths for Stage 1:
- repo checkout: `~/Projects/SIGNING_OS/path`
- local secrets root: `~/Projects/SIGNING_OS/.opsec`
- marker file: `~/Projects/SIGNING_OS/.opsec/path/signing_os.marker`
- env files:
  - `~/Projects/SIGNING_OS/.opsec/path/env/sepolia.env`
  - `~/Projects/SIGNING_OS/.opsec/path/env/mainnet.env`

When a generic doc shows `~/.opsec/...`, replace it with:
- `~/Projects/SIGNING_OS/.opsec/...`

## B) Trust boundary

Dev OS does:
- policy edits
- compile/test
- `ops:lock-inputs`
- `ops:dispatch-bundle`

Signing OS does:
- local-only keystore/password handling
- bundle fetch
- pinned checkout
- `ops:verify`
- `ops:approve`
- `ops:apply`
- `ops:postconditions`
- post-run audit

Never do serious Sepolia/Mainnet `apply` from Dev OS.
Never patch repo code, policy, or runbook content on Signing OS during an active run.

## C) Cold-start bootstrap on Signing OS

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

Create or update the Stage-1 checkout:

```bash
mkdir -p ~/Projects/SIGNING_OS
cd ~/Projects/SIGNING_OS
if [[ ! -d path/.git ]]; then
  git clone git@github.com:inshell-art/path.git path
fi
cd path
git fetch origin
git checkout main
git pull --ff-only origin main
```

Authenticate GitHub CLI for bundle download:

```bash
gh auth status || gh auth login
```

Install repo dependencies:

```bash
npm --prefix evm ci
```

## D) Create local-only Stage-1 storage

```bash
install -d -m 700 ~/Projects/SIGNING_OS/.opsec/path
install -d -m 700 ~/Projects/SIGNING_OS/.opsec/path/env
install -d -m 700 ~/Projects/SIGNING_OS/.opsec/path/params
install -d -m 700 ~/Projects/SIGNING_OS/.opsec/sepolia/signers/deploy_sw_a
install -d -m 700 ~/Projects/SIGNING_OS/.opsec/sepolia/password-files
install -d -m 700 ~/Projects/SIGNING_OS/.opsec/mainnet/signers/deploy_sw_a
install -d -m 700 ~/Projects/SIGNING_OS/.opsec/mainnet/password-files
touch ~/Projects/SIGNING_OS/.opsec/path/signing_os.marker
chmod 600 ~/Projects/SIGNING_OS/.opsec/path/signing_os.marker
```

These paths are outside the repo and must never be committed.

## E) Provision keystore, password file, and env

Generate or import only encrypted keystore material on Signing OS.
Never paste a raw private key into the shell.

Example encrypted keystore paths:
- `~/Projects/SIGNING_OS/.opsec/sepolia/signers/deploy_sw_a/keystore.json`
- `~/Projects/SIGNING_OS/.opsec/mainnet/signers/deploy_sw_a/keystore.json`

If generating a fresh signer locally with Foundry:

```bash
cast wallet new ~/Projects/SIGNING_OS/.opsec/sepolia/signers/deploy_sw_a keystore.json
cast wallet new ~/Projects/SIGNING_OS/.opsec/mainnet/signers/deploy_sw_a keystore.json
chmod 600 ~/Projects/SIGNING_OS/.opsec/sepolia/signers/deploy_sw_a/keystore.json
chmod 600 ~/Projects/SIGNING_OS/.opsec/mainnet/signers/deploy_sw_a/keystore.json
```

Create local password files with an editor, not a shell literal:

```bash
$EDITOR ~/Projects/SIGNING_OS/.opsec/sepolia/password-files/deploy_sw_a.password.txt
$EDITOR ~/Projects/SIGNING_OS/.opsec/mainnet/password-files/deploy_sw_a.password.txt
chmod 600 ~/Projects/SIGNING_OS/.opsec/sepolia/password-files/deploy_sw_a.password.txt
chmod 600 ~/Projects/SIGNING_OS/.opsec/mainnet/password-files/deploy_sw_a.password.txt
```

Create local env files:

```bash
$EDITOR ~/Projects/SIGNING_OS/.opsec/path/env/sepolia.env
$EDITOR ~/Projects/SIGNING_OS/.opsec/path/env/mainnet.env
chmod 600 ~/Projects/SIGNING_OS/.opsec/path/env/sepolia.env
chmod 600 ~/Projects/SIGNING_OS/.opsec/path/env/mainnet.env
```

Sepolia env shape:

```bash
SEPOLIA_RPC_URL=https://<your-sepolia-rpc>
SEPOLIA_DEPLOY_KEYSTORE_JSON=~/Projects/SIGNING_OS/.opsec/sepolia/signers/deploy_sw_a/keystore.json
SEPOLIA_DEPLOY_KEYSTORE_PASSWORD_FILE=~/Projects/SIGNING_OS/.opsec/sepolia/password-files/deploy_sw_a.password.txt
SIGNING_OS_MARKER_FILE=~/Projects/SIGNING_OS/.opsec/path/signing_os.marker
```

Mainnet env shape:

```bash
MAINNET_RPC_URL=https://<your-mainnet-rpc>
MAINNET_DEPLOY_KEYSTORE_JSON=~/Projects/SIGNING_OS/.opsec/mainnet/signers/deploy_sw_a/keystore.json
MAINNET_DEPLOY_KEYSTORE_PASSWORD_FILE=~/Projects/SIGNING_OS/.opsec/mainnet/password-files/deploy_sw_a.password.txt
SIGNING_OS_MARKER_FILE=~/Projects/SIGNING_OS/.opsec/path/signing_os.marker
```

Rules:
- no raw `SEPOLIA_PRIVATE_KEY`
- no raw `MAINNET_PRIVATE_KEY`
- password file is preferred over password env for serious operator use

Optional sanity checks:

```bash
[[ -f "$HOME/Projects/SIGNING_OS/.opsec/sepolia/signers/deploy_sw_a/keystore.json" ]] && echo "sepolia keystore ok"
[[ -f "$HOME/Projects/SIGNING_OS/.opsec/sepolia/password-files/deploy_sw_a.password.txt" ]] && echo "sepolia password file ok"
[[ -f "$HOME/Projects/SIGNING_OS/.opsec/path/env/sepolia.env" ]] && echo "sepolia env ok"
[[ -f "$HOME/Projects/SIGNING_OS/.opsec/path/signing_os.marker" ]] && echo "signing os marker ok"
```

## F) If the deploy signer is new or rotated

Do this before any serious Dev OS preflight or bundle creation.

1. Read the current policy-mapped deploy signer from the current checkout.

Sepolia:

```bash
jq -r '.signer_alias_map.SEPOLIA_DEPLOY_SW_A // empty' ops/policy/lane.sepolia.json
```

Mainnet:

```bash
jq -r '.signer_alias_map.MAINNET_DEPLOY_SW_A // empty' ops/policy/lane.mainnet.json
```

2. Derive the public address from the local keystore.

Sepolia:

```bash
cast wallet address \
  --keystore ~/Projects/SIGNING_OS/.opsec/sepolia/signers/deploy_sw_a/keystore.json \
  --password-file ~/Projects/SIGNING_OS/.opsec/sepolia/password-files/deploy_sw_a.password.txt
```

Mainnet:

```bash
cast wallet address \
  --keystore ~/Projects/SIGNING_OS/.opsec/mainnet/signers/deploy_sw_a/keystore.json \
  --password-file ~/Projects/SIGNING_OS/.opsec/mainnet/password-files/deploy_sw_a.password.txt
```

3. Derive it a second time and confirm the same result.

4. If the derived address differs from policy:
- stop the serious run flow
- carry only this public handoff note to Dev OS:

Sepolia:

```text
NETWORK=sepolia
ALIAS=SEPOLIA_DEPLOY_SW_A
ADDRESS=0x...
```

Mainnet:

```text
NETWORK=mainnet
ALIAS=MAINNET_DEPLOY_SW_A
ADDRESS=0x...
```

5. On Dev OS, update the policy, validate it, commit, and push.

6. Back on Signing OS, pull latest `main` before the serious run begins:

```bash
cd ~/Projects/SIGNING_OS/path
git fetch origin
git checkout main
git pull --ff-only origin main
```

Do not let Dev OS start a serious bundle flow until the intended deploy signer is reflected in pushed policy.

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

Typical Stage-1 handoff note:

```text
NETWORK=sepolia
RUN_ID=<bundle-run-id>
```

## H) Integrated Signing OS preflight

Before the first serious fetch for a network/lane, run:

Sepolia:

```bash
OPSEC_ROOT=~/Projects/SIGNING_OS/.opsec CHECK_GH_AUTH=1 NETWORK=sepolia LANE=deploy npm run ops:preflight:signingos
```

Mainnet:

```bash
OPSEC_ROOT=~/Projects/SIGNING_OS/.opsec CHECK_GH_AUTH=1 NETWORK=mainnet LANE=deploy npm run ops:preflight:signingos
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

From the Stage-1 repo root:

```bash
cd ~/Projects/SIGNING_OS/path
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

If you already have the GitHub run id:

```bash
NETWORK=<sepolia|mainnet>
RUN_DB_ID=<github-actions-run-id>
GH_REPO=inshell-art/path
npm run ops:fetch-bundle
```

## J) Checkout the exact pinned commit

```bash
BUNDLE_SHA=$(jq -r .git_commit "bundles/$NETWORK/$RUN_ID/run.json")
git fetch origin
git checkout "$BUNDLE_SHA"
git diff --quiet && git diff --cached --quiet || { echo "tracked tree is dirty"; exit 1; }
```

## K) Load local Stage-1 env

Sepolia:

```bash
set -a
source ~/Projects/SIGNING_OS/.opsec/path/env/sepolia.env
set +a
unset SEPOLIA_PRIVATE_KEY
```

Mainnet:

```bash
set -a
source ~/Projects/SIGNING_OS/.opsec/path/env/mainnet.env
set +a
unset MAINNET_PRIVATE_KEY
```

Optional sanity checks:

```bash
gh auth status
[[ -f "${SEPOLIA_DEPLOY_KEYSTORE_JSON/#\~/$HOME}" ]] && echo "keystore ok"
[[ -f "${SEPOLIA_DEPLOY_KEYSTORE_PASSWORD_FILE/#\~/$HOME}" ]] && echo "password file ok"
```

## L) Execute the Signing OS lane

Before `ops:verify`, check:
- `RUN_ID` matches the intended CI bundle
- `git rev-parse HEAD` matches `run.json.git_commit`
- tracked tree is clean
- loaded env file is the Signing OS env file
- `SIGNING_OS_MARKER_FILE` points to the Stage-1 marker file

Before `ops:approve`, check:
- bundle path is intended
- inputs summary matches intended deploy params
- signer address expected by policy is the one you intend to use

Before `ops:apply`, check:
- you are on the Stage-1 Signing OS checkout
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

Expected final shape:
- `postconditions.json`
  - `"mode": "auto"`
  - `"status": "pass"`

## M) Audit after postconditions

Do not stop at `postconditions`.
Run the post-run audit from the same repo checkout that holds the completed bundle:

```bash
AUDIT_ID=$NETWORK-audit-$(date -u +%Y%m%dT%H%M%SZ)
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID RUN_IDS=$RUN_ID npm run ops:audit:plan
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID npm run ops:audit:collect
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID npm run ops:audit:verify
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID npm run ops:audit:report
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID AUDIT_APPROVER=<name> npm run ops:audit:signoff
```

For more detail, see [audit-runbook.md](audit-runbook.md).

## N) Failure rules

If `ops:verify` says commit mismatch:
- fetch latest refs
- checkout `run.json.git_commit`
- do not keep using a different `HEAD`

If code or policy changed after CI bundle:
- do not reuse that bundle
- create a fresh `RUN_ID`
- rebuild the CI bundle

If `ops:apply` fails on-chain but code did not change:
- you may usually retry the same `RUN_ID`
- examples:
  - insufficient funds
  - temporary RPC/provider failure

If `ops:postconditions` fails because of probe logic:
- fix the probe logic on Dev OS
- push the fix
- start a fresh bundle flow if commit pin changes

If audit fails or is incomplete:
- do not count the run as passed
- inspect the audit outputs
- fix repo, policy, or runbook on Dev OS if the gap is process-related
- rerun with a fresh `RUN_ID` if run evidence must change

If any Signing OS step reveals a process or documentation gap:
- stop the run
- do not patch locally on Signing OS
- return to Dev OS
- fix the repo and push the fix
- restart from the appropriate earlier boundary with a fresh run

## O) Stage-1 pass criteria

Stage 1 only counts as passed if:
- separate signer workspace and separate secrets root were actually used
- no ad hoc fixes were made on Signing OS during execution
- `postconditions.json` is `pass`
- `audit_verify.json` is `pass`
- `audit_report.json` is `pass`
- `audit_signoff.json` exists

Stage-1 authority realism:
- temporary EOA treasury/admin is acceptable only if the run is explicitly treated as procedure rehearsal
- do not present a Stage-1 EOA treasury/admin run as proof of final Safe authority shape
