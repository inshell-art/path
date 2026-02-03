#!/usr/bin/env bash

# Allow sourcing from zsh without terminating the session.
if [ -z "${BASH_VERSION:-}" ]; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    case "${ZSH_EVAL_CONTEXT:-}" in
      *:file) ;; # sourced in zsh
      *) exec /usr/bin/env bash "$0" "$@" ;;
    esac
  else
    exec /usr/bin/env bash "$0" "$@"
  fi
fi

# Only enable strict mode when executed (not sourced).
if [ -n "${BASH_SOURCE:-}" ] && [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
fi

if [ -n "${BASH_SOURCE:-}" ]; then
  SCRIPT_SOURCE="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  SCRIPT_SOURCE="${(%):-%x}"
else
  SCRIPT_SOURCE="$0"
fi

ROOT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")/../.." && pwd)"
PATH_REPO="${PATH_REPO:-$ROOT_DIR}"
LOCALNET_DIR="${LOCALNET_DIR:-$ROOT_DIR/../localnet}"
export ROOT_DIR PATH_REPO LOCALNET_DIR

export RPC="${RPC:-http://127.0.0.1:5050/rpc}"
export ACCOUNT="${ACCOUNT:-dev_deployer}"
export ACCOUNTS_FILE="${ACCOUNTS_FILE:-$LOCALNET_DIR/.accounts/devnet_oz_accounts.json}"
export ACCOUNTS_NAMESPACE="${ACCOUNTS_NAMESPACE:-alpha-sepolia}"

export WORKBOOK_DIR="${WORKBOOK_DIR:-$ROOT_DIR/workbook}"
export ARTIFACTS_DIR="${ARTIFACTS_DIR:-$WORKBOOK_DIR/artifacts/devnet}"
export ADDR_FILE="${ADDR_FILE:-$ARTIFACTS_DIR/addresses.json}"
export TX_FILE="${TX_FILE:-$ARTIFACTS_DIR/txs.json}"
export SVG_DIR="${SVG_DIR:-$ARTIFACTS_DIR/svg}"
export META_DIR="${META_DIR:-$ARTIFACTS_DIR/metadata}"
export SCARB_CACHE="${SCARB_CACHE:-$ROOT_DIR/output/scarb-cache}"

mkdir -p "$ARTIFACTS_DIR" "$SVG_DIR" "$META_DIR"

[ -f "$ADDR_FILE" ] || echo '{}' >"$ADDR_FILE"
[ -f "$TX_FILE" ] || echo '{}' >"$TX_FILE"
