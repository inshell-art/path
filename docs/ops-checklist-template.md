# OPS-CHECKLIST Template

Use this exact checklist text as a public-safe operator template.

```text
OPS-CHECKLIST

1. Right machine: dedicated ops host / Signing OS only.
2. Right session: bounded maintenance or bounded run session only.
3. Right network: exact target network and RPC host confirmed.
4. Right repo state: exact pinned commit and run id confirmed.
5. Right role: ADMIN action uses ADMIN operational wallet; TREASURY action uses TREASURY operational wallet.
6. Right wallet mode: operational wallet is attached-passphrase / secondary-PIN path; base wallet is unused.
7. Ops secret layer only: host password/disk unlock plus Ledger PIN path only.
8. Recovery-layer materials absent: no passphrase master copy, recovery phrase, or recovery map should be present in the daily ops layer.
9. Recovery rule understood: recovery without Ledger remains possible with another BIP39-compatible wallet/device using the recorded phrase, passphrase, and derivation path.
10. Stop immediately on any address, path, network, or prompt mismatch.
```
