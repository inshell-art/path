# Policy files

Edit the PATH policy files in this repo:
- `ops/policy/lane.devnet.example.json` -> `ops/policy/lane.devnet.json`
- `ops/policy/lane.sepolia.example.json` -> `ops/policy/lane.sepolia.json`
- `ops/policy/lane.mainnet.example.json` -> `ops/policy/lane.mainnet.json`
- `ops/policy/audit.policy.example.json` -> `ops/policy/audit.policy.json`

Keep secrets out of git. Only reference local deploy keystore paths via env vars.
Before the first serious Sepolia/Mainnet run with a new signer set, complete `workbook/ops/signer-enrollment-runbook.md` and run `npm run ops:policy:init:check`.

Signer semantics:
- `allowed_signers` are signer identities that can authorize the relevant lane, not destination addresses
- final custody is no-Safe and Ledger-only in steady state
- final `ADMIN` signer aliases should be hardware aliases such as `*_ADMIN_HW_A`
- final `TREASURY` signer aliases should be hardware aliases such as `*_TREASURY_HW_A`
- `TREASURY` is a recipient/holding role, not a contract-admin role
- the deploy alias may still be a software-keystore alias such as `*_DEPLOY_SW_A`, but that alias is deploy-only and not final custody
- do not map a software key to a `*_HW_*` alias name
- the live hardware aliases should correspond to attached-passphrase / secondary-PIN Ledger addresses
- base / no-passphrase wallets are intentionally unused and should not appear as final signer aliases

Lane-shape guidance:
- `deploy` may stay on a deploy-only signer alias such as `*_DEPLOY_SW_A`
- `handoff` is transitional only; use it when moving authority away from a temporary deploy signer or old admin path
- `govern`, `operate`, and `emergency` should resolve to final `ADMIN` signer identities
- `treasury` should resolve to final `TREASURY` signer identities

Mainnet write lanes default to:
- `gates.require_rehearsal_proof: true`
- `gates.rehearsal_proof_network: "devnet"`
Only set the gate to false if you are consciously overriding the control.
For EVM lanes, set realistic EIP-1559 bounds in each lane's `fee_policy`.
Legacy keys (`requires_*_rehearsal_proof`, `gates.require_*_rehearsal_proof`) are deprecated but temporarily supported during migration.
Audit policy controls coverage thresholds and open-finding gates for periodic/release audits.
`AUD-011` verifies pinned constructor inputs were enforced at apply for deployed Sepolia/Mainnet runs.
