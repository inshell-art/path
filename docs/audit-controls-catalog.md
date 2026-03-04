# Audit Controls Catalog (v1)

This catalog maps audit controls to lane artifacts and verifier behavior.

## Controls
- `AUD-001` Bundle integrity hash verified.
- `AUD-002` `run.json` commit pin matches expected code state.
- `AUD-003` Lane policy file exists and lane id is valid.
- `AUD-004` Approval hash matches bundle hash.
- `AUD-005` Apply used approved bundle only (no ad-hoc args).
- `AUD-006` Postconditions present and status recorded.
- `AUD-007` Rehearsal proof gate respected when required.
- `AUD-008` Signer allowlist and lane signer mapping respected.
- `AUD-009` Network and chain consistency across artifacts.
- `AUD-010` Secrets hygiene evidence recorded (no leaks in run-scoped logs/diffs).
- `AUD-011` Inputs wrapper pinned in bundle and enforced at apply.

## Evidence Mapping (default)
- `AUD-001`: `bundle_manifest.json`, immutable files listed inside manifest
- `AUD-002`: `run.json.git_commit`, current repo commit
- `AUD-003`: policy file (`ops/policy/*`) and `run.json.lane`
- `AUD-004`: `approval.json.bundle_hash`, `bundle_manifest.json.bundle_hash`
- `AUD-005`: apply script invocation policy and bundle/approval binding
- `AUD-006`: `postconditions.json`
- `AUD-007`: lane gates + proof bundle presence (`txs.json`, `postconditions.json`)
- `AUD-008`: policy signer allowlist + run signer alias (if present)
- `AUD-009`: `run.json.network`, plan network, bundle path network
- `AUD-010`: secret scan output or explicit run-scoped hygiene notes
- `AUD-011`: `inputs.json`, `intent.json.inputs_sha256`, `bundle_manifest.json` immutable entry for `inputs.json`, `approval.json.inputs_sha256`, `txs.json.inputs_*`

Each control result must include a claim tier:
- `VERIFIED` for direct deterministic checks
- `INFERRED` for indirect claims/heuristics

## Severity Defaults
- `AUD-001`: high
- `AUD-002`: high
- `AUD-003`: medium
- `AUD-004`: high
- `AUD-005`: medium
- `AUD-006`: medium
- `AUD-007`: high
- `AUD-008`: high
- `AUD-009`: medium
- `AUD-010`: critical
- `AUD-011`: high
