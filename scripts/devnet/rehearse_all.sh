#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

"$ROOT_DIR/scripts/devnet/01_preflight.sh"
"$ROOT_DIR/scripts/devnet/10_group_A_utils.sh"
"$ROOT_DIR/scripts/devnet/20_group_C_path_core.sh"
"$ROOT_DIR/scripts/devnet/30_group_B_renderer.sh"
"$ROOT_DIR/scripts/devnet/40_group_D_pulse.sh"
"$ROOT_DIR/scripts/devnet/50_group_E_movements.sh"

echo "==> Rehearsal complete"
