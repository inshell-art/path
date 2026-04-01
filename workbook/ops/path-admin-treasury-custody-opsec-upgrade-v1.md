# PATH custody migration note

## Status
The old Safe-based custody note is superseded.
The canonical final-custody rule now lives in:
- [../../docs/custody-no-safe-two-ledgers.md](../../docs/custody-no-safe-two-ledgers.md)

## What changed
PATH no longer treats steady-state custody as:
- Safe-based ADMIN authority
- Safe-based TREASURY authority
- software-keystore final ownership on Signing OS

PATH now documents:
- `ADMIN` as a direct Ledger-backed contract authority account
- `TREASURY` as a direct Ledger-backed recipient/holding account
- one Ledger-backed attached-passphrase wallet per role
- base / no-passphrase wallets as unused

## What stayed intentionally unchanged
- the contracts still accept a single admin address and a separate treasury recipient address
- Signing OS still exists as the dedicated serious-run host
- deploy lanes may still use a deploy-only keystore alias such as `*_DEPLOY_SW_A`
- this repo refactor does not change already deployed addresses by itself
- this repo refactor does not convert contract access control patterns

## What still needs separate follow-up if desired
- changing deploy lanes away from deploy-keystore execution
- rewriting non-deploy lane procedures around direct Ledger execution end to end
- changing on-chain admin or treasury addresses on already deployed systems
- changing contract ownership/access-control semantics
