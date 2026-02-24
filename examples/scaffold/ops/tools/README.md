# Ops tools (stubs)

These scripts are placeholders. Replace them with your repo's real commands.

Expected behavior by script:
- `bundle.sh` creates `run.json`, `intent.json`, `checks.json`, and `bundle_manifest.json`.
- `verify_bundle.sh` verifies manifest hashes, git commit, and policy compatibility.
- `approve_bundle.sh` records human approval tied to the bundle hash.
- `apply_bundle.sh` executes the approved bundle in signing context only.
- `postconditions.sh` records post-apply verification and writes `postconditions.json`.

All write operations must use keystore mode only. Do not use accounts-file signing.

Optional bundle tooling (reference implementations):
- `bundle.sh`, `verify_bundle.sh`, `approve_bundle.sh`, `apply_bundle.sh`

Review and adapt these scripts before use.
