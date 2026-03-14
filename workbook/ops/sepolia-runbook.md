# Sepolia runbook

See also:
- [Signing OS runbook](signing-os-runbook.md) for the serious split between Dev OS, CI, and Signing OS.

## A) Preflight checklist
- correct network selected (`sepolia`)
- constructor params file exists at `~/.opsec/path/params.sepolia.deploy.json`
- `ops/policy/lane.sepolia.json` placeholders resolved (RPC allowlist, signer map, fee policy)
- tracked git tree clean before bundle
- Signing OS is prepared separately with:
  - its own `SEPOLIA_RPC_URL`
  - its own keystore/password refs
  - its own `SIGNING_OS_MARKER_FILE`
- Dev OS does not need Sepolia signing env for `lock-inputs` or `dispatch-bundle`

## B) Execute deploy lane
```bash
mkdir -p ~/.opsec/path
$EDITOR ~/.opsec/path/params.sepolia.deploy.json

# Example params file:
# {
#   "name": "PATH NFT",
#   "symbol": "PATH",
#   "baseUri": "",
#   # Set exactly one of openTime or startDelaySec.
#   "startDelaySec": "600",
#   "k": "600",
#   "genesisPrice": "1000",
#   "genesisFloor": "900",
#   "pts": "1",
#   "firstPublicId": "1",
#   "epochBase": "1",
#   "reservedCap": "3",
#   "paymentToken": "0x0000000000000000000000000000000000000000",
#   "treasury": "0xYourTreasuryAddress"
# }
chmod 600 ~/.opsec/path/params.sepolia.deploy.json

npm run evm:compile
npm run evm:test

RUN_ID=sepolia-deploy-$(date -u +%Y%m%dT%H%M%SZ)
PARAMS_FILE=~/.opsec/path/params.sepolia.deploy.json
NETWORK=sepolia LANE=deploy RUN_ID=$RUN_ID INPUT_FILE=$PARAMS_FILE INPUT_KIND=constructor_params PARAMS_SCHEMA=schemas/path.constructor_params.schema.json npm run ops:lock-inputs
NETWORK=sepolia LANE=deploy RUN_ID=$RUN_ID npm run ops:dispatch-bundle

# After the workflow succeeds, fetch the bundle artifact on the Signing OS.
NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:fetch-bundle

# On the Signing OS, switch to the exact pinned commit before local CD.
BUNDLE_SHA=$(jq -r .git_commit bundles/sepolia/$RUN_ID/run.json)
git fetch origin
git checkout "$BUNDLE_SHA"

# verify runs the Sepolia deploy prechecks locally on the Signing OS
# (the remote CI bundle intentionally omits immutable checks.path.json for deploy lanes).
SIGNING_OS=1 NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:verify
SIGNING_OS=1 NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:approve
SIGNING_OS=1 NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:apply
SIGNING_OS=1 NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:postconditions
```

Manual override (optional):
```bash
SIGNING_OS=1 POSTCONDITIONS_MODE=manual POSTCONDITIONS_STATUS=pass NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:postconditions
```

## C) Capture deployment outputs
- confirm `bundles/sepolia/$RUN_ID/deployments/sepolia-eth.json` exists
- copy promoted deployment metadata to your chosen publishing target if needed

## D) Failure handling
- if verify fails due policy/check mismatch: fix policy or deployment inputs, then create a new `RUN_ID`
- if commit changes after bundle: rerun bundle/verify/approve with a new `RUN_ID`
