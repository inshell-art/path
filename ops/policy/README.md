# Policy files

Edit the PATH policy files in this repo:
- `ops/policy/lane.devnet.example.json` -> `ops/policy/lane.devnet.json`
- `ops/policy/lane.sepolia.example.json` -> `ops/policy/lane.sepolia.json`
- `ops/policy/lane.mainnet.example.json` -> `ops/policy/lane.mainnet.json`
- `ops/policy/audit.policy.example.json` -> `ops/policy/audit.policy.json`

Keep secrets out of git. Only reference local keystore paths via env vars.
Before the first serious Sepolia/Mainnet run with a new signer set, complete `workbook/ops/signer-enrollment-runbook.md` and run `npm run ops:policy:init:check`.

Signer semantics:
- `allowed_signers` are signer-owner identities, not treasury/admin destination addresses
- if treasury or admin authority is a Safe, model the Safe as the target authority/destination and model the Safe owners as signer aliases
- final ADMIN / TREASURY Safe owner aliases should be hardware-only aliases such as `*_GOV_HW_A`, `*_GOV_HW_B`, `*_TREASURY_HW_A`, `*_TREASURY_HW_B`
- the deploy alias may still be a software-keystore alias such as `*_DEPLOY_SW_A`
- do not map a software key to a `*_HW_*` alias name

Mainnet write lanes default to:
- `gates.require_rehearsal_proof: true`
- `gates.rehearsal_proof_network: "devnet"`
Only set the gate to false if you are consciously overriding the control.
For EVM lanes, set realistic EIP-1559 bounds in each lane's `fee_policy`.
Legacy keys (`requires_*_rehearsal_proof`, `gates.require_*_rehearsal_proof`) are deprecated but temporarily supported during migration.
Audit policy controls coverage thresholds and open-finding gates for periodic/release audits.
`AUD-011` verifies pinned constructor inputs were enforced at apply for deployed Sepolia/Mainnet runs.
