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
- one Ledger-backed wallet for `ADMIN`
- one Ledger-backed wallet for `TREASURY`
- both active wallets live on attached-passphrase / secondary-PIN paths
- base / no-passphrase wallets are intentionally unused

## Dedicated host rule
A dedicated Signing OS / ops host may still exist.
Its job is to coordinate serious runs and Ledger-backed admin actions.
It is not a final software signer for ADMIN or TREASURY.

## Public/private boundary
The public repo may contain:
- alias names
- placeholder addresses
- public-safe runbooks
- redacted examples

The public repo must not contain:
- recovery phrases
- passphrases
- real signer-to-device maps
- raw keyed RPC URLs
- final-custody secret material

## Deploy-lane note
A deploy-only keystore may still exist on Signing OS for deploy lanes.
That is a deploy execution detail, not the final custody architecture.
It must not be described as ADMIN or TREASURY custody.

## What stays unchanged in this refactor
- contracts still take a single constructor admin address and a separate treasury recipient address
- Signing OS remains the dedicated serious-run host
- deploy lanes may still use the policy-approved deploy keystore alias until a separate deploy-architecture change is made
- this refactor does not change already deployed on-chain addresses by itself
