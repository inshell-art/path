#!/usr/bin/env bash
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
exec python3 "$ROOT/ops/tools/audit.py" plan
