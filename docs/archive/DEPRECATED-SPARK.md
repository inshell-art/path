# DEPRECATED SPARK

Status:
- removed from `main`
- archived for possible future restoration

## What it was

The deprecated spark model was the old reserved-mint branch inside `PathMinter`.

It included:
- `RESERVED_ROLE`
- `mintSparker(address to, bytes data)`
- `getReservedCap()`
- `getReservedRemaining()`
- constructor input `reservedCap`
- the split token-id rule:
  - public mint stream below `SPARK_BASE`
  - reserved mint stream at and above `SPARK_BASE`

## Why it was removed

PATH now treats `PathMinter` as a single public mint proxy.

The reserved/spark branch was removed so the active repo surface has:
- one mint stream
- one simpler constructor/config path
- no reserved-role supply branch
- no special token-id domain split

## Exact archive point

The exact pre-drop implementation is preserved in git tag:

- `archive/path-minter-spark-v1`

That tag is the real archive source of truth.
Use it instead of trying to reconstruct the feature from prose alone.

## Deprecated surface that was removed from `main`

Contract/API:
- `PathMinter.RESERVED_ROLE`
- `PathMinter.SPARK_BASE`
- `PathMinter.getReservedCap()`
- `PathMinter.getReservedRemaining()`
- `PathMinter.mintSparker(...)`
- `IPathMinter.getReservedCap()`
- `IPathMinter.getReservedRemaining()`
- `IPathMinter.mintSparker(...)`

Deploy/config:
- constructor param `reservedCap`
- deploy script/env/npm/config support for `reservedCap`
- release/export field `reserved_cap`

Tests/docs:
- reserved-role and reserved-cap tests
- reserved/public split documentation
- spark-specific rehearsal guidance

## If the feature is ever restored

Do not reimplement it from this note alone.

Use this sequence:
1. inspect tag `archive/path-minter-spark-v1`
2. restore the exact old contract/interface/tests/deploy/docs surface into a branch
3. adapt only what is intentionally changing
4. re-run compile/test/deploy-script/doc updates together

## Known pre-drop deployment context

The current repo historically produced at least one Sepolia deployment from the pre-drop model.
If you need to compare restored behavior against historical on-chain behavior, inspect the archived tag together with the recorded Sepolia deployment artifacts in local operator history.
