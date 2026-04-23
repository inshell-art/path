# Signing OS Stage 3 runbook

This is the self-contained Signing OS handbook for Stage 3.
Use this file alone for the Signing OS half when you are doing the Stage 3 rehearsal.

Stage 3 means:
- real separate Signing OS machine
- separate home directory
- separate local-only secrets storage
- production-shape rehearsal

Use Stage 3 when:
- Stage 2 has already passed
- you want Sepolia/Mainnet to mirror the final no-Safe custody shape as closely as possible
- you are ready to prove the real machine boundary

Canonical references for this stage:
- [Signing OS Wi-Fi handbook](signing-os-wifi-handbook.md)
- [No-Safe two-Ledger custody doc](../../docs/custody-no-safe-two-ledgers.md)

## A) Stage-3 machine model

Use a dedicated Signing OS machine with:
- repo checkout: `~/Projects/path`
- local secrets root: `~/.opsec`
- marker file: `~/.opsec/path/signing_os.marker`
- Signing OS transfer pack root: `~/Downloads/Signing-OS-Transfer-Pack`
- env files under `~/.opsec/path/env/`
- downloaded handoff files pulled during the bounded maintenance-only SSH/rsync bridge window:
  - `~/Downloads/path-handoff.sepolia.public.env`
  - `~/Downloads/path-handoff.mainnet.public.env`
  - `~/Downloads/path-handoff.signing-runtime.sepolia.env`
  - `~/Downloads/path-handoff.signing-runtime.mainnet.env`

Keep the machine role narrow:
- repo checkout
- local-only deploy keystore/password files
- bundle fetch
- verify/approve/apply/postconditions/audit

## B) Trust boundary

Dev OS does:
- policy edits
- compile/test
- `ops:lock-inputs`
- `ops:dispatch-bundle`

Signing OS does:
- local-only deploy keystore/password handling on the dedicated machine
- bundle fetch
- pinned checkout
- `ops:verify`
- `ops:approve`
- `ops:apply`
- `ops:postconditions`
- post-run audit

Never do serious Sepolia/Mainnet `apply` from Dev OS.
Never patch repo code, policy, or runbook content on Signing OS during an active run.

Final custody baseline for this stage:
- `ADMIN` must be the intended Ledger-backed contract authority address, not a Safe
- `TREASURY` must be the intended Ledger-backed recipient address, not a Safe
- the operational Ledger addresses should correspond to attached-passphrase / secondary-PIN wallets
- base / no-passphrase wallets are intentionally unused
- the deploy lane still uses the policy-approved deploy keystore alias such as `SEPOLIA_DEPLOY_SW_A` or `MAINNET_DEPLOY_SW_A`
- the Signing OS deploy keystore is deploy-only and not final ADMIN or TREASURY custody
- daily ops on the host should rely on the host password/disk unlock plus Ledger PIN path, not passphrase master copies

Bounded-online rule for this stage:
- Wi-Fi off by default
- turn Wi-Fi on only for trusted maintenance work or a bounded serious run
- serious-run online tasks are exact repo/bundle fetch, RPC checks, Ledger/RPC execution, and postconditions
- no browsing, chat, search, cloud storage, package installs, or cloud agents during the run

## C) First-time Stage-3 setup

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

Create or update the repo checkout:

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
git submodule update --init --recursive
```

Authenticate GitHub CLI in a bounded maintenance or run session:

```bash
gh auth status || gh auth login
```

Install repo dependencies:

```bash
npm --prefix evm ci
```

Before trusting `cast` with real signer material, review and complete:
- [cast-verification-discipline.md](cast-verification-discipline.md)

Create the local-only operator directories:

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

## D) Provision keystore, password file, and env

Generate or import only encrypted keystore material on Signing OS.
Never paste a raw private key into the shell.
This local keystore is the deploy signer used by the lane. It is not final ADMIN or TREASURY custody.
Final ADMIN / TREASURY actions come from the dedicated Ledger paths outside this shell flow.
If this is the first serious use of `cast` on this Signing OS, complete:
- [cast-verification-discipline.md](cast-verification-discipline.md)

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

Build local env files from the Dev OS runtime handoff file pulled to `~/Downloads/` during the bounded maintenance-only bridge window.
Do not open provider dashboards or fetch provider credentials on the Signing OS machine.

Sepolia:

```bash
set -a
source "$HOME/Downloads/path-handoff.signing-runtime.sepolia.env"
set +a
cat > ~/.opsec/path/env/sepolia.env <<EOF
SEPOLIA_RPC_URL=$SEPOLIA_RPC_URL
SEPOLIA_DEPLOY_KEYSTORE_JSON=~/.opsec/sepolia/signers/deploy_sw_a/keystore.json
SEPOLIA_DEPLOY_KEYSTORE_PASSWORD_FILE=~/.opsec/sepolia/password-files/deploy_sw_a.password.txt
SIGNING_OS_MARKER_FILE=~/.opsec/path/signing_os.marker
EOF
chmod 600 ~/.opsec/path/env/sepolia.env
unset SEPOLIA_RPC_URL
```

Mainnet:

```bash
set -a
source "$HOME/Downloads/path-handoff.signing-runtime.mainnet.env"
set +a
cat > ~/.opsec/path/env/mainnet.env <<EOF
MAINNET_RPC_URL=$MAINNET_RPC_URL
MAINNET_DEPLOY_KEYSTORE_JSON=~/.opsec/mainnet/signers/deploy_sw_a/keystore.json
MAINNET_DEPLOY_KEYSTORE_PASSWORD_FILE=~/.opsec/mainnet/password-files/deploy_sw_a.password.txt
SIGNING_OS_MARKER_FILE=~/.opsec/path/signing_os.marker
EOF
chmod 600 ~/.opsec/path/env/mainnet.env
unset MAINNET_RPC_URL
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

## E) If the deploy signer is new or rotated

Do this before any serious Dev OS preflight or bundle creation.

Read the current deploy alias mapping:

```bash
jq -r '.signer_alias_map.SEPOLIA_DEPLOY_SW_A // empty' ops/policy/lane.sepolia.json
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
- pull latest `main` before continuing

```bash
git fetch origin
git checkout main
git pull --ff-only origin main
```

## F) What you carry from Dev OS to Signing OS

Transfer to Signing OS during the bounded maintenance-only SSH/rsync bridge window from `~/Projects/signing-os-ops`:
- the full `~/Downloads/Signing-OS-Transfer-Pack/`
- public handoff files under `~/Downloads/`
  - `~/Downloads/path-handoff.sepolia.public.env`
  - `~/Downloads/path-handoff.mainnet.public.env`
- private runtime handoff files under `~/Downloads/`
  - `~/Downloads/path-handoff.signing-runtime.sepolia.env`
  - `~/Downloads/path-handoff.signing-runtime.mainnet.env`

Do not carry:
- private keys
- mnemonic/seed
- CI secrets
- ad hoc calldata or handwritten addresses
- the RPC URL in the public handoff note

Do not close the bridge window yet.
You still need the public handoff file for `NETWORK` and `RUN_ID` during bundle fetch.
Clean up the downloaded handoff files from `~/Downloads/` after those values are loaded into the shell, then close the bridge window before the serious run continues.

## G) Integrated Signing OS preflight

Before the first serious fetch for a network/lane, re-establish the Signing OS serious-run baseline from the transfer pack, then run PATH preflight:

```bash
cd ~/Downloads/Signing-OS-Transfer-Pack
./tools/signing-os-ops.sh serious-run-preflight
```

Then run:

```bash
CHECK_GH_AUTH=1 NETWORK=sepolia LANE=deploy npm run ops:preflight:signingos
CHECK_GH_AUTH=1 NETWORK=mainnet LANE=deploy npm run ops:preflight:signingos
```

## H) Fetch bundle on Signing OS

From the Stage-3 repo root:

```bash
cd ~/Projects/path
git fetch origin
git checkout main
git pull --ff-only origin main
git submodule update --init --recursive
git diff --quiet && git diff --cached --quiet || { echo "tracked tree is dirty"; exit 1; }
```

Fetch the CI bundle:

```bash
set -a
source "$HOME/Downloads/path-handoff.<network>.public.env"
set +a
rm -f "$HOME/Downloads/path-handoff.sepolia.public.env"
rm -f "$HOME/Downloads/path-handoff.mainnet.public.env"
rm -f "$HOME/Downloads/path-handoff.signing-runtime.sepolia.env"
rm -f "$HOME/Downloads/path-handoff.signing-runtime.mainnet.env"
# Close the bounded maintenance-only bridge window before continuing.
GH_REPO=inshell-art/path
npm run ops:fetch-bundle
```

Or with `RUN_DB_ID` if you already have it.

## I) Checkout the exact pinned commit

```bash
BUNDLE_SHA=$(jq -r .git_commit "bundles/$NETWORK/$RUN_ID/run.json")
git fetch origin
git checkout "$BUNDLE_SHA"
git submodule update --init --recursive
git diff --quiet && git diff --cached --quiet || { echo "tracked tree is dirty"; exit 1; }
```

## J) Load local Stage-3 env

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

Optional chain sanity:

```bash
cast chain-id --rpc-url "$SEPOLIA_RPC_URL"   # expect 11155111
cast chain-id --rpc-url "$MAINNET_RPC_URL"   # expect 1
```

## K) Execute the Signing OS lane

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
- you are on the Stage-3 Signing OS checkout
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

## L) Audit after postconditions

Run the post-run audit from the same repo checkout that holds the completed bundle:

```bash
AUDIT_ID=$NETWORK-audit-$(date -u +%Y%m%dT%H%M%SZ)
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID RUN_IDS=$RUN_ID npm run ops:audit:plan
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID npm run ops:audit:collect
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID npm run ops:audit:verify
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID npm run ops:audit:report
NETWORK=$NETWORK AUDIT_ID=$AUDIT_ID AUDIT_APPROVER=<name> npm run ops:audit:signoff
```

## M) Failure rules

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

## N) Stage-3 pass criteria

Stage 3 only counts as passed if:
- a real separate Signing OS machine was actually used
- the Signing OS checkout and local secrets root lived only on that machine
- no ad hoc fixes were made on Signing OS during execution
- `postconditions.json` is `pass`
- `audit_verify.json` is `pass`
- `audit_report.json` is `pass`
- `audit_signoff.json` exists
- final no-Safe authority/custody shape was used
- treasury in deploy params was the intended Treasury recipient address for the target network
- admin in deploy params was the intended final ADMIN Ledger-backed contract authority address for the target network
- final custody remained no-Safe and Ledger-only
- Signing OS online use stayed within the bounded-online rule
