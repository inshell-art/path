# Policy files

Copy example policies from the template repo and edit the copies:
- `ops/policy/lane.devnet.example.json` -> `ops/policy/lane.devnet.json`
- `ops/policy/lane.sepolia.example.json` -> `ops/policy/lane.sepolia.json`
- `ops/policy/lane.mainnet.example.json` -> `ops/policy/lane.mainnet.json`
- `ops/policy/audit.policy.example.json` -> `ops/policy/audit.policy.json`

Keep secrets out of git. Only reference local keystore paths via env vars.
Before the first serious Sepolia/Mainnet run with a new signer set, complete `workbook/ops/signer-enrollment-runbook.md` and run `npm run ops:policy:init:check`.

Signer semantics:
- `allowed_signers` are signer-owner identities, not treasury/admin destination addresses
- if treasury or admin authority is a Safe, model the Safe as the target authority/destination and model the Safe owners as signer aliases
- do not map a software key to a `*_HW_*` alias name
- if Sepolia rehearsal must proceed before hardware arrives, use an honestly named temporary software alias for the rehearsal owner and retire it after the real hardware alias is enrolled

Mainnet write lanes default to:
- `gates.require_rehearsal_proof: true`
- `gates.rehearsal_proof_network: "devnet"`
Only set the gate to false if you are consciously overriding the control.
For EVM lanes, set realistic EIP-1559 bounds in each lane's `fee_policy`.
Legacy keys (`requires_*_rehearsal_proof`, `gates.require_*_rehearsal_proof`) are deprecated but temporarily supported during migration.
Audit policy controls coverage thresholds and open-finding gates for periodic/release audits.
`AUD-011` verifies pinned constructor inputs were enforced at apply for deployed Sepolia/Mainnet runs.
