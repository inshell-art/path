# Policy files

Copy example policies from the template repo and edit the copies:
- `ops/policy/lane.devnet.example.json` -> `ops/policy/lane.devnet.json`
- `ops/policy/lane.sepolia.example.json` -> `ops/policy/lane.sepolia.json`
- `ops/policy/lane.mainnet.example.json` -> `ops/policy/lane.mainnet.json`
- `ops/policy/audit.policy.example.json` -> `ops/policy/audit.policy.json`

Keep secrets out of git. Only reference local keystore paths via env vars.

Mainnet write lanes default to:
- `gates.require_rehearsal_proof: true`
- `gates.rehearsal_proof_network: "devnet"`
Only set the gate to false if you are consciously overriding the control.
For EVM lanes, set realistic EIP-1559 bounds in each lane's `fee_policy`.
Sepolia/Mainnet deploy lanes default to include:
- `required_inputs: [{\"kind\": \"constructor_params\"}]`
Use `ops/tools/lock_inputs.sh` to create run-scoped locked wrappers and pass them to bundle via `INPUTS_TEMPLATE`.
Downstreams can define tighter business schemas via `PARAMS_SCHEMA` in `lock_inputs.sh`.
Legacy keys (`requires_*_rehearsal_proof`, `gates.require_*_rehearsal_proof`) are deprecated but temporarily supported during migration.
Audit policy controls coverage thresholds and open-finding gates for periodic/release audits.
Audit contract requires:
- `audit_plan.json`
- `audit_evidence_index.json`
- `audit_verification.json`
- `audit_report.json`
- `findings.json`
Optional but recommended:
- `signoff.json`
