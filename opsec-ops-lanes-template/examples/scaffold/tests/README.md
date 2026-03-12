# Scaffold tests

These scripts validate the template audit module contracts in an isolated temporary scaffold checkout.

## Scripts
- `audit_smoke.sh`
  - Runs `bundle -> audit_plan -> audit_collect -> audit_verify -> audit_report`.
  - Checks required audit output files and JSON validity.
- `audit_negative.sh`
  - Verifies expected failures for:
    - manifest mismatch
    - commit mismatch
    - missing approval
    - approval hash mismatch
    - missing postconditions in required rehearsal proof
- `inputs_gate.sh`
  - Verifies first-class inputs integrity gate behavior:
    - missing required inputs fail
    - mutated bundled inputs fail verify
    - coherence mismatch fails verify
    - external override fails apply
    - valid pinned inputs pass verify/apply and are recorded in apply evidence
    - mainnet rehearsal-proof gate remains enforced
- `postconditions_mode.sh`
  - Verifies postconditions mode behavior:
    - auto-mode happy path passes
    - missing `txs.json` auto-fails
    - failing `checks.path.json` auto-fails
    - manual mode remains compatible and requires explicit `POSTCONDITIONS_STATUS`
- `bundle_workflow_inputs.sh`
  - Verifies the scaffold CI bundle workflow shape for locked-input deploy lanes:
    - sepolia/mainnet deploy succeeds when valid `inputs_json` is supplied
    - required-input lane fails clearly when `inputs_json` is missing
    - CI-like bundle path writes `artifacts/<network>/current/inputs/inputs.<run_id>.json`
    - bundled `inputs.json` is pinned into `intent.json.inputs_sha256`
- `../ops/tests/test_lock_inputs.sh`
  - Verifies lock-inputs guardrails:
    - realistic string params pass
    - placeholder token rejection works
    - strict mode requires `PARAMS_SCHEMA`
    - Sepolia example-schema refusal and override behavior

## Usage
```bash
examples/scaffold/tests/audit_smoke.sh
examples/scaffold/tests/audit_negative.sh
examples/scaffold/tests/inputs_gate.sh
examples/scaffold/tests/postconditions_mode.sh
examples/scaffold/tests/bundle_workflow_inputs.sh
examples/scaffold/ops/tests/test_lock_inputs.sh
```
