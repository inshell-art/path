# PulseAuction Open Time Spec

Status: `PROPOSED`

## 1. Objective

Replace relative launch delay (`startDelaySec`) in core auction semantics with an exact launch timestamp (`openTime`) suitable for mainnet announcement and verification.

## 2. Scope

In scope:
- `PulseAuction` launch-time input semantics.
- Deployment script input/precedence updates.
- Test and docs updates tied to launch-time behavior.

Out of scope:
- Curve math (`k`, `pts`, floor/anchor updates).
- Payment behavior (ETH/ERC20).
- Adapter settlement and epoch-to-token coupling.

## 3. Current Behavior (Baseline)

Current constructor sets:
- `openTime = uint64(block.timestamp) + startDelaySec`

Current bid gate:
- `require(block.timestamp >= openTime, "AUCTION_NOT_OPEN")`

References:
- `vendors/pulse/evm/src/PulseAuction.sol`
- `evm/scripts/deploy-local-eth.js`

## 4. Target Contract Behavior

### 4.1 Constructor Input

Change first constructor argument from `startDelaySec` to `openTime`.

Before:
- `constructor(uint64 startDelaySec, ...)`

After:
- `constructor(uint64 openTime_, ...)`

### 4.2 Storage Assignment

Set:
- `openTime = openTime_`

No addition with deployment timestamp.

### 4.3 Validation

Constructor must enforce:
- `openTime_ >= block.timestamp`

Optional strictness (recommended):
- `openTime_ > block.timestamp` on non-local networks is handled by deployment scripts, not contract logic.

### 4.4 Mutability

`openTime` remains immutable after deployment in v1 (no reschedule function).

### 4.5 Eventing

Add a constructor-time event:
- `event LaunchConfigured(uint64 indexed openTime, uint64 deployedAt);`

Emit once during deployment.

## 5. Deployment Script Spec

### 5.1 New Inputs

Add explicit timestamp input across surfaces:
- CLI: `--deploy-open-time`
- ENV: `DEPLOY_OPEN_TIME`
- npm config: `npm_config_deploy_open_time`
- params file key: `openTime`

### 5.2 Backward-Compatible Convenience

Keep `startDelaySec` as script-only convenience for local/testing.

If provided, derive:
- `openTime = latestBlock.timestamp + startDelaySec`, with a one-second minimum lead when delay is zero.

### 5.3 Resolution Rules

1. If `openTime` is provided, use it directly.
2. Else if `startDelaySec` is provided, derive `openTime`.
3. Else:
- Local/dev networks: default to current block timestamp.
- Non-local networks: fail with `OPEN_TIME_REQUIRED`.

Conflict rule:
- If both `openTime` and `startDelaySec` are set, fail with `AMBIGUOUS_LAUNCH_TIME`.

### 5.4 Deployment Artifact Fields

Include in deployment output JSON:
- `config.openTime` (unix seconds as string)
- `config.openTimeIso` (UTC ISO-8601)
- `config.openTimeSource` (`explicit` | `derived_delay` | `default_local_now`)

## 6. Documentation Requirements

Public launch wording must be:
- "Auction opens at `<UTC time>` and becomes active on the first block with `block.timestamp >= openTime`."

Document:
- Wall-clock vs block-time caveat.
- Conversion process from UTC schedule to unix seconds.
- Post-deploy verification step to read `openTime` on-chain.

## 7. Test Requirements

Contract/tests:
- Constructor stores exact `openTime`.
- Bid at `openTime - 1` reverts `AUCTION_NOT_OPEN`.
- Bid at `openTime` succeeds.

Script/tests:
- Explicit `openTime` path works.
- `startDelaySec` derivation path works.
- Conflict (`openTime` + `startDelaySec`) fails.
- Non-local missing both fails.
- Artifact contains `openTime`, `openTimeIso`, `openTimeSource`.

Regression:
- Existing integration tests pass after fixture/deploy helper migration.

## 8. Acceptance Criteria

1. Mainnet launch can be announced as one exact UTC timestamp before deployment.
2. On-chain `openTime` equals announced timestamp.
3. Launch gating behavior is unchanged except input semantics.
4. Local rehearsal remains convenient through derived delay in scripts.

## 9. Migration Notes

1. Contract constructor signature changes; deploy scripts and any callers must be updated atomically.
2. Existing deployed contracts are unaffected.
3. `startDelaySec` should be marked deprecated for production usage in docs.
