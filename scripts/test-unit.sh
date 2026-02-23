#!/usr/bin/env bash
set -euo pipefail

scarb run test -p path_nft
scarb run test -p path_minter
scarb run test -p path_minter_adapter

(
  cd legacy/cairo/contracts/path_look/contracts
  scarb test
)
