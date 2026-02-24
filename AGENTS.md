# AGENTS

## Overview
- PATH smart contracts with Solidity/EVM as the primary implementation.
- Legacy Cairo/Starknet code is preserved under `legacy/cairo/`.
- Primary workflows: Hardhat compile/test and local ETH deployment rehearsal.

## Project layout
- `evm/`: Solidity contracts, tests, and local deployment scripts.
- `legacy/cairo/contracts/`: legacy PathNFT, PathMinter, PathMinterAdapter, PathLook.
- `legacy/cairo/interfaces/`: legacy shared Cairo interfaces.
- `legacy/cairo/crates/`: legacy test support and e2e helpers.
- `contracts/`, `interfaces/`, `crates/`: compatibility symlinks to `legacy/cairo/*`.
- `vendors/`: vendored dependencies (pulse, pprf, step-curve).
- `scripts/`: root helpers (EVM local deploy/smoke/scenario + legacy Starknet scripts).
- `workbook/`: runbooks + devnet/sepolia workbooks.

## Install
- `pnpm install` (optional; for husky hooks only).
- Required tools (primary): `node`, `npm`.
- Required tools (legacy): `scarb`, `sncast`, `starknet-devnet`, `jq`, `python3`.

## Build / Lint / Format / Test
- EVM compile: `npm run evm:compile`.
- EVM tests: `npm run evm:test`.
- EVM deploy-cost estimate: `npm run evm:estimate:deploy:cost`.
- Legacy Cairo build: `scarb build` (root) or `scarb build -p path_nft` (per package).
- Legacy Cairo unit tests: `npm run cairo:test:unit`.
- Legacy Cairo full tests: `npm run cairo:test:full`.
- Legacy format/lint: `scarb fmt` and `scarb lint`.

## EVM local entrypoints
- Start local node: `npm run evm:node`
- Deploy: `npm run evm:deploy:local:eth` or `./scripts/deploy-eth-local.sh`
- Smoke: `npm run evm:smoke:local:eth` or `./scripts/smoke-eth-local.sh`
- Scenario: `npm run evm:scenario:local:eth` or `./scripts/scenario-eth-local.sh`

## Legacy devnet entrypoints
- Devnet runtime is managed in `../localnet` (see `../localnet/README.md`).
- Legacy devnet scripts live under `scripts/devnet/`.
- Devnet workbook lives under `workbook/`.

## Legacy Sepolia local deploy (no CI/CD)
- Create `scripts/.env.sepolia.local` with `RPC_URL`, `SNCAST_ACCOUNTS_FILE`, `SNCAST_ACCOUNTS_NAMESPACE`, and `DECLARE_PROFILE/DEPLOY_PROFILE`.
- Create `scripts/params.sepolia.local` with `PAYTOKEN`, `TREASURY`, and any constructor overrides.
- Optional: set `PPRF_ADDR` and `STEP_CURVE_ADDR` in `scripts/params.sepolia.local` to reuse existing glyph deployments.
- Declare: `npm run legacy:declare:sepolia`.
- Deploy: `npm run legacy:deploy:sepolia`.
- Configure roles: `npm run legacy:config:sepolia`.
- Verify wiring: `npm run legacy:verify:sepolia`.
- If using v0_10 RPC, the scripts use `scripts/sepolia_declare_v3.py` and `scripts/sepolia_invoke_v3.py` helpers for v3 transactions.
- Artifacts live under `output/sepolia/` (`classes.sepolia.json`, `addresses.sepolia.json`, `addresses.sepolia.env`, `deploy.params.sepolia.json`, and per-contract declare/deploy JSON logs).

## Definition of done
- Relevant builds/tests pass.
- For EVM changes: `npm run evm:compile` and `npm run evm:test`.
- For legacy Cairo changes: `scarb fmt` and `scarb lint` for touched packages.
- No unintended changes in `vendors/`, `output/`, or `workbook/` artifacts.
- Docs updated when interfaces or behavior change.

## Coding conventions
- Follow existing Solidity style in `evm/`; use explicit visibility and role checks.
- Follow existing Cairo style in `legacy/cairo/`; prefer `snake_case` names.
- Keep movement labels (`THOUGHT`, `WILL`, `AWA`) and constants consistent.
- Use `ByteArray` for string outputs and keep edits ASCII by default.

## Boundaries (do not touch unless asked)
- `vendors/` vendored code or submodules.
- `workbook/artifacts/*`, `output/*`, or `.accounts` secrets.
- Network credentials, keys, or deployment state.

## Security and leak-prevention rules
- Never introduce secrets into the repo.
- Do not add or modify code that includes any: private keys, seed phrases, mnemonics, service account JSON, API keys/tokens (RPC keys included), `.env` files, or `.pem`/`.key` files.
- Treat any `VITE_*` env vars as public (baked into client JS). Never store secrets in them.
- Always run a leak scan before committing:
  - `git diff --staged` and manually inspect for secrets.
  - `gitleaks detect --no-git --redact` (or repo’s chosen scanner).
- If any potential secret is detected, stop and remove it; do not “mask” it.
- Do not print sensitive values in CI logs (avoid `echo $TOKEN`, `printenv`, verbose debug logs with headers/keys).
- Avoid logging full RPC URLs if they include keys.
- No new third-party telemetry by default (no analytics, session replay, fingerprinting, or new error trackers unless explicitly requested).
- If error tracking exists, ensure it does not capture wallet addresses, RPC payloads, or user identifiers.
- Protect deployment and workflow integrity: do not weaken branch protections in docs/instructions; pin GitHub Action versions where possible; prefer least-privilege tokens; avoid long-lived credentials.
- Remove debug artifacts before committing (no debug-only endpoints, “test wallets”, or localhost RPC defaults in production configs).
- Security PR checklist (must pass):
  - No secrets in diff.
  - No new telemetry.
  - No new external endpoints without clear reason.
  - Build succeeds with clean env.
  - Any new config is documented and safe to be public.

## Ops Agent Response Contract (MUST)

This section applies to any agent interacting with ops steps/tools in this repo.

### Trigger rule (unambiguous)
If the user:
- asks to run any ops tool/step (`ops/tools/*.sh`, `make -C ops ...`, or workflow steps like `bundle`, `verify`, `approve`, `apply`, `postconditions`), or
- asks what happened / what a step does / what was run / to show output for any ops step,
then the agent response MUST be in this order:
- A) Minimal Evidence Pack
- B) Common Answer

### Minimal Evidence Pack (mandatory fields)
One short line per field by default.
1. Claim + trust tier label (`PROPOSED` | `VERIFIED` | `PINNED` | `ON_CHAIN`)
2. Source-of-truth scripts + repo pin (`git rev-parse HEAD` or tag)
3. Exact reproduce command(s)
4. Observed output (and/or expected output if not run) + exit code
5. Files read/produced (paths)
6. Stop conditions (what would make it fail/refuse)
7. What the evidence does not prove (scope limits)

### Common Answer
After the Minimal Evidence Pack, provide the normal concise answer.

### Default behavior
- Use minimal/compact response by default.
- Expand only when the user asks (for example: `expand evidence`).
- Do not paste long command output dumps unless asked.

Rules:
- Never present `PROPOSED` as `VERIFIED`.
- If you did not run a command, say so and provide expected output (do not claim observed output).

### Short example (required order)
`Minimal Evidence Pack`
- `Claim:` `VERIFIED` bundle check passed.
- `Source:` `ops/tools/verify_bundle.sh`, repo pin `<sha>`.
- `Reproduce:` `NETWORK=devnet RUN_ID=<id> ops/tools/verify_bundle.sh`.
- `Output:` observed `Bundle verified ...`, exit `0`.
- `Files:` read `bundles/devnet/<id>/*`, produced none.
- `Stop:` missing manifest/hash mismatch/commit mismatch.
- `Limits:` does not prove semantic safety.

`Common Answer`
- Verify step succeeded for `RUN_ID=<id>`.
