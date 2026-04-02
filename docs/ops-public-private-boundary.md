# Ops Public / Private Boundary

This repo stays public.

The operating rule is:
- keep contracts, schemas, generic ops tooling, public-safe runbooks, and redacted examples in git
- keep secrets, signer material, private overlays, and live operator outputs outside git

## Public-safe material

Safe to keep in this repo:
- contract code under `evm/`
- public-safe ops tooling under `ops/`
- lane policy with aliases/placeholders
- schemas, examples, and redacted fixtures
- generic runbooks and architecture docs
- public contract addresses and release notes when intentionally published
- non-secret custody/checklist templates such as `MAP-MAIN` and `OPS-CHECKLIST`

## Private-local material

Never commit:
- private keys, mnemonics, recovery keys
- passphrases or passphrase hints
- keystore JSON files used for real deploy signing
- password files
- secret `.env` files
- RPC URLs with embedded credentials
- signer-to-device mappings tied to real operators
- private incident contacts or fallback procedures
- live bundles, evidence, or audit outputs unless deliberately curated and redacted

## Final custody rule

Final PATH custody is hardware-only:
- `ADMIN` is the Ledger-backed contract authority account
- `TREASURY` is the Ledger-backed recipient/holding account
- the live Ledger addresses correspond to attached-passphrase / secondary-PIN operational wallets
- base / no-passphrase wallets are intentionally unused

Daily ops secret layer is only:
- Ledger secondary PINs / operational PIN path
- ops-host password / disk unlock

Keep outside git and outside the daily ops layer:
- recovery phrases
- passphrase master copies
- metals / physical recovery inventory
- real signer-to-device mappings
- operator-specific box/recovery maps

Passphrase master copies remain recovery-layer only.

## Local/private overlay model

Use local paths outside git for real operator state, for example:

```text
~/.opsec/path/
  env/
    sepolia.env
    mainnet.env
  params/
    params.sepolia.deploy.json
    params.mainnet.deploy.json
  handoff/
    path-handoff.sepolia.public.env
    path-handoff.mainnet.public.env
    path-handoff.signing-runtime.sepolia.env
    path-handoff.signing-runtime.mainnet.env
  runs/
    sepolia/
    mainnet/

~/.opsec/sepolia/
  signers/
    deploy_sw_a/
      keystore.json
      address.txt
  password-files/
    deploy_sw_a.password.txt

~/.opsec/mainnet/
  signers/
    deploy_sw_a/
      keystore.json
      address.txt
  password-files/
    deploy_sw_a.password.txt
```

The public repo documents this model. It does not store the real materials.

Keystore overlays are not part of final custody.
They remain valid only for:
- deploy-only lanes
- dev-only workflows
- deliberate migration windows that are clearly labeled temporary

Do not present a keystore JSON or password file as the final ADMIN or TREASURY path.

## Recovery rule

Recovery without Ledger devices must remain possible through another BIP39-compatible wallet or device using the recorded phrase, passphrase, and derivation path.
The repo may document that rule and template the mapping, but not the real values.

## Artifacts vs bundles

Use the terms consistently:
- `artifacts/` = broad evidence / working material
- `bundles/` = frozen per-run packages for `verify -> approve -> apply`

In public git, both should default to:
- `README.md`
- `.gitkeep`
- `*.example.*`
- `*.redacted.*`
- deliberately reviewed public-safe fixtures only

## CI artifact rule

CI bundle artifacts are not public by default.
They are:
- non-secret by design
- still untrusted until verified on Signing OS
- kept in controlled CI storage unless intentionally curated and redacted for publication

## Signing boundary

Serious Sepolia/Mainnet apply remains Signing OS only.
CI computes deterministic bundles without secrets.
Dev OS prepares inputs and dispatches bundle jobs.
Signing OS may hold a deploy-only keystore for the deploy lane, but that does not make it the final custody location for ADMIN or TREASURY.

## Deliberate publication rule

If you want to publish generated material, do it intentionally:
- review it
- redact it where needed
- rename it as `*.example.*` or `*.redacted.*` when appropriate
- make sure it does not include private overlay detail

## Historical leak response

If Class A material ever entered git history:
1. treat it as disclosed
2. rotate or replace it
3. remove it from current HEAD
4. consider history rewrite if warranted
5. do not rely on history rewrite alone as the fix

Historical note for this repo:
- `keystore.json` existed in repo history in commits `ec6a66a267deeb06ad256a4639617876b6cc7cb9` and `0850f4a91ca5334754a6ea0441f858100d2c9ddd`
- any material from that file must be treated as disclosed and permanently retired
- current HEAD keeps keystore/password/env material out of git and blocks reintroduction with the public-safe guard
