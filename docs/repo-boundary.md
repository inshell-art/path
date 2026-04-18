# PATH Repo Boundary

This document defines what `path/` owns, what it does not own, and how it interfaces with `signing-os-ops/`.

## Purpose

`path/` is the canonical repo for PATH protocol code and PATH-specific operations.

Use this repo for:
- Solidity contracts and tests
- PATH deploy/rehearsal parameters
- PATH lane policy and signer alias mapping
- PATH bundle creation and audit flow
- PATH runbooks for Dev OS and Signing OS execution of the PATH lane
- public-safe deployment artifacts meant for PATH consumers such as frontend integration

## Owns

`path/` owns:
- `evm/`
- `ops/`
- `workbook/ops/`
- PATH-specific `docs/`
- PATH-specific generated/public-safe artifacts such as:
  - `bundles/`
  - `audits/`
  - `artifacts/<network>/current/fe-release/`

PATH-specific means:
- constructor params
- `NETWORK`, `RUN_ID`, and audit ids
- policy allowlists and signer alias maps
- bundle manifests and locked inputs
- PATH contract addresses, ABIs, and release metadata
- PATH acceptance criteria for `verify`, `approve`, `apply`, `postconditions`, and audit

## Does Not Own

`path/` does not own the generic Signing OS operator environment.

Do not make `path/` the source of truth for:
- Signing OS boot hygiene
- Signing OS Wi-Fi policy implementation details
- generic Ledger/adapter verification procedures
- transfer-pack build mechanics
- bridge transport implementation
- generic host maintenance workflow
- generic serious-run reset/preflight procedure for the Signing OS host

Those belong in `signing-os-ops/`.

## Interface To `signing-os-ops/`

`path/` consumes a Signing OS operator capability provided by `signing-os-ops/`.

`path/` assumes that `signing-os-ops/` provides:
- a transfer pack
- a bounded bridge procedure
- a serious-run baseline/preflight on Signing OS
- host-side verification and maintenance discipline

`path/` provides the PATH-specific inputs that must move through that operator environment:
- public handoff files
- private runtime handoff files
- PATH bundle fetch/run instructions
- PATH-specific env shape and lane commands

## Stable Handoff Contract

For the normal Signing OS path, `path/` must ship one pinned
`PATH-RUN-BUNDLE/` alongside `Signing-OS-Transfer-Pack/`.

Minimum required contents:
- `RUNBOOK.txt`
- `MANIFEST.json`
- `SHA256SUMS.txt`
- `CONTEXT.json`
- `SIGNER.json`
- `EXPECTED.json`
- `WORKSPACE/`
- `bin/`

Minimum machine-readable fields that must cross the boundary in that bundle:
- `MANIFEST.json`
  - `bundle_id`
  - `built_at_utc`
  - `source_repo`
  - `source_commit`
  - `source_commit_dirty`
  - `protocol`
  - `chain_id`
  - `rpc_host`
  - `signer_alias`
  - `expected_address`
  - `entrypoints.verify`
  - `entrypoints.approve`
  - `entrypoints.apply`
  - `entrypoints.postconditions`
- `CONTEXT.json`
  - `action`
  - `description`
  - `chain_id`
  - `rpc_host`
  - `contracts`
  - `params`
  - `expected_outputs`
- `SIGNER.json`
  - `signer_alias`
  - `expected_address`
  - `hd_path`
  - `ledger_label`
  - `role_description`
- `EXPECTED.json`
  - `preconditions`
  - `postconditions`
  - `must_match`
  - `forbidden`

PATH-owned protocol data may include additional fields such as:
- constructor params
- `NETWORK`
- `RUN_ID`
- audit ids
- policy allowlists
- signer alias maps
- locked inputs
- PATH contract addresses
- ABIs
- release metadata

Those PATH-specific values may travel inside `PATH-RUN-BUNDLE/`, but they do
not become `signing-os-ops/` source of truth just because they cross the
artifact boundary.

Execution contract for the bundle:
- the artifact bridge is artifact-only, not a shared workspace
- Signing OS does **not** `git pull` in the normal path
- `bin/verify`, `bin/approve`, `bin/apply`, and `bin/postconditions` are the
  preferred entrypoints
- each entrypoint should behave like one operator-facing command
- each entrypoint should write one top-level run dir
- each entrypoint should write `SUMMARY.txt`
- each entrypoint should exit `0` on pass and non-zero on fail

## Operational Split

Dev OS side in `path/`:
- compile/test
- policy edits
- `ops:lock-inputs`
- `ops:dispatch-bundle`
- PATH handoff file preparation

Signing OS side in `path/`:
- `ops:preflight:signingos`
- `ops:fetch-bundle`
- pinned checkout or pinned handoff import
- `ops:verify`
- `ops:approve`
- `ops:apply`
- `ops:postconditions`
- PATH audit

Signing OS host safety around those steps is delegated to `signing-os-ops/`.

## Change-Order Rule

If the host/operator mechanism changes first:
1. update `signing-os-ops/`
2. then adapt `path/` handoff/runbooks to the new operator contract

If PATH deploy semantics change first:
1. update `path/`
2. update `signing-os-ops/` only if the host procedure or operator pack must change

## Agent Roles

Use a distinct `path` agent role for this repo.

That agent should own:
- protocol code
- PATH ops runbooks
- PATH deployment parameters
- PATH release artifacts for downstream consumers

That agent should treat `signing-os-ops/` as an external operator-kit dependency, not as an implementation dump for PATH-specific logic.
