# Codex bootstrap — create and publish the template repo

Goal: create a public-safe template repository named `opsec-ops-lanes-template`.

## Constraints (non-negotiable)
- No secrets in git history: no private keys, keystores, mnemonics, 2FA backups, RPC URLs with embedded credentials.
- Keystore signing mode is the only supported signing surface in docs.
- HOT wallet (MetaMask/Rabby) is explicitly *not* an ops-lane signer.

## Repo contents (expected)
- `README.md`
- `LICENSE` (MIT)
- `DISCLAIMER.md`
- `SECURITY.md`
- `CONTRIBUTING.md`
- `.gitignore`
- `.editorconfig`
- `docs/ops-lanes-agent.md`
- `docs/opsec-ops-lanes-signer-map.md`
- `docs/integration.md`
- `policy/devnet.policy.example.json`
- `policy/sepolia.policy.example.json`
- `policy/mainnet.policy.example.json`
- `schemas/intent.schema.json`
- `schemas/checks.schema.json`
- `schemas/approval.schema.json`
- `examples/toy/...` (safe placeholder artifacts)

## Steps (local)
1) Ensure the working directory is clean and contains only the template files.
2) Run a simple secret scan before the first commit:
   - grep for: 'mnemonic', 'seed phrase', 'private_key', 'keystore', 'BEGIN PRIVATE KEY', 'alchemy.com/v2/', 'infura.io/v3/' with a real key.
3) `git init`
4) `git add -A`
5) `git commit -m "Initial public-safe template: OPSEC + Ops Lanes + agent"`

## Push to remote
Preferred (GitHub CLI):
```bash
gh repo create opsec-ops-lanes-template --public --source=. --remote=origin --push
```

Alternative (manual):
- create repo on remote
- `git remote add origin <REMOTE_URL>`
- `git push -u origin main`

## Release
Tag an initial release:
```bash
git tag v0.1.0
git push origin v0.1.0
```

## After publishing
- Add a note in the README that users should fork/copy/submodule and keep secrets out-of-repo.
