# MAP-MAIN Master Template

Use this as a public-safe structure only.
Keep real secrets and real operator-identifying placement data outside git.

## Purpose
`MAP-MAIN` is the stable master map of structural custody facts.
It should change only when the architecture, expected addresses, derivation paths, or recovery pairing model changes.
It is not the recurring drill log.

Use `DRILL-LOG` for mutable recurring checks and timestamps.

## Fields

```text
SYSTEM=PATH
NETWORK=<sepolia|mainnet>
MAP_MAIN_VERSION=<version>

ADMIN_ADDRESS=0x<expected-admin-address>
TREASURY_ADDRESS=0x<expected-treasury-address>

ADMIN_OPERATIONAL_WALLET=
  device=<Ledger label/code>
  derivation_path=<record exact path>
  wallet_mode=attached-passphrase / secondary-PIN

TREASURY_OPERATIONAL_WALLET=
  device=<Ledger label/code>
  derivation_path=<record exact path>
  wallet_mode=attached-passphrase / secondary-PIN

BASE_WALLETS=unused

RECOVERY_PAIRING=
  admin_phrase_copy=<private location reference>
  admin_passphrase_copy=<private location reference>
  treasury_phrase_copy=<private location reference>
  treasury_passphrase_copy=<private location reference>

RECOVERY_WITHOUT_LEDGER=
  supported=true
  wallet_type=any BIP39-compatible wallet/device
  admin_requires=<phrase + passphrase + path>
  treasury_requires=<phrase + passphrase + path>
```

## Rules
- record exact expected addresses
- record exact derivation paths
- record recovery pairing at the level of private location references only
- do not record raw phrases, raw passphrases, or raw PINs in the public repo
- keep signer-to-device mappings tied to real operators outside git if that mapping is sensitive
- keep routine drill timestamps and recurring results in `DRILL-LOG`, not in `MAP-MAIN`
