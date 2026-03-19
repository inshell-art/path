# Signing OS Stage 3 runbook

Stage 3 is the final production-shape rehearsal:
- real separate Signing OS machine
- separate home directory
- separate local-only secrets storage
- final intended authority and signer topology

Use this stage when:
- Stage 2 has already passed
- you want Sepolia to mirror the final Mainnet operating shape as closely as possible
- you are ready to prove the real machine boundary

## A) Stage-3 machine model

Use a dedicated Signing OS machine with:
- its own `~/Projects/path` checkout
- its own `~/.opsec`
- no dependence on the Dev OS home directory, shared user account, or shared secrets root

Keep the machine role narrow:
- repo checkout
- local-only keystore/password files
- bundle fetch
- verify/approve/apply/postconditions/audit

## B) Stage-3 first-time setup

On the Signing OS machine:
1. install required tools from the common [Signing OS runbook](signing-os-runbook.md)
2. create or update the repo checkout under `~/Projects/path`:

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

3. create the local-only operator directories under `~/.opsec`:

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

4. prepare the local keystore/password/env using the common [Signing OS runbook](signing-os-runbook.md)

## C) Stage-3 sequencing rule

Before any serious Dev OS preflight or bundle creation that depends on deploy signer binding:
1. finish this Stage-3 machine setup
2. if the deploy signer is new or rotated, complete [Signer Enrollment runbook](signer-enrollment-runbook.md)
3. only then return to [Sepolia runbook](sepolia-runbook.md) or [Mainnet runbook](mainnet-runbook.md) on Dev OS

## D) Stage-3 authority realism

For Stage 3:
- treasury should be the intended Safe treasury
- admin authority should be the intended Safe target
- signer topology should match the intended production signer set
- if hardware is part of the target model, this stage should use the hardware-backed topology

## E) Stage-3 pass criteria

Stage 3 only counts as passed if:
- a real separate Signing OS machine was actually used
- the Signing OS checkout and local secrets root lived only on that machine
- no ad hoc fixes were made on Signing OS during the run
- `postconditions.json` is `pass`
- `audit_verify.json` is `pass`
- `audit_report.json` is `pass`
- `audit_signoff.json` exists
- final Safe authority/custody shape was used
- final intended signer topology was used, including hardware if part of the target model
