# DEPLOY-SUPERVISOR PATH release-clean handback

Date: 2026-08-21

Status: the verified PATH integrated deployment-campaign implementation was
selectively separated from an unrelated dirty worktree and committed locally as
one review-scoped change. Trust tier remains `VERIFIED`; it is not `PINNED` or
`ON_CHAIN` and grants no deployment or signing authority.

The commit was created from parent
`085cfc084b0e568740e0da639e968eb535f7e5c8`. The exact resulting commit and tree
identities are reported by:

```bash
git show -s --format='commit=%H%ntree=%T%nparent=%P%nsubject=%s' HEAD
```

The resulting commit hash cannot be embedded in its own tree without changing
that hash. The supervisor handoff carrying this document records both identities
verbatim after commit creation.

## Release scope

The commit contains only campaign-attributable code, schemas, descriptors,
examples, tests, ops integration, package entrypoints, repository-boundary
documentation, and durable handbacks.

Tracked files with campaign-only diffs:

- `docs/repo-boundary.md`
- `evm/package.json`
- `ops/policy/lane.devnet.example.json`
- `ops/policy/lane.devnet.json`
- `ops/policy/lane.mainnet.example.json`
- `ops/policy/lane.mainnet.json`
- `ops/policy/lane.sepolia.example.json`
- `ops/policy/lane.sepolia.json`
- `ops/tools/README.md`
- `ops/tools/apply_bundle.sh`
- `ops/tools/bundle.sh`
- `ops/tools/generate_path_checks.sh`
- `ops/tools/lock_inputs.sh`
- `ops/tools/postconditions.sh`
- `package.json`

New campaign files:

- `docs/ops/DEPLOY_SUPERVISOR_PATH_HAND_BACK_20260821.md`
- `docs/ops/DEPLOY_SUPERVISOR_PATH_RELEASE_CLEAN_HAND_BACK_20260821.md`
- `docs/ops/path-thought-deployment-campaign-refactor-report-2026-08-21.md`
- `docs/ops/path-thought-integrated-deployment-campaign-handback-2026-08-21.md`
- `evm/scripts/check-path-campaign-state.js`
- `evm/scripts/deploy-campaign-phase-a.js`
- `evm/scripts/deploy-campaign-phase-b.js`
- `evm/scripts/lib/path-campaign.mjs`
- `evm/scripts/prepare-path-campaign-devnet-dependencies.js`
- `evm/test/pathCampaign.behavior.test.js`
- `ops/campaign/README.md`
- `ops/campaign/examples/path-phase-a-checkpoint.example.json`
- `ops/campaign/examples/path-phase-a-params.example.json`
- `ops/campaign/examples/path-phase-a-receipt.example.json`
- `ops/campaign/examples/path-phase-b-checkpoint.example.json`
- `ops/campaign/examples/path-phase-b-config.example.json`
- `ops/campaign/examples/path-phase-b-final-receipt.example.json`
- `ops/campaign/path-a/CAMPAIGN-PHASE.json`
- `ops/campaign/path-a/bin/execute`
- `ops/campaign/path-a/bin/postconditions`
- `ops/campaign/path-a/bin/preflight`
- `ops/campaign/path-a/bin/resume`
- `ops/campaign/path-a/bin/verify-checkpoint`
- `ops/campaign/path-b/CAMPAIGN-PHASE.json`
- `ops/campaign/path-b/bin/execute`
- `ops/campaign/path-b/bin/postconditions`
- `ops/campaign/path-b/bin/preflight`
- `ops/campaign/path-b/bin/resume`
- `ops/campaign/path-b/bin/verify-checkpoint`
- `ops/tests/path_campaign.sh`
- `ops/tests/path_campaign_e2e.sh`
- `ops/tests/path_campaign_interop.mjs`
- `ops/tests/synthetic_path_campaign_receipts.mjs`
- `ops/tools/generate_path_campaign_phase_descriptor.mjs`
- `ops/tools/path_campaign.mjs`
- `ops/tools/path_campaign_protocol.mjs`
- `schemas/path.campaign.phase_a_checkpoint.schema.json`
- `schemas/path.campaign.phase_a_params.schema.json`
- `schemas/path.campaign.phase_a_receipt.schema.json`
- `schemas/path.campaign.phase_b_checkpoint.schema.json`
- `schemas/path.campaign.phase_b_final_receipt.schema.json`
- `schemas/path.campaign.phase_b_params.schema.json`
- `schemas/path.campaign.thought_receipt.schema.json`
- `schemas/protocol-receipt-envelope.v1.schema.json`

No campaign transient output was retained. The pure synthetic tests and bundle
regression used temporary directories and cleaned them on exit. Durable tests,
examples, descriptors, and handbacks were intentionally retained.

## Explicit exclusions

The release commit excludes all unrelated work, including `AGENTS.md`,
`INBOX.md`, renderer/color changes, Solidity and ABI/preview changes, frontend
handbacks, `marketplace-preview/`, and other user-owned worktree state. No
excluded file was reverted or rewritten during cleanup.

## Verification

All final release-clean checks exited `0`:

- strict Node syntax checks for campaign libraries, deploy/check scripts,
  production protocol entrypoints, descriptor generator, and synthetic harness;
- Bash syntax checks for campaign and touched ops entrypoints;
- JSON parsing for all campaign schemas, examples, descriptors, and touched lane
  policy files;
- exact OPS envelope schema parity and exact THOUGHT owner-schema parity;
- descriptor regeneration byte comparison for PATH-A and PATH-B;
- validation of both descriptors with the actual generic Signing OS
  `validate_descriptor` implementation;
- `node --test ops/tests/path_campaign_interop.mjs`: 6 passing, including the
  true staged THOUGHT-harness raw-byte handoff and strict JCS integer subset;
- `./ops/tests/path_campaign.sh`: envelope, exact owner payload, locked-input,
  schema, descriptor, tamper, and negative checks passed;
- `npm run ops:test:safe-treasury`: existing file-based bundle/input-lock
  regression passed without RPC or deployment;
- scoped `gitleaks detect --no-git --redact` scans passed for campaign code,
  schemas, ops, and handbacks;
- staged public-safe, whitespace, and diff review gates passed before commit.

Frozen schema digests at cleanup time:

```text
c74f493ba55326efcaca4be3ede6b33da319e2e6ae636817e1cb91aec550cccc  protocol-receipt-envelope.v1.schema.json
4db5fae69c93432b43b340ecf24078efdb5933c85094a23b70550789e49701d1  thought-deployment-receipt.v1.schema.json
```

The earlier Hardhat compile/full test/campaign unit and disposable-local-devnet
E2E evidence remains recorded in
`docs/ops/DEPLOY_SUPERVISOR_PATH_HAND_BACK_20260821.md`. It was not rerun during
release cleanup. The final staged supervisor rehearsal was pure file-based,
with no signer, transaction, deployment entrypoint, RPC, or broadcast.

## Remaining release gates

- The commit is local and review-scoped; no push, merge, PR, tag, or immutable
  release bundle was created.
- OPS must re-check schema parity and pin the reviewed commit/bundle digest at
  campaign assembly time.
- Signing OS/OPS still owns the exact three-bundle manifest, approvals,
  append-only receipt transport, and final orchestration evidence.
- Signer approval, credentials, chain deployment, auction authorization, and
  frontend exposure remain explicitly outside this handback.
