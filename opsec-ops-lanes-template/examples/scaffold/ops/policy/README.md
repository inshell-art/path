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
For Sepolia/Mainnet deploy lanes, use downstream strict schemas:
- set `STRICT_PARAMS_SCHEMA=1`
- provide `PARAMS_SCHEMA=schemas/params/<kind>.<contract>.<lane>.schema.json`
Template `examples/inputs/*.example.json` schemas are minimal references and should not be used as production strict validation.
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
