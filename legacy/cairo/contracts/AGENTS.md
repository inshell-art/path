# AGENTS (contracts/)

Overrides root guidance:
- Run formatting/lint/tests from the specific package dir (e.g. `contracts/path_nft`).
  - `scarb fmt`
  - `scarb lint`
  - `scarb test`
- Use `scarb test -p <pkg>` when running from repo root.
- PathLook gallery HTML under `contracts/path_look/gallery` should only be edited when explicitly requested.
