#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

cat <<'HELP'
PATH ops scripts (rehearsable pipeline)

Usage:
  source ~/.config/inshell/path/env/<network>.env
  ./scripts/ops/10_build.sh
  ./scripts/ops/20_declare.sh
  ./scripts/ops/30_deploy.sh
  ./scripts/ops/40_wire.sh
  ./scripts/ops/50_prepare_handoff_intents.sh
  ./scripts/ops/60_verify.sh
  ./scripts/ops/70_log_run.sh

Required env (typical):
  OPS_NETWORK            devnet | sepolia | mainnet
  RPC                    RPC endpoint
  ACCOUNT                deployer account name/alias
  ACCOUNTS_FILE          accounts/keystore file path (outside repo)

Optional env:
  WORKBOOK_DIR           override workbook path (default: repo/workbook)
  OPS_CONTRACTS_DIR      where to run build/declare/deploy commands
  OPS_BUILD_CMD          build command (default: scarb build if available)
  OPS_DECLARE_CMD        declare command (must produce classes output)
  OPS_DECLARE_OUTPUT     path to classes JSON (default: output/classes.<net>.json)
  OPS_DEPLOY_CMD         deploy command (must produce addresses output)
  OPS_DEPLOY_OUTPUT      path to addresses JSON (default: output/addresses.<net>.json)
  OPS_WIRE_CMD           wiring command
  OPS_VERIFY_CMD         verify command
  MULTISIG_ADDRESS       multisig contract address (for handoff)
  OPS_HANDOFF_ACTIONS_FILE  JSON file with actions[] for handoff intent bundle

Artifacts:
  workbook/artifacts/<network>/... (logs, classes.json, addresses.json, handoff.json)

Notes:
  - Scripts are non-interactive and deterministic.
  - They write only safe outputs (addresses, tx hashes, class hashes) to logs.
HELP
