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

## Private-local material

Never commit:
- private keys, mnemonics, recovery keys
- keystore JSON files
- password files
- secret `.env` files
- RPC URLs with embedded credentials
- signer-to-device mappings tied to real operators
- private incident contacts or fallback procedures
- live bundles, evidence, or audit outputs unless deliberately curated and redacted

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
