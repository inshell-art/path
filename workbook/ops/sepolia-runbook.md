# Sepolia runbook

See also:
- [Signing OS runbook](signing-os-runbook.md) for the serious split between Dev OS, CI, and Signing OS.

Use this runbook as the default meaning of "deploy on Sepolia" for this repo.
Do not switch to a direct ad hoc Hardhat deploy path unless you are intentionally bypassing the repo-managed ops lane.

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

## B) Dev OS steps
```bash
install -d -m 700 ~/.opsec/path
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
printf 'NETWORK=%s\nRUN_ID=%s\n' sepolia "$RUN_ID"
```

## C) Handoff note

Carry only:

```text
NETWORK=sepolia
RUN_ID=<bundle-run-id>
```

## D) Signing OS steps

On the Signing OS, from the repo root:

```bash
NETWORK=sepolia
RUN_ID=<bundle-run-id>
GH_REPO=inshell-art/path

# After the workflow succeeds, fetch the bundle artifact on the Signing OS.
git fetch origin
git checkout main
git pull origin main
git diff --quiet && git diff --cached --quiet || { echo "tracked tree is dirty"; exit 1; }

npm run ops:fetch-bundle

BUNDLE_SHA=$(jq -r .git_commit bundles/sepolia/$RUN_ID/run.json)
git fetch origin
git checkout "$BUNDLE_SHA"
git diff --quiet && git diff --cached --quiet || { echo "tracked tree is dirty"; exit 1; }

set -a
source ~/.opsec/path/sepolia.env
set +a
unset SEPOLIA_PRIVATE_KEY

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

## E) Capture deployment outputs
- confirm `bundles/sepolia/$RUN_ID/deployments/sepolia-eth.json` exists
- copy promoted deployment metadata to your chosen publishing target if needed

## F) Failure handling
- if verify fails due policy/check mismatch: fix policy or deployment inputs, then create a new `RUN_ID`
- if commit changes after bundle: rerun bundle/verify/approve with a new `RUN_ID`
