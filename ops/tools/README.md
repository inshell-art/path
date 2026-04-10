# Ops tools (stubs)

These scripts are placeholders. Replace them with your repo's real commands.

Expected behavior by script:
- `bundle.sh` creates `run.json`, `intent.json`, `checks.json`, optional `checks.path.json` (devnet PATH rehearsal), and `bundle_manifest.json`.
- `verify_bundle.sh` verifies manifest hashes, git commit, and policy compatibility. For Sepolia/Mainnet deploy lanes, it regenerates predeploy PATH checks locally when the bundle intentionally omits `checks.path.json`, and it requires Signing OS context (`SIGNING_OS=1` + local marker file).
- `approve_bundle.sh` records human approval tied to the bundle hash. Sepolia/Mainnet deploy approval requires Signing OS context (`SIGNING_OS=1` + local marker file).
- `apply_bundle.sh` executes the approved bundle in signing context only (deploy lane runs the configured EVM deploy command). Sepolia/Mainnet deploy apply expects explicit keystore env inputs (`<NET>_DEPLOY_KEYSTORE_JSON` + password env/file), requires Signing OS context (`SIGNING_OS=1` + local marker file), and refuses pre-set raw `<NET>_PRIVATE_KEY`.
- `postconditions.sh` records post-apply verification and writes `postconditions.json` (default `POSTCONDITIONS_MODE=auto`; optional `POSTCONDITIONS_MODE=manual` with explicit `POSTCONDITIONS_STATUS`). Sepolia/Mainnet deploy postconditions requires Signing OS context (`SIGNING_OS=1` + local marker file).
- `generate_path_checks.sh` probes PATH readiness (devnet/sepolia/mainnet) and writes `checks.path.json` with `required_checks` and `path_invariants`.
- `dispatch_ci_bundle.sh` dispatches the remote `Ops Bundle (CI)` workflow using the locked inputs wrapper file and prints the resulting GitHub run id when available.
- `fetch_ci_bundle.sh` downloads a remote CI bundle artifact. Preferred Signing OS handoff is `NETWORK + RUN_ID`; the helper resolves the matching GitHub Actions run from exact artifact name `ops-bundle-<network>-<run_id>`, derives the bundle run id from `run.json`, places it under `bundles/<network>/<run_id>/`, and sanity-checks the downloaded `run.json`.
- `check_policy_initialization.sh` reports policy initialization gaps such as missing signer alias map entries, unresolved fee-policy placeholders, and non-allowlisted configured RPC hosts for `sepolia` and `mainnet`; with no `LANE` it checks all lanes, and with `LANE=<lane>` it checks only the targeted lane for serious-run preflight.
- `preflight_devos.sh` is the integrated serious-network Dev OS preflight for `sepolia`/`mainnet`; it checks toolchain, clean tracked git state, lane presence, the intended Signing OS RPC URL against policy allowlists, policy initialization, deploy params presence, full secret scan, compile/test, and optional GitHub auth.
- `preflight_signingos.sh` is the integrated serious-network Signing OS preflight for `sepolia`/`mainnet`; it checks toolchain, clean tracked git state, network env + marker presence, policy initialization, deploy keystore/password presence, signer binding against policy, and optional GitHub auth.
- `export_fe_release.sh` exports a public-safe frontend handoff bundle from a completed deploy run under `artifacts/<network>/current/fe-release/`; it emits a release manifest, flat addresses file, ABI JSON files, checksums, and an env hint containing `VITE_PULSE_AUCTION_DEPLOY_BLOCK`, and it requires a passing `postconditions.json` plus an RPC URL to resolve deploy block numbers.
- `scan_secrets_staged.sh` materializes the staged git snapshot into a temporary directory and runs `gitleaks --no-git` against that snapshot; this is the hook-safe local secret scan for `pre-commit`.
- `audit_plan.sh` creates `audit_plan.json` with the exact ordered `RUN_ID` scope, explicit lane scope, and the lane-derived control set.
- `audit_collect.sh` copies read-only evidence into `audits/<network>/<audit_id>/runs/<run_id>/`, snapshots `policy.json` at each run's pinned commit, writes `audit_manifest.json`, and also emits the compatibility alias `audit_evidence_index.json`.
- `audit_verify.sh` re-hashes collected evidence, verifies plan/manifest/run coherence, and writes `audit_verify.json` plus the compatibility alias `audit_verification.json`.
- `audit_report.sh` generates `audit_report.md`, `audit_report.json`, and `findings.json`.
- `audit_signoff.sh` writes `audit_signoff.json` plus the compatibility alias `signoff.json`, and refuses signoff unless verify/report both passed and the frozen evidence set is unchanged.
- `lint_secret_snippets.sh` enforces no raw private-key snippets in docs/runbooks for `sepolia`/`mainnet` (devnet skipped).

Deploy-side CLI write operations must use keystore mode only for the deploy lane. Do not use accounts-file signing.
For PATH, final ADMIN / TREASURY custody is no-Safe and Ledger-only. The Signing OS may hold a deploy-only keystore for deploy lanes, but it is not a final-custody software signer.
For serious Sepolia/Mainnet flow, Dev OS prepares and dispatches bundles only; Signing OS is the only place that should run deploy-side `verify/approve/apply/postconditions`.
Signing OS network use is bounded-online only: Wi-Fi off by default, on only for trusted maintenance or exact run tasks.

Optional bundle tooling (reference implementations):
- `bundle.sh`, `verify_bundle.sh`, `approve_bundle.sh`, `apply_bundle.sh`

Optional audit tooling (reference implementations):
- `audit_plan.sh`, `audit_collect.sh`, `audit_verify.sh`, `audit_report.sh`, `audit_signoff.sh`

Review and adapt these scripts before use.

Public-safe boundary:
- keep real env files, keystores, and password files outside git under `~/.opsec/...`
- keep live bundles, artifacts, output, and audits local/generated by default
- only commit curated `*.example.*` or `*.redacted.*` fixtures

Audit boundary:
- audit is evidence-only and sits after `postconditions`
- audit groups completed `RUN_ID`s under one `AUDIT_ID`
- audit plan must state the exact run list
- multi-lane audits require explicit `ALLOWED_LANES`
- audit collect refuses secret-bearing files and snapshots per-run policy at the pinned commit
- audit signoff binds to exact plan, manifest, verify, and report hashes

Locked inputs flow:
- run `lock_inputs.sh` to create the run-scoped locked inputs wrapper
- pass that file to `bundle.sh` via `LOCKED_INPUTS_FILE`
- deprecated alias: `INPUTS_TEMPLATE`
