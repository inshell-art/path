#!/usr/bin/env bash
set -euo pipefail

./scripts/test-unit.sh
snforge test --package path_pulse_e2e
snforge test --package pulse_adapter
snforge test --package pulse_auction
