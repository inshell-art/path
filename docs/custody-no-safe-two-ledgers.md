# PATH Custody Model: No Safe, Two Ledgers

## Scope
This is the current public-safe custody architecture for PATH.
It describes final custody, not every deploy-lane implementation detail.

## Final role split
- `ADMIN` = contract authority account
- `TREASURY` = recipient / holding account
- `TREASURY` is not a contract-admin role

## Final custody shape
- no Safe in steady state
- no software keystore signer for final custody
- one Ledger-backed operational wallet for `ADMIN`
- one Ledger-backed operational wallet for `TREASURY`
- both operational wallets live on attached-passphrase / secondary-PIN paths
- base / no-passphrase wallets are intentionally unused

## Dedicated host rule
A dedicated Signing OS / ops host may still exist.
Its job is to coordinate serious runs and Ledger-backed admin actions.
It is not a final software signer for ADMIN or TREASURY.

## Daily ops layer vs recovery layer
Daily ops secret layer:
- Ledger PINs / secondary PIN paths
- ops-host password / disk unlock

Recovery layer only:
- passphrase master copies
- recovery phrases / metals
- deep recovery maps and pairing records

Do not treat passphrase master copies as daily ops material.
They stay in the deeper recovery layer only.

## Public/private boundary
The public repo may contain:
- alias names
- placeholder addresses
- public-safe runbooks
- redacted examples
- non-secret map/checklist templates

The public repo must not contain:
- recovery phrases
- passphrases
- real signer-to-device maps
- raw keyed RPC URLs
- final-custody secret material

## Recovery rule
Recovery without Ledger devices must remain possible through another BIP39-compatible wallet or device using:
- the recorded recovery phrase
- the recorded passphrase
- the recorded derivation path

The public repo may describe that rule and template the mapping.
It must not store the real values.

## Deploy-lane note
A deploy-only keystore may still exist on Signing OS for deploy lanes.
That is a deploy execution detail, not the final custody architecture.
It must not be described as ADMIN or TREASURY custody.

## Supporting templates
- [MAP-MAIN template](map-main-template.md)
- [OPS-CHECKLIST template](ops-checklist-template.md)

## What stays unchanged in this refactor
- contracts still take a single constructor admin address and a separate treasury recipient address
- Signing OS remains the dedicated serious-run host
- deploy lanes may still use the policy-approved deploy keystore alias until a separate deploy-architecture change is made
- this refactor does not change already deployed on-chain addresses by itself
