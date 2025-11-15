#!/usr/bin/env bash
[ -n "${BASH_VERSION:-}" ] || exec /usr/bin/env bash "$0" "$@"
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
need starknet-devnet
need jq
need curl

HOST="${DEVNET_HOST:-127.0.0.1}"
PORT="${DEVNET_PORT:-5050}"
SEED="${DEVNET_SEED:-0}"
ACCOUNTS="${DEVNET_ACCOUNTS:-10}"
INITIAL_BALANCE="${DEVNET_INITIAL_BALANCE:-1000000000000000000000}"
OUT_DIR="${DEVNET_OUT_DIR:-output/devnet}"
LOG_FILE="${DEVNET_LOG_FILE:-$OUT_DIR/devnet.log}"
DUMP_FILE="${DEVNET_DUMP_FILE:-$OUT_DIR/devnet.dump.json}"
RESTART_DELAY="${DEVNET_RESTART_DELAY:-5}"
LOAD_ON_START="${DEVNET_LOAD_ON_START:-1}"
INIT_WAIT="${DEVNET_INIT_WAIT:-5}"

mkdir -p "$OUT_DIR"
: >"$OUT_DIR/.gitkeep"
touch "$LOG_FILE"

declare -a DEVNET_BASE_ARGS=(
  --host "$HOST"
  --port "$PORT"
  --seed "$SEED"
  --accounts "$ACCOUNTS"
  --initial-balance "$INITIAL_BALANCE"
)

[ -n "${DEVNET_DUMP_ON:-}" ] && DEVNET_BASE_ARGS+=(--dump-on "${DEVNET_DUMP_ON}") || DEVNET_BASE_ARGS+=(--dump-on exit)
[ -n "${DEVNET_DUMP_PATH:-}" ] && DEVNET_BASE_ARGS+=(--dump-path "${DEVNET_DUMP_PATH}") || DEVNET_BASE_ARGS+=(--dump-path "$DUMP_FILE")

if [ -n "${DEVNET_ADDITIONAL_ARGS:-}" ]; then
  # shellcheck disable=SC2206
  EXTRA_ARGS=( ${DEVNET_ADDITIONAL_ARGS} )
else
  EXTRA_ARGS=()
fi

ts_log() { date -Iseconds 2>/dev/null || date; }

load_dump_if_present() {
  [ "$LOAD_ON_START" = "0" ] && return 0
  [ -s "$DUMP_FILE" ] || return 0
  local payload tries=30 response
  payload=$(jq -nc --arg path "$DUMP_FILE" '{jsonrpc:"2.0",method:"devnet_load",params:[{path:$path}],id:42}')
  while [ $tries -gt 0 ]; do
    if response=$(curl -sSf -H 'Content-Type: application/json' -d "$payload" "http://$HOST:$PORT/rpc" 2>/dev/null); then
      local err; err=$(jq -r '.error // empty' <<<"$response")
      if [ -z "$err" ]; then
        echo "$(ts_log) devnet_load succeeded ($DUMP_FILE)" | tee -a "$LOG_FILE"
        return 0
      fi
    fi
    sleep 1
    tries=$((tries-1))
  done
  echo "$(ts_log) devnet_load failed after retries" | tee -a "$LOG_FILE"
}

start_devnet_once() {
  echo "================================================================" | tee -a "$LOG_FILE"
  echo "$(ts_log) starting starknet-devnet (port $PORT)" | tee -a "$LOG_FILE"
  local cmd=( starknet-devnet "${DEVNET_BASE_ARGS[@]}" )
  if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
    cmd+=("${EXTRA_ARGS[@]}")
  fi
  (
    trap '' INT TERM
    "${cmd[@]}"
  ) >>"$LOG_FILE" 2>&1 &
  echo $! >"$OUT_DIR/devnet.pid"
}

wait_for_rpc() {
  sleep "$INIT_WAIT"
  local tries=60
  while [ $tries -gt 0 ]; do
    if curl -sf "http://$HOST:$PORT/is_alive" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    tries=$((tries-1))
  done
  return 1
}

stop_devnet() {
  [ -f "$OUT_DIR/devnet.pid" ] || return 0
  local pid; pid=$(cat "$OUT_DIR/devnet.pid" 2>/dev/null || true)
  [ -n "$pid" ] && kill "$pid" >/dev/null 2>&1 || true
}

trap 'echo "$(ts_log) watchdog exiting" | tee -a "$LOG_FILE"; stop_devnet; exit 0' INT TERM

while true; do
  start_devnet_once
  if wait_for_rpc; then
    load_dump_if_present || true
    wait $(cat "$OUT_DIR/devnet.pid") || true
  else
    echo "$(ts_log) devnet failed to expose RPC in time" | tee -a "$LOG_FILE"
    stop_devnet
  fi
  echo "$(ts_log) restarting in ${RESTART_DELAY}s..." | tee -a "$LOG_FILE"
  sleep "$RESTART_DELAY"
done
