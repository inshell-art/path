# Signing OS Stage 1 runbook

Stage 1 is the first serious Sepolia rehearsal shape:
- separate signer workspace on the same macOS account
- separate local-only secrets root
- procedure rehearsal first, not final authority-shape proof

Use this stage when:
- you want to prove the full Dev OS -> CI -> Signing OS -> audit flow quickly
- you want separate checkout and separate secrets root before moving to stronger isolation
- temporary EOA treasury/admin is still acceptable for this rehearsal

Do not treat Stage 1 as proof of:
- final Safe treasury custody
- final Admin Safe handoff shape
- final production signer topology

## A) Stage-1 path model

Use these Stage-1-local paths:
- repo checkout: `~/Projects/SIGNING_OS/path`
- local secrets root: `~/Projects/SIGNING_OS/.opsec`

When common runbooks show `~/.opsec/...`, substitute:
- `~/Projects/SIGNING_OS/.opsec/...`

## B) Stage-1 workspace setup

Create or update the dedicated Stage-1 checkout:

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

Create the Stage-1-local operator directories:

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

## C) Stage-1 sequencing rule

Before any serious Dev OS preflight or bundle creation that depends on deploy signer binding:
1. finish this Stage-1 workspace setup
2. prepare the local keystore/password/env using the common [Signing OS runbook](signing-os-runbook.md)
3. if the deploy signer is new or rotated, complete [Signer Enrollment runbook](signer-enrollment-runbook.md)
4. only then return to [Sepolia runbook](sepolia-runbook.md) or [Mainnet runbook](mainnet-runbook.md) on Dev OS

That means:
- Signing OS keystore preparation comes before serious Dev OS preflight when signer binding is changing
- Dev OS should not dispatch a serious bundle until policy has been updated and pushed for the intended signer

## D) Stage-1 common-flow handoff

After Dev OS dispatches the bundle:
- continue the common Signing OS flow in [Signing OS runbook](signing-os-runbook.md)
- use the Stage-1-local secrets root when a command needs `OPSEC_ROOT`

Example:

```bash
OPSEC_ROOT=~/Projects/SIGNING_OS/.opsec CHECK_GH_AUTH=1 NETWORK=sepolia LANE=deploy npm run ops:preflight:signingos
```

## E) Stage-1 pass criteria

Stage 1 only counts as passed if:
- separate signer workspace and separate secrets root were actually used
- no ad hoc fixes were made on Signing OS during the run
- `postconditions.json` is `pass`
- `audit_verify.json` is `pass`
- `audit_report.json` is `pass`
- `audit_signoff.json` exists

Stage-1 authority realism:
- temporary EOA treasury/admin is acceptable only if the run is explicitly treated as procedure rehearsal
- do not present a Stage-1 EOA treasury/admin run as proof of final Safe authority shape
