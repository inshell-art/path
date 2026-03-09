# Sepolia runbook

## A) Preflight checklist
- correct network selected (`sepolia`)
- `SEPOLIA_RPC_URL` loaded from local env (not committed)
- deploy signer keystore env is present:
  - `SEPOLIA_DEPLOY_KEYSTORE_JSON` (path or inline JSON)
  - and one of `SEPOLIA_DEPLOY_KEYSTORE_PASSWORD` or `SEPOLIA_DEPLOY_KEYSTORE_PASSWORD_FILE`
- `SEPOLIA_PRIVATE_KEY` is not pre-set in shell
- constructor params file exists at `~/.opsec/path/params.sepolia.deploy.json`
- `ops/policy/lane.sepolia.json` placeholders resolved (RPC allowlist, signer map, fee policy)
- tracked git tree clean before bundle/apply

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
INPUTS_TEMPLATE=artifacts/sepolia/current/inputs/inputs.$RUN_ID.json NETWORK=sepolia LANE=deploy RUN_ID=$RUN_ID npm run ops:bundle
NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:verify
NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:approve
SIGNING_OS=1 NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:apply
NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:postconditions
```

Manual override (optional):
```bash
POSTCONDITIONS_MODE=manual POSTCONDITIONS_STATUS=pass NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:postconditions
```

## C) Capture deployment outputs
- confirm `bundles/sepolia/$RUN_ID/deployments/sepolia-eth.json` exists
- copy promoted deployment metadata to your chosen publishing target if needed

## D) Failure handling
- if verify fails due policy/check mismatch: fix policy or deployment inputs, then create a new `RUN_ID`
- if commit changes after bundle: rerun bundle/verify/approve with a new `RUN_ID`
