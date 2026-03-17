# Signer Enrollment runbook

Purpose: enroll or rotate public signer addresses without mixing Signing OS secret custody and Dev OS policy editing.

Use this runbook:
- before the first serious Sepolia or Mainnet run that uses a new signer
- when rotating any signer alias
- when batching one-time policy initialization so you do not switch between Dev OS and Signing OS repeatedly

Ownership split:
- Signing OS:
  - generate or import the encrypted keystore
  - derive the public address
  - hand off only public address data
- Dev OS:
  - update `ops/policy/lane.<network>.json`
  - commit and push the policy change
- Signing OS:
  - pull latest `main`
  - only then start the real lane run

Never edit or push repo policy from the Signing OS as part of this procedure.

## A) One-time initialization items to batch

Check current policy initialization state:

```bash
npm run ops:policy:init:check
```

Current repo state:
- `sepolia`
  - deploy signer alias is enrolled: `SEPOLIA_DEPLOY_SW_A`
  - missing signer alias map entries for future write lanes:
    - `SEPOLIA_GOV_SW_A`
    - `SEPOLIA_GOV_HW_B`
    - `SEPOLIA_TREASURY_SW_A`
    - `SEPOLIA_TREASURY_HW_B`
- `mainnet`
  - missing signer alias map entries:
    - `MAINNET_DEPLOY_SW_A`
    - `MAINNET_GOV_SW_A`
    - `MAINNET_GOV_HW_B`
    - `MAINNET_TREASURY_SW_A`
    - `MAINNET_TREASURY_HW_B`
  - deploy fee policy placeholders still require one-time policy values:
    - `deploy.max_fee_per_gas_gwei`
    - `deploy.max_priority_fee_per_gas_gwei`

Also check provider-host policy once per provider choice:
- if you plan to use a provider host not already in `rpc_host_allowlist`, update that allowlist on Dev OS once before the first real run

Batch recommendation:
- enroll every signer alias you expect to use in the near term
- update all corresponding public addresses in one Dev OS policy commit
- set mainnet fee policy in the same one-time policy commit if those values are known

## B) Generate or import the signer on Signing OS

Example software signer paths:

```bash
~/.opsec/sepolia/signers/deploy_sw_a/keystore.json
~/.opsec/sepolia/password-files/deploy_sw_a.password.txt
~/.opsec/mainnet/signers/deploy_sw_a/keystore.json
~/.opsec/mainnet/password-files/deploy_sw_a.password.txt
```

Generate a fresh signer locally on the Signing OS:

```bash
cast wallet new ~/.opsec/sepolia/signers/deploy_sw_a keystore.json
cast wallet new ~/.opsec/mainnet/signers/deploy_sw_a keystore.json
```

Or import an existing signer through a trusted flow that still ends with an encrypted keystore on the Signing OS.

## C) Derive the public address on Signing OS

Derive the address from the encrypted keystore locally on the Signing OS:

```bash
cast wallet address \
  --keystore ~/.opsec/sepolia/signers/deploy_sw_a/keystore.json \
  --password-file ~/.opsec/sepolia/password-files/deploy_sw_a.password.txt
```

Mainnet example:

```bash
cast wallet address \
  --keystore ~/.opsec/mainnet/signers/deploy_sw_a/keystore.json \
  --password-file ~/.opsec/mainnet/password-files/deploy_sw_a.password.txt
```

Repeat for every alias you are enrolling in this batch.

## D) Transfer the public address to Dev OS

The address is public metadata. It is safe to transfer to Dev OS.

Preferred handoff format:

```text
NETWORK=sepolia
ALIAS=SEPOLIA_DEPLOY_SW_A
ADDRESS=0x...
```

Acceptable transfer methods:
- manual transcription
- copy/paste between local sessions
- text note
- QR code or screenshot

Do not transfer:
- keystore JSON
- password files
- raw private keys

## E) Update policy on Dev OS

On Dev OS, edit the lane policy and add or update the alias mapping:

```bash
$EDITOR ops/policy/lane.sepolia.json
$EDITOR ops/policy/lane.mainnet.json
```

Example:

```json
"signer_alias_map": {
  "SEPOLIA_DEPLOY_SW_A": "0x..."
}
```

Then validate policy initialization:

```bash
npm run ops:policy:init:check
```

Commit and push the policy update from Dev OS.

## F) Pull the policy on Signing OS

After the Dev OS policy commit is pushed:

```bash
git fetch origin
git checkout main
git pull --ff-only origin main
```

Only after that should you start the real lane run.

## G) Clean procedure rule

The clean procedure is:
1. Signing OS generates or imports the signer and derives the public address
2. Dev OS updates and pushes policy
3. Signing OS pulls latest `main`
4. the actual lane run begins

Treat signer enrollment or rotation as a one-time initialization procedure, not a per-run step.
