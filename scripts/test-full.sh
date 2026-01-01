#!/usr/bin/env bash
set -euo pipefail

./scripts/test-unit.sh
scarb run test -p path_pulse_e2e
scarb run test -p pulse_adapter
scarb run test -p pulse_auction
