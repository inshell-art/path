#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
PORT=${PATH_CAMPAIGN_E2E_PORT:-8551}
CHAIN_ID=${PATH_CAMPAIGN_E2E_CHAIN_ID:-31349}
RPC_URL="http://127.0.0.1:${PORT}"
DEPLOYER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
TMP_DIR=$(mktemp -d)
NODE_PID=""
RUN_ID_A="path-campaign-e2e-a-${CHAIN_ID}-$$"
RUN_ID_B="path-campaign-e2e-b-${CHAIN_ID}-$$"

cleanup() {
  if [[ -n "$NODE_PID" ]]; then
    kill "$NODE_PID" >/dev/null 2>&1 || true
    wait "$NODE_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$ROOT/bundles/devnet/$RUN_ID_A" "$ROOT/bundles/devnet/$RUN_ID_B"
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

rpc() {
  local method=$1
  curl -fsS \
    -H 'content-type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"${method}\",\"params\":[]}" \
    "$RPC_URL" | jq -er '.result'
}

run_hardhat() {
  (
    cd "$ROOT/evm"
    PATH_LOCAL_CHAIN_ID="$CHAIN_ID" PATH_LOCAL_RPC_URL="$RPC_URL" \
      npx hardhat run "$@" --network localhost
  )
}

build_verify_bundle() {
  local run_id=$1
  local kind=$2
  local params=$3
  local schema=$4
  local locked_dir="$TMP_DIR/locked-${run_id}"
  NETWORK=devnet LANE=deploy RUN_ID="$run_id" \
    INPUT_FILE="$params" INPUT_KIND="$kind" PARAMS_SCHEMA="$schema" \
    OUT_DIR="$locked_dir" "$ROOT/ops/tools/lock_inputs.sh" >/dev/null
  if ! PATH_LOCAL_CHAIN_ID="$CHAIN_ID" PATH_LOCAL_RPC_URL="$RPC_URL" \
    NETWORK=devnet LANE=deploy RUN_ID="$run_id" \
    LOCKED_INPUTS_FILE="$locked_dir/inputs.${run_id}.json" \
    "$ROOT/ops/tools/bundle.sh" >"$TMP_DIR/bundle-${run_id}.log" 2>&1; then
    cat "$TMP_DIR/bundle-${run_id}.log" >&2
    for log_file in "$ROOT/bundles/devnet/$run_id"/*.log; do
      if [[ -f "$log_file" ]]; then
        echo "--- $log_file" >&2
        cat "$log_file" >&2
      fi
    done
    return 1
  fi
  if ! PATH_LOCAL_CHAIN_ID="$CHAIN_ID" PATH_LOCAL_RPC_URL="$RPC_URL" \
    BUNDLE_PATH="$ROOT/bundles/devnet/$run_id" \
    "$ROOT/ops/tools/verify_bundle.sh" >"$TMP_DIR/verify-${run_id}.log" 2>&1; then
    cat "$TMP_DIR/verify-${run_id}.log" >&2
    return 1
  fi
  jq -e --arg kind "$kind" '.kind == $kind' \
    "$ROOT/bundles/devnet/$run_id/inputs.json" >/dev/null
}

approve_apply_postconditions() {
  local run_id=$1
  local bundle_dir="$ROOT/bundles/devnet/$run_id"
  local bundle_hash
  local inputs_hash
  bundle_hash=$(jq -er '.bundle_hash' "$bundle_dir/bundle_manifest.json")
  inputs_hash=$(jq -er '.inputs_sha256' "$bundle_dir/intent.json")
  local phrase="APPROVE devnet deploy ${bundle_hash: -8} IN${inputs_hash: -8}"
  printf '%s\n' "$phrase" | BUNDLE_PATH="$bundle_dir" \
    "$ROOT/ops/tools/approve_bundle.sh" >"$TMP_DIR/approve-${run_id}.log"
  PATH_LOCAL_CHAIN_ID="$CHAIN_ID" PATH_LOCAL_RPC_URL="$RPC_URL" \
    SIGNING_OS=1 PATH_PACK_MANIFEST_JSON=devnet-campaign-e2e \
    BUNDLE_PATH="$bundle_dir" "$ROOT/ops/tools/apply_bundle.sh" \
    >"$TMP_DIR/apply-${run_id}.log"
  PATH_LOCAL_CHAIN_ID="$CHAIN_ID" PATH_LOCAL_RPC_URL="$RPC_URL" \
    NETWORK=devnet BUNDLE_PATH="$bundle_dir" \
    "$ROOT/ops/tools/postconditions.sh" >"$TMP_DIR/postconditions-${run_id}.log"
  jq -e '.status == "pass"' "$bundle_dir/postconditions.json" >/dev/null
}

(
  cd "$ROOT/evm"
  PATH_LOCAL_CHAIN_ID="$CHAIN_ID" npx hardhat node --hostname 127.0.0.1 --port "$PORT"
) >"$TMP_DIR/node.log" 2>&1 &
NODE_PID=$!

for _ in $(seq 1 60); do
  if rpc eth_chainId >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done
if [[ "$(rpc eth_chainId)" != "$(printf '0x%x' "$CHAIN_ID")" ]]; then
  echo "local campaign node chain mismatch" >&2
  exit 1
fi

jq \
  --arg chain "$CHAIN_ID" \
  --arg deployer "$DEPLOYER" \
  --arg campaign "path-campaign-resume-e2e-${CHAIN_ID}" \
  '.expectedChainId = $chain
    | .campaignId = $campaign
    | .environment = "internal-sepolia"
    | .retainedAuthority.address = $deployer' \
  "$ROOT/ops/campaign/examples/path-phase-a-params.example.json" \
  >"$TMP_DIR/path-phase-a-params.json"

build_verify_bundle \
  "$RUN_ID_A" \
  path_campaign_phase_a \
  "$TMP_DIR/path-phase-a-params.json" \
  schemas/path.campaign.phase_a_params.schema.json
BUNDLE_A="$ROOT/bundles/devnet/$RUN_ID_A"
SOURCE_A=$(jq -er '.bundle_hash' "$BUNDLE_A/bundle_manifest.json")
PHASE_A_RECEIPT="$BUNDLE_A/deployments/path-phase-a-receipt.json"
PHASE_A_CHECKPOINT="$BUNDLE_A/deployments/path-phase-a-checkpoint.json"

if DEPLOY_PARAMS_FILE="$TMP_DIR/path-phase-a-params.json" \
  DEPLOY_OUT_FILE="$PHASE_A_RECEIPT" \
  PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST="$SOURCE_A" \
  PATH_CAMPAIGN_TEST_STOP_AFTER_DEPLOY=1 \
  run_hardhat scripts/deploy-campaign-phase-a.js >"$TMP_DIR/phase-a-stop.log" 2>&1; then
  echo "expected the controlled Phase A interruption to fail" >&2
  exit 1
fi
grep -q 'PATH_CAMPAIGN_TEST_STOP:PATH_NFT_DEPLOYED' "$TMP_DIR/phase-a-stop.log"
test -f "$PHASE_A_CHECKPOINT"
test ! -f "$PHASE_A_RECEIPT"
PHASE_A_PATH=$(jq -er '.pathNft.address' "$PHASE_A_CHECKPOINT")

approve_apply_postconditions "$RUN_ID_A"
test "$PHASE_A_PATH" = "$(jq -er '.pathNft.address' "$PHASE_A_RECEIPT")"
node "$ROOT/ops/tools/path_campaign.mjs" verify-phase-a \
  --receipt "$PHASE_A_RECEIPT" >/dev/null

PATH_PHASE_A_RECEIPT_FILE="$PHASE_A_RECEIPT" \
  PATH_CAMPAIGN_DEVNET_OUT_DIR="$TMP_DIR/dependencies" \
  run_hardhat scripts/prepare-path-campaign-devnet-dependencies.js \
  >"$TMP_DIR/dependencies.log"

build_verify_bundle \
  "$RUN_ID_B" \
  path_campaign_phase_b \
  "$TMP_DIR/dependencies/path-phase-b-params.json" \
  schemas/path.campaign.phase_b_params.schema.json
BUNDLE_B="$ROOT/bundles/devnet/$RUN_ID_B"
SOURCE_B=$(jq -er '.bundle_hash' "$BUNDLE_B/bundle_manifest.json")
PHASE_B_RECEIPT="$BUNDLE_B/deployments/path-phase-b-final-receipt.json"
PHASE_B_CHECKPOINT="$BUNDLE_B/deployments/path-phase-b-checkpoint.json"

if DEPLOY_PARAMS_FILE="$TMP_DIR/dependencies/path-phase-b-params.json" \
  DEPLOY_OUT_FILE="$PHASE_B_RECEIPT" \
  PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST="$SOURCE_B" \
  PATH_CAMPAIGN_TEST_STOP_AFTER_ACTION=FREEZE_THOUGHT_MOVEMENT \
  run_hardhat scripts/deploy-campaign-phase-b.js >"$TMP_DIR/phase-b-stop.log" 2>&1; then
  echo "expected the controlled Phase B interruption to fail" >&2
  exit 1
fi
grep -q 'PATH_CAMPAIGN_TEST_STOP:FREEZE_THOUGHT_MOVEMENT' "$TMP_DIR/phase-b-stop.log"
test ! -f "$PHASE_B_RECEIPT"
test "$(jq -er '.completedActions | length' "$PHASE_B_CHECKPOINT")" = "2"

DEPLOY_PARAMS_FILE="$TMP_DIR/dependencies/path-phase-b-params.json" \
  PATH_CAMPAIGN_INPUT_KIND=path_campaign_phase_b \
  PATH_CAMPAIGN_CHECK_MODE=predeploy \
  PATH_CAMPAIGN_CHECKPOINT_FILE="$PHASE_B_CHECKPOINT" \
  PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST="$SOURCE_B" \
  PATH_CAMPAIGN_POLICY_SIGNER_ADDRESS="$DEPLOYER" \
  PATH_CAMPAIGN_RPC_HOST_ALLOWED=1 \
  PATH_CAMPAIGN_NETWORK_LABEL=devnet \
  PATH_CAMPAIGN_LANE_LABEL=deploy \
  PATH_CAMPAIGN_CHECKS_OUT="$TMP_DIR/resume-preflight.json" \
  run_hardhat scripts/check-path-campaign-state.js >"$TMP_DIR/resume-preflight.log"
jq -e '.pass == true and .path_invariants.phase_b_resume_checkpoint_verified == true' \
  "$TMP_DIR/resume-preflight.json" >/dev/null

approve_apply_postconditions "$RUN_ID_B"
test "$(jq -er '.completedActions | length' "$PHASE_B_CHECKPOINT")" = "16"
node "$ROOT/ops/tools/path_campaign.mjs" verify-final \
  --receipt "$PHASE_B_RECEIPT" >/dev/null

DEPLOY_PARAMS_FILE="$TMP_DIR/dependencies/path-phase-b-params.json" \
  PATH_CAMPAIGN_INPUT_KIND=path_campaign_phase_b \
  PATH_CAMPAIGN_CHECK_MODE=postdeploy \
  PATH_CAMPAIGN_RECEIPT_FILE="$PHASE_B_RECEIPT" \
  PATH_CAMPAIGN_POLICY_SIGNER_ADDRESS="$DEPLOYER" \
  PATH_CAMPAIGN_RPC_HOST_ALLOWED=1 \
  PATH_CAMPAIGN_NETWORK_LABEL=devnet \
  PATH_CAMPAIGN_LANE_LABEL=deploy \
  PATH_CAMPAIGN_CHECKS_OUT="$TMP_DIR/final-postconditions.json" \
  run_hardhat scripts/check-path-campaign-state.js >"$TMP_DIR/final-postconditions.log"
jq -e '.pass == true and .path_invariants.combined_postconditions_verified == true' \
  "$TMP_DIR/final-postconditions.json" >/dev/null

BLOCK_BEFORE=$(rpc eth_blockNumber)
DEPLOY_PARAMS_FILE="$TMP_DIR/dependencies/path-phase-b-params.json" \
  DEPLOY_OUT_FILE="$PHASE_B_RECEIPT" \
  PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST="$SOURCE_B" \
  run_hardhat scripts/deploy-campaign-phase-b.js >"$TMP_DIR/phase-b-idempotent.log"
BLOCK_AFTER=$(rpc eth_blockNumber)
test "$BLOCK_BEFORE" = "$BLOCK_AFTER"
grep -q 'already complete' "$TMP_DIR/phase-b-idempotent.log"

echo "PATH campaign bundle apply, forced-interruption resume, idempotence, and postcondition rehearsal passed"
