# Scaffold audit tests

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

## Usage
```bash
examples/scaffold/tests/audit_smoke.sh
examples/scaffold/tests/audit_negative.sh
examples/scaffold/tests/inputs_gate.sh
```
