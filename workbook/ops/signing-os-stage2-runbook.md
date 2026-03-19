# Signing OS Stage 2 runbook

Stage 2 is the Sepolia authority-shape rehearsal:
- separate local macOS account on the same machine
- separate home directory and shell history
- authority shape should now resemble the intended Safe-based model

Use this stage when:
- Stage 1 has already passed
- you want to prove the serious operator flow from a distinct macOS account
- you want Sepolia to reflect the intended treasury/admin target shape more closely

## A) Stage-2 path model

Use the Signing OS account's own paths:
- repo checkout: `~/Projects/path`
- local secrets root: `~/.opsec`

Do not reference:
- the Dev OS home directory
- the Stage-1 workspace under `~/Projects/SIGNING_OS`

## B) Stage-2 account setup

Create and enter a dedicated local macOS Signing OS account:
1. open `System Settings -> Users & Groups`
2. add a new local user
3. choose a distinct account name for Signing OS work
4. do not reuse the normal development account

After logging into the new account, verify:
- `pwd` starts under the new account home
- `echo $HOME` is the new account home
- `ls ~/Projects` does not rely on the old account's checkout
- `ls ~/.opsec` does not rely on the old account's secrets

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

Then create the local-only operator directories:

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

## C) Stage-2 sequencing rule

Before any serious Dev OS preflight or bundle creation that depends on deploy signer binding:
1. finish this Stage-2 account and local-storage setup
2. prepare the local keystore/password/env using the common [Signing OS runbook](signing-os-runbook.md)
3. if the deploy signer is new or rotated, complete [Signer Enrollment runbook](signer-enrollment-runbook.md)
4. only then return to [Sepolia runbook](sepolia-runbook.md) or [Mainnet runbook](mainnet-runbook.md) on Dev OS

## D) Stage-2 authority realism

For Stage 2 Sepolia rehearsal:
- treasury in deploy params should be the real Sepolia Treasury Safe
- Admin Safe should be the intended handoff target
- if hardware has not arrived yet, honest temporary Sepolia-only software owner aliases are acceptable for the second owner set
- do not reuse `*_HW_*` alias names for software stand-ins

## E) Stage-2 pass criteria

Stage 2 only counts as passed if:
- a separate macOS account was actually used
- the Signing OS checkout lived under that account's own home directory
- no ad hoc fixes were made on Signing OS during the run
- `postconditions.json` is `pass`
- `audit_verify.json` is `pass`
- `audit_report.json` is `pass`
- `audit_signoff.json` exists
- treasury in deploy params was the real Sepolia Treasury Safe
- Admin Safe target was identified for handoff
- any temporary second-owner stand-in remained Sepolia-only and honestly named
