# Signing OS runbook

This runbook is the serious Sepolia/Mainnet operator path.

Use it when:
- the bundle is built remotely in CI
- signing happens on a separate machine
- you want Sepolia rehearsal to mirror mainnet shape as closely as possible

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
- fetch bundle artifact
- checkout the exact commit pinned in `run.json`
- `ops:verify`
- `ops:approve`
- `ops:apply`
- `ops:postconditions`

Never do serious Sepolia/Mainnet `apply` from the Dev OS.

## B) Signing OS prerequisites

Install and local setup:
- repo clone exists locally
- `node`, `npm`, `git`, `gh` available
- `gh auth status` succeeds for the repo
- `npm --prefix evm ci` has been run at least once on the machine

Local-only operator materials:
- network env file outside repo:
  - `~/.opsec/path/sepolia.env`
  - `~/.opsec/path/mainnet.env`
- keystore path is local-only
- password file or password env is local-only
- no raw `*_PRIVATE_KEY` export for Sepolia/Mainnet

Required local env shape:
- Sepolia:
  - `SEPOLIA_RPC_URL`
  - `SEPOLIA_DEPLOY_KEYSTORE_JSON`
  - one of:
    - `SEPOLIA_DEPLOY_KEYSTORE_PASSWORD`
    - `SEPOLIA_DEPLOY_KEYSTORE_PASSWORD_FILE`
- Mainnet:
  - `MAINNET_RPC_URL`
  - `MAINNET_DEPLOY_KEYSTORE_JSON`
  - one of:
    - `MAINNET_DEPLOY_KEYSTORE_PASSWORD`
    - `MAINNET_DEPLOY_KEYSTORE_PASSWORD_FILE`

## C) What you carry from Dev OS to Signing OS

Carry only these identifiers:
- `NETWORK`
- `RUN_ID`
- GitHub workflow run id (`RUN_DB_ID`)
- for mainnet only, rehearsal proof run id if required:
  - `REHEARSAL_PROOF_RUN_ID`

Do not carry:
- private keys
- mnemonic/seed
- CI secrets
- ad hoc calldata or handwritten addresses

## D) Signing OS bootstrap

Run from repo root:

```bash
cd /Users/bigu/Projects/path
git fetch origin
git checkout main
git pull origin main
```

Install deps if the machine is fresh:

```bash
npm --prefix evm ci
```

Check tracked tree cleanliness before local CD:

```bash
git diff --quiet && git diff --cached --quiet || { echo "tracked tree is dirty"; exit 1; }
```

## E) Fetch bundle on Signing OS

Use the CI run id from the Dev OS / GitHub Actions page:

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

## F) Checkout the exact pinned commit

Do not assume latest `main` is correct.

Read the bundle-pinned commit and switch to it:

```bash
RUN_ID=<run-id-from-run.json-or-dev-os>
BUNDLE_SHA=$(jq -r .git_commit "bundles/$NETWORK/$RUN_ID/run.json")
git fetch origin
git checkout "$BUNDLE_SHA"
```

Then recheck tracked cleanliness:

```bash
git diff --quiet && git diff --cached --quiet || { echo "tracked tree is dirty"; exit 1; }
```

Why:
- `ops:verify` requires `run.json.git_commit == HEAD`
- `ops:apply` refuses dirty tracked state

## G) Load operator env on Signing OS

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

## H) Local CD on Signing OS

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

## I) Mainnet-specific gate

Current mainnet deploy policy requires rehearsal proof.

Operational meaning:
- serious mainnet `apply` needs:
  - a valid mainnet bundle
  - local keystore on Signing OS
  - `REHEARSAL_PROOF_RUN_ID` set to an accepted rehearsal bundle id

## J) Agent usage on Signing OS

Using the agent on the Signing OS is acceptable if:
- the agent works in the local repo checkout only
- keystore/password stay local to the machine
- you do not paste secrets into chat
- you do not ask it to expose secret values

Good prompts on Signing OS:
- "fetch the bundle for run id X and verify it"
- "show me the pinned commit in run.json and switch to it"
- "run ops:verify and summarize the failing check"
- "run ops:apply and summarize the deployment output"

Bad prompts:
- anything asking to print private keys
- anything asking to rewrite env files with secret literals in the repo

## K) Failure rules

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
- future runs must use a fresh `RUN_ID`
- do not claim the old bundle matches the new commit

## L) Minimal serious sequence

Dev OS:

```bash
NETWORK=<net> LANE=deploy RUN_ID=$RUN_ID \
INPUT_FILE=~/.opsec/path/params.<net>.deploy.json \
INPUT_KIND=constructor_params \
PARAMS_SCHEMA=schemas/path.constructor_params.schema.json \
npm run ops:lock-inputs

NETWORK=<net> LANE=deploy RUN_ID=$RUN_ID npm run ops:dispatch-bundle
```

Signing OS:

```bash
NETWORK=<net> RUN_DB_ID=<gh-run-id> npm run ops:fetch-bundle
BUNDLE_SHA=$(jq -r .git_commit "bundles/$NETWORK/$RUN_ID/run.json")
git checkout "$BUNDLE_SHA"
NETWORK=<net> RUN_ID=$RUN_ID npm run ops:verify
NETWORK=<net> RUN_ID=$RUN_ID npm run ops:approve
SIGNING_OS=1 NETWORK=<net> RUN_ID=$RUN_ID npm run ops:apply
NETWORK=<net> RUN_ID=$RUN_ID npm run ops:postconditions
```
