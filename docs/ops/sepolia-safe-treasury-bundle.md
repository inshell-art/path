# Sepolia Safe Treasury Deploy Bundle

This note defines the Dev OS side of the Sepolia PATH deploy bundle when the treasury is Safe-backed.

## Required Public Inputs

- `NETWORK=sepolia`
- `LANE=deploy`
- Constructor params source: `ops/params.sepolia.deploy.safe-treasury.example.json`
- Treasury Safe evidence source: `/Users/bigu/Downloads/path-safe-treasury-rehearsal/out/treasury_safe.verified.json`
- Deploy signer ref: `SEPOLIA_DEPLOY_SW_A`
- ADMIN ref: `SEPOLIA_ADMIN_HW_A`
- Treasury signer ref: `SEPOLIA_TREASURY_SAFE_1OF1`
- Treasury Safe owner ref: `SEPOLIA_TREASURY_HW_A`

The constructor params example uses `startDelaySec=600` for a Sepolia rehearsal-style deploy. For a scheduled launch, OPS should copy the params file and replace `startDelaySec` with the final absolute UTC `openTime` before locking inputs.

## Bundle Commands

```bash
RUN_ID=sepolia-deploy-<UTC>-safe-treasury
NETWORK=sepolia LANE=deploy RUN_ID=$RUN_ID \
  INPUT_FILE=ops/params.sepolia.deploy.safe-treasury.example.json \
  PARAMS_SCHEMA=schemas/path.constructor_params.schema.json \
  npm run ops:lock-inputs

NETWORK=sepolia LANE=deploy RUN_ID=$RUN_ID \
  LOCKED_INPUTS_FILE=artifacts/sepolia/current/inputs/inputs.$RUN_ID.json \
  TREASURY_SAFE_FILE=/Users/bigu/Downloads/path-safe-treasury-rehearsal/out/treasury_safe.verified.json \
  npm run ops:bundle
```

## Signing OS Commands

```bash
NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:verify
NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:approve
NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:apply
NETWORK=sepolia RUN_ID=$RUN_ID npm run ops:postconditions
```

## Hard Stop Conditions

- Constructor treasury is not the Safe address.
- `treasurySignerRef` is not `SEPOLIA_TREASURY_SAFE_1OF1`.
- Safe evidence is missing or does not match constructor treasury.
- Safe evidence does not prove threshold `1`, owner ref `SEPOLIA_TREASURY_HW_A`, and on-chain code/readback.
- ADMIN is not `SEPOLIA_ADMIN_HW_A`.
- Bundle manifest hash verification fails.
