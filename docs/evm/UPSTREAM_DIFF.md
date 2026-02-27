# PulseAuction Upstream Diff

This file tracks how `PulseAuction` is sourced from upstream in this repo.

## Upstream Pin

- Upstream repo: `git@github.com:inshell-art/pulse.git`
- Vendored reference path: `vendors/pulse/evm/src/PulseAuction.sol`
- Vendored commit pin: `8a3086433405f44e9230562e89c36758001f06b8`

## Policy

1. Deployable contracts remain in `evm/src`.
2. `evm/src/PulseAuction.sol` is a symlink to the vendored upstream source.
3. Do not edit Pulse auction logic in this repo; update by bumping `vendors/pulse`.
4. Material deltas from upstream (if ever introduced) must be documented here.
5. Upstream reference stays in `vendors/pulse` for side-by-side comparison.

## Current State

1. `evm/src/PulseAuction.sol` points to:
- `../../vendors/pulse/evm/src/PulseAuction.sol`

2. Local deltas in Pulse auction logic:
- None.

3. Note on adapter interface:
- PATH keeps local `IPulseAdapter` minimal for local contracts (`settle(...)` only).
- `PulseAuction` behavior itself is sourced from upstream vendor code.

## How To Compare

Use:

```bash
git -C vendors/pulse rev-parse HEAD
diff -u vendors/pulse/evm/src/PulseAuction.sol evm/src/PulseAuction.sol
```
