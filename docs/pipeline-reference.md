# Pipeline Reference (CI → Local CD)

This is a minimal “stupid steps” reference for the deterministic pipeline.
For trust tiers and claim-verification format, see `docs/agent-trust-model.md`.

## Inputs
- `NETWORK` (`devnet` | `sepolia` | `mainnet`)
- `LANE` (`observe` | `plan` | `deploy` | `handoff` | `govern` | `treasury` | `operate` | `emergency`)
- `RUN_ID` (string; CI can default to `YYYYMMDDTHHMMSSZ-<short_sha>`)
- `AUDIT_ID` (string; for periodic/release audit runs)
- Optional: `BUNDLE_PATH` (local path to a bundle directory)
- Optional for lanes with `required_inputs`: `INPUTS_TEMPLATE` (path to locked inputs wrapper JSON)
- Required before bundling high-entropy params: `INPUT_FILE` (for `ops/tools/lock_inputs.sh`)
- Optional (mainnet only): `REHEARSAL_PROOF_RUN_ID` (run id of the rehearsal proof bundle)
- Backward-compatible proof env fallback: `DEVNET_PROOF_RUN_ID`, then `SEPOLIA_PROOF_RUN_ID`

## Outputs
- Bundle directory: `bundles/<network>/<run_id>/`
- Lanes with required inputs: bundled `inputs.json`
- Post-apply evidence:
  - `txs.json`
  - `snapshots/*`
  - `postconditions.json`

## Remote CI (plan + checks only)
1. Checkout repo (pinned action SHA).
2. Build/test (read-only).
3. Generate bundle:
   - for lanes with `required_inputs`, run `ops/tools/lock_inputs.sh` first and pass `INPUTS_TEMPLATE=<locked_wrapper_path>`
   - `run.json` (includes git SHA)
   - `intent.json` (EVM call or Safe payload)
   - `checks.json` (read/sim only; includes bytecode/proxy checks for writes)
   - `inputs.json` for lanes that declare `required_inputs` (Sepolia/Mainnet deploy default)
   - `bundle_manifest.json` (hashes immutable files)
4. Upload bundle artifact.

## Local CD (Signing OS only)
1. Pull bundle from AIRLOCK into `bundles/<network>/<run_id>/`.
2. Verify bundle:
   - manifest hashes match immutable files
   - `run.json` commit matches checkout
   - policy contains the lane
   - inputs pinning/coherence passes for lanes with `required_inputs`
3. Approve bundle:
   - record approval tied to `bundle_hash`
   - include `inputs_sha256` binding when `inputs.json` is present
   - typed phrase includes network + lane + hash suffix
4. Apply bundle (requires `SIGNING_OS=1`):
   - refuses on dirty repo
   - refuses on manifest mismatch
   - refuses if approval missing
   - refuses if policy requires rehearsal proof and it’s missing
   - enforces policy fee limits (including EIP-1559 bounds where configured)
   - for lanes with required inputs, sets `INPUTS_FILE` to bundled `inputs.json`
   - rejects mismatched external `INPUTS_FILE` override
   - no manual calldata/addresses at apply time
   - no LLM calls during apply

5. Postconditions:
   - Run `ops/tools/postconditions.sh` to record on-chain verification.
   - Set `POSTCONDITIONS_STATUS=pass` after verification.
   - Persist `txs.json`, `snapshots/*`, and `postconditions.json`.

6. Periodic/release audit (recommended):
   - `ops/tools/audit_plan.sh`
   - `ops/tools/audit_collect.sh`
   - `ops/tools/audit_verify.sh`
   - `ops/tools/audit_report.sh`
   - `make -C ops audit-gate NETWORK=<network> AUDIT_ID=<audit_id>` for release gating
   - optional `ops/tools/audit_signoff.sh`

Note: mainnet write lanes default to:
- `gates.require_rehearsal_proof: true`
- `gates.rehearsal_proof_network: "devnet"`

Downstreams may explicitly set `gates.require_rehearsal_proof: false` per lane if they consciously relax the gate.

## CI hardening defaults
- Pin GitHub Actions to commit SHAs.
- Least privilege `GITHUB_TOKEN` permissions.
- No secrets in CI for public repos.
- Avoid workflows that run on fork PRs with write permissions.
