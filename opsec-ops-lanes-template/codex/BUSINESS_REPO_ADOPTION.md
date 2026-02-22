# Codex guide — adopting the template inside a downstream repo

This file is intended for use inside a downstream repo that wants to adhere to the template rules.

## Add template as submodule
```bash
git submodule add <REMOTE_URL_OF_TEMPLATE> ops-template
git commit -m "Add ops-template submodule"
```

## Create instance directories
```bash
mkdir -p ops/policy ops/runbooks artifacts/devnet/current artifacts/sepolia/current artifacts/mainnet/current
```

## Copy example policies (edit placeholders)
```bash
cp ops-template/policy/devnet.policy.example.json ops/policy/lane.devnet.json
cp ops-template/policy/sepolia.policy.example.json ops/policy/lane.sepolia.json
cp ops-template/policy/mainnet.policy.example.json ops/policy/lane.mainnet.json
```

## Keep secrets out-of-repo
Store keystore files and signer metadata outside the repo and reference them via env vars (gitignored).
