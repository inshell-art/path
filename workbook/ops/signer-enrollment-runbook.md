# Signer Enrollment runbook

Purpose: enroll or rotate public signer addresses without mixing Signing OS secret custody and Dev OS policy editing.

Use this runbook:
- before the first serious Sepolia or Mainnet run that uses a new signer
- when rotating any signer alias
- when batching one-time policy initialization so you do not switch between Dev OS and Signing OS repeatedly

Ownership split:
- Signing OS:
  - for deploy aliases, generate or import the encrypted keystore
  - derive the public address
  - for final ADMIN / TREASURY aliases, confirm the Ledger-derived public address
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

Treat the checker output as the source of truth.

Scope rule:
- no `LANE` set:
  - check full network initialization across all lanes
  - use this for signer enrollment / batching / one-time readiness work
- `LANE=<lane>` set:
  - check only the targeted lane's signer and fee requirements
  - use this for serious-run preflight, for example:

```bash
NETWORK=sepolia LANE=deploy npm run ops:policy:init:check
NETWORK=mainnet LANE=deploy npm run ops:policy:init:check
```

Current repo state at the time this runbook was written:
- `sepolia`
  - deploy signer alias is enrolled: `SEPOLIA_DEPLOY_SW_A`
  - missing signer alias map entries for future write lanes:
    - `SEPOLIA_ADMIN_HW_A`
    - `SEPOLIA_TREASURY_HW_A`
- `mainnet`
  - missing signer alias map entries:
    - `MAINNET_DEPLOY_SW_A`
    - `MAINNET_ADMIN_HW_A`
    - `MAINNET_TREASURY_HW_A`
  - deploy fee policy placeholders still require one-time policy values:
    - `deploy.max_fee_per_gas_gwei`
    - `deploy.max_priority_fee_per_gas_gwei`

Also check provider-host policy once per provider choice:
- if you plan to use a provider host not already in `rpc_host_allowlist`, update that allowlist on Dev OS once before the first real run

Batch recommendation:
- enroll every signer alias you expect to use in the near term
- update all corresponding public addresses in one Dev OS policy commit
- set mainnet fee policy in the same one-time policy commit if those values are known

Authority model:
- signer aliases represent human/operator signer identities
- final ADMIN authority is a direct Ledger-backed address, not a Safe owner set
- final TREASURY authority is a direct Ledger-backed recipient/holding address, not a contract-admin role
- base / no-passphrase wallets are intentionally unused
- the live hardware aliases should correspond to attached-passphrase / secondary-PIN Ledger addresses

Temporary deployment rule:
- the deploy signer may still remain a software-keystore alias such as `*_DEPLOY_SW_A`
- do not create or keep final ADMIN / TREASURY software-owner aliases in policy
- do not map a deploy keystore to a `*_HW_*` alias name

## B) Generate or import the signer on Signing OS

This section is for software deploy aliases such as `SEPOLIA_DEPLOY_SW_A` and `MAINNET_DEPLOY_SW_A`.
It is not the enrollment flow for final ADMIN or TREASURY Ledger identities.

For final ADMIN / TREASURY Ledger aliases:
- derive or confirm the public address from the Ledger setup flow
- hand off only `NETWORK`, `ALIAS`, and `ADDRESS` to Dev OS
- do not create a Signing OS keystore for those final Ledger aliases

Example deploy software signer paths:

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

Before using `cast` for the first serious signer on a Signing OS, review and complete:
- [cast-verification-discipline.md](cast-verification-discipline.md)

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

Repeat for every deploy alias you are enrolling in this batch.

For Ledger-only final aliases, use the Ledger setup flow to read the public address and write the same three-line handoff note:

```text
NETWORK=sepolia
ALIAS=SEPOLIA_ADMIN_HW_A
ADDRESS=0x...
```

## D) Transfer the public address to Dev OS

The address is public metadata. It is safe to transfer to Dev OS.

Preferred handoff format:

```text
NETWORK=sepolia
ALIAS=SEPOLIA_DEPLOY_SW_A
ADDRESS=0x...
```

Recommended transfer media by stage:
- stage 1, same account:
  - manual transcription
  - copy/paste through a local text note
- stage 2, separate macOS account on the same machine:
  - removable media
  - manual transcription
  - QR code or screenshot
- stage 3, real separate machine:
  - removable media
  - manual transcription
  - QR code or printed note

Acceptable transfer methods:
- manual transcription
- copy/paste between local sessions
- text note
- QR code or screenshot
- USB text file

Transfer discipline:
- transfer only `NETWORK`, `ALIAS`, and `ADDRESS`
- do not add commentary or extra secret-bearing context
- do not transfer keystore paths or password-file paths unless you deliberately want those public path conventions on Dev OS too
- if using USB, store plain text only and remove it after the Dev OS policy update is complete

Do not transfer:
- keystore JSON
- password files
- raw private keys

Sanity check before leaving the Signing OS:
1. derive the address again from the keystore or Ledger path
2. confirm the second result matches the first exactly
3. write the handoff note in the three-line format above
4. verify the alias name is the one you actually intend to enroll

Sanity check after arriving on Dev OS:
1. paste or type the handoff note into a temporary scratch note
2. compare the full address against the Signing OS note
3. only then update `signer_alias_map`
4. run `npm run ops:policy:init:check`

## E) Update policy on Dev OS

On Dev OS, edit the lane policy and add or update the alias mapping:

```bash
$EDITOR ops/policy/lane.sepolia.json
$EDITOR ops/policy/lane.mainnet.json
```

Example:

```json
"signer_alias_map": {
  "SEPOLIA_DEPLOY_SW_A": "0x...",
  "SEPOLIA_ADMIN_HW_A": "0x...",
  "SEPOLIA_TREASURY_HW_A": "0x..."
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

## G) Numbered switch sequence

Use this exact OS-switch sequence:

1. On Signing OS:
- generate or import the encrypted deploy keystore if needed
- derive the public address
- derive it a second time and confirm the same result
- prepare the three-line handoff note

2. Move only the handoff note to Dev OS:
- `NETWORK`
- `ALIAS`
- `ADDRESS`

3. On Dev OS:
- update `ops/policy/lane.sepolia.json` and/or `ops/policy/lane.mainnet.json`
- if batching initialization, update all missing aliases in one pass
- if batching initialization, also set Mainnet deploy fee policy and any new RPC host allowlist entries
- run `npm run ops:policy:init:check`
- commit and push

4. Return to Signing OS:
- pull latest `main`
- continue the serious run only after the updated policy is present locally
