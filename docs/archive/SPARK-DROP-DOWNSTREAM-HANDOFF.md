# Spark Drop Downstream Handoff

## Status

Spark/reserved mint logic has been removed from the active `path/` repo surface.

- Removal commit: `070ee8342833a4249027146d3ed61cf555e4762f`
- Archive tag: `archive/path-minter-spark-v1`
- Archive note: [DEPRECATED-SPARK.md](/Users/bigu/Projects/path/docs/archive/DEPRECATED-SPARK.md)

The archive tag is the exact restoration source. This handoff note is only the downstream update map.

## Removed active surface

The following active PATH surface was removed:

- `PathMinter.RESERVED_ROLE`
- `PathMinter.SPARK_BASE`
- `PathMinter.getReservedCap()`
- `PathMinter.getReservedRemaining()`
- `PathMinter.mintSparker(...)`
- `IPathMinter.getReservedCap()`
- `IPathMinter.getReservedRemaining()`
- `IPathMinter.mintSparker(...)`
- constructor param `reservedCap`
- release/export field `reserved_cap`

The active `PathMinter` model is now public sequential minting only.

## PATH artifacts to use as source of truth

Use these files when updating downstream consumers:

- contract surface:
  - [PathMinter.sol](/Users/bigu/Projects/path/evm/src/PathMinter.sol)
  - [IPathMinter.sol](/Users/bigu/Projects/path/evm/src/interfaces/IPathMinter.sol)
- deploy/config surface:
  - [deploy-local-eth.js](/Users/bigu/Projects/path/evm/scripts/deploy-local-eth.js)
  - [path.constructor_params.schema.json](/Users/bigu/Projects/path/schemas/path.constructor_params.schema.json)
  - [params.constructor.example.json](/Users/bigu/Projects/path/ops/params.constructor.example.json)
- release/export surface:
  - [export_fe_release.sh](/Users/bigu/Projects/path/ops/tools/export_fe_release.sh)
  - [path.protocol_release.schema.json](/Users/bigu/Projects/path/schemas/path.protocol_release.schema.json)
- regression evidence:
  - [pathMinter.behavior.test.js](/Users/bigu/Projects/path/evm/test/pathMinter.behavior.test.js)

## Required downstream interpretation

Downstream repos should now assume:

- no reserved mint branch
- no spark-specific token-ID domain
- no `reservedCap` constructor/config input
- no `reserved_cap` release-manifest field
- no reserved-role or reserved-remaining inspection path

## `inshell.art` follow-up

`inshell.art` was not modified in this pass.

Target follow-up there:

1. confirm no frontend logic expects:
   - `mintSparker`
   - `SPARK_BASE`
   - reserved token classification by high token ID
   - `reserved_cap` in exported release data
2. confirm ABI/type snapshots are aligned to `path/` commit `070ee83`
3. confirm any contract package import or local address/ABI sync does not preserve the deleted minter interface

Suggested validation:

```bash
rg -n "reservedCap|reserved_cap|RESERVED_ROLE|SPARK_BASE|mintSparker|getReservedCap|getReservedRemaining|spark|Sparker" .
```

## `signing-os-ops` follow-up

`signing-os-ops` was not modified in this pass.

Important: generated PATH pack content there is now stale if it was built from pre-drop PATH state.

Target follow-up there:

1. rebuild or refresh any vendored/generated PATH run bundle from `path/` commit `070ee83` or later
2. remove stale PATH pack references to:
   - `reservedCap`
   - `reserved_cap`
   - `RESERVED_ROLE`
   - `SPARK_BASE`
   - `mintSparker`
   - `getReservedCap`
   - `getReservedRemaining`
3. ensure any copied schema, deploy helper, or ABI snapshot matches current PATH surface

Suggested validation:

```bash
rg -n "reservedCap|reserved_cap|RESERVED_ROLE|SPARK_BASE|mintSparker|getReservedCap|getReservedRemaining|spark|Sparker" .
```

## Restoration rule

If spark/reserved minting is ever brought back:

1. inspect tag `archive/path-minter-spark-v1`
2. restore from exact code/tests first
3. then adapt for current repo shape

Do not reimplement from prose alone.

## Minimal handoff set

If another repo owner only needs the minimum reference set, send:

1. removal commit: `070ee8342833a4249027146d3ed61cf555e4762f`
2. archive tag: `archive/path-minter-spark-v1`
3. archive note: [DEPRECATED-SPARK.md](/Users/bigu/Projects/path/docs/archive/DEPRECATED-SPARK.md)
4. contract interface refs:
   - [PathMinter.sol](/Users/bigu/Projects/path/evm/src/PathMinter.sol)
   - [IPathMinter.sol](/Users/bigu/Projects/path/evm/src/interfaces/IPathMinter.sol)
5. export/schema refs:
   - [path.constructor_params.schema.json](/Users/bigu/Projects/path/schemas/path.constructor_params.schema.json)
   - [path.protocol_release.schema.json](/Users/bigu/Projects/path/schemas/path.protocol_release.schema.json)
