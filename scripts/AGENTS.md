# AGENTS (scripts/)

Overrides root guidance:
- Scripts are bash; run with `bash` if unsure.
- `scripts/devnet/00_env.sh` is meant to be sourced to set env vars.
- Keep script behavior stable; avoid refactors unless explicitly requested.
- Sepolia flow uses `scripts/declare-sepolia.sh` and `scripts/deploy-sepolia.sh` with outputs in `output/sepolia/`.
