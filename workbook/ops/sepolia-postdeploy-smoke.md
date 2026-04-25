# Sepolia postdeploy smoke

Purpose: this is the optional live-business-flow smoke after a qualified Sepolia
deploy. It is not part of the deploy authority path, and it is not required for
the deploy history itself to be `pass`.

Use it when you want confidence that the deployed contracts work through one
real Sepolia buyer flow, beyond deploy + postconditions evidence.

This smoke is:
- Dev OS only
- disposable-buyer only
- separate from Signing OS
- separate from `handoff`
- separate from `audit`

This smoke is not:
- a normal post-deploy authority step
- a reason to reopen Signing OS
- a substitute for audit signoff

## A) Preconditions
- the deploy history already exists and `Final status: pass`
- you know the target `RUN_ID`
- you have the canonical deploy history folder
- you have a disposable Sepolia buyer wallet with a small amount of Sepolia ETH
- you are not using `ADMIN`, `TREASURY`, or the deploy signer as the buyer
- you have a Sepolia RPC URL available on Dev OS

Recommended local evidence folder:

```bash
RUN_ID=<run-id>
mkdir -p "output/smoke/sepolia/$RUN_ID"
```

## B) Pull canonical addresses

Use the canonical deployment artifact from the promoted history:

```bash
RUN_ID=<run-id>
HISTORY_DIR="$HOME/Private/signing-os-history/sepolia/deploy/$RUN_ID"
DEPLOY_JSON="$HISTORY_DIR/canonical-artifacts/deployment.sepolia-eth.json"
```

Print the current addresses:

```bash
python3 - <<'PY'
import json
import os
from pathlib import Path

deploy = json.loads(Path(os.environ["DEPLOY_JSON"]).read_text())
print("deployer =", deploy["deployer"])
print("admin    =", deploy["admin"])
print("treasury =", deploy["treasury"])
print("pathNft  =", deploy["contracts"]["pathNft"])
print("pathMinter =", deploy["contracts"]["pathMinter"])
print("pathMinterAdapter =", deploy["contracts"]["pathMinterAdapter"])
print("pulseAuction =", deploy["contracts"]["pulseAuction"])
print("paymentToken =", deploy["paymentToken"])
PY
```

## C) Baseline read-only snapshot

For this smoke, record the sale state before the live buyer action:

```bash
export SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
AUCTION=<pulseAuction-address>
MINTER=<pathMinter-address>
NFT=<pathNft-address>
TREASURY=<treasury-address>
```

```bash
ASK_BEFORE=$(cast call "$AUCTION" "getCurrentPrice()(uint256)" --rpc-url "$SEPOLIA_RPC_URL")
EPOCH_BEFORE=$(cast call "$AUCTION" "epochIndex()(uint256)" --rpc-url "$SEPOLIA_RPC_URL")
NEXT_ID_BEFORE=$(cast call "$MINTER" "nextId()(uint256)" --rpc-url "$SEPOLIA_RPC_URL")
TREASURY_BEFORE=$(cast balance "$TREASURY" --rpc-url "$SEPOLIA_RPC_URL")

printf '%s\n' \
  "ask_before=$ASK_BEFORE" \
  "epoch_before=$EPOCH_BEFORE" \
  "next_id_before=$NEXT_ID_BEFORE" \
  "treasury_before=$TREASURY_BEFORE" \
  > "output/smoke/sepolia/$RUN_ID/baseline.env"
```

For native-ETH payment runs, `paymentToken` should be the zero address.
If the deploy used an ERC-20 payment token instead, do the buyer approval first
and record that token path separately.

## D) Live buyer smoke

Recommended path:
- use the repo-managed Rabby/browser-wallet helper below
- use the intended integration surface only if you intentionally want to test that
  surface instead of the contract-level buyer flow

Rules:
- only one minimal bid
- do not use `ADMIN`, `TREASURY`, or deployer wallets
- do not use Signing OS for this
- do not hand-copy calldata into a wallet
- the wallet page must ABI-encode `bid(uint256)` at runtime, simulate before
  sending, and verify the mined transaction input after sending

Target behavior:
- buyer submits one bid at the current ask
- bid succeeds
- buyer receives the minted PATH token
- treasury receives the sale amount
- auction advances by one epoch

Record at minimum:
- buyer address
- tx hash
- exact ask used
- expected token id (`NEXT_ID_BEFORE`)

Official Rabby/browser-wallet helper:

```bash
RUN_ID=<run-id>
BUYER=<disposable-buyer-address>
npm run ops:postdeploy:smoke -- serve --network sepolia --run-id "$RUN_ID" --buyer "$BUYER"
```

Open the printed local URL, then:
- click `Discover Wallets`
- click `Connect Rabby`
- confirm the connected account is the disposable buyer
- click `Refresh Ask + Simulate`
- approve the wallet transaction only after the page says simulation passed

The page refuses the wrong buyer, wrong chain, wrong selector, wrong calldata
length, and a failed pre-send `eth_call` simulation. After send, it fetches the
mined transaction and compares on-chain `input` with the intended `bid(uint256)`
calldata. If that comparison fails, stop and keep the failure evidence.

## E) Post-smoke verification

After the live bid confirms, verify:

```bash
TX_HASH=<smoke-tx-hash>
BUYER=<disposable-buyer-address>
TOKEN_ID="$NEXT_ID_BEFORE"
RUN_ID=<run-id>

npm run ops:postdeploy:smoke -- verify \
  --network sepolia \
  --run-id "$RUN_ID" \
  --buyer "$BUYER" \
  --tx-hash "$TX_HASH"
```

Pass conditions:
- receipt status is success
- transaction input starts with `0x454a2ab3` (`bid(uint256)`)
- `owner_after == buyer`
- `epoch_after == epoch_before + 1`
- `treasury_after > treasury_before`

## F) Smoke note

Write one small note for the run:

```text
output/smoke/sepolia/<run-id>/SMOKE-NOTE.md
```

Template:

```md
# Sepolia Postdeploy Smoke

Run ID: <run-id>
Buyer: <buyer-address>
Transaction: <tx-hash>
Expected token id: <token-id>

Checks:
- receipt success
- ownerOf(token_id) == buyer
- treasury balance increased
- epoch advanced by one

Result:
- pass | fail

Notes:
- any UI-specific observations
```

After a passing smoke, promote the smoke folder into the canonical deploy
history as optional postdeploy evidence:

```bash
RUN_ID=<run-id>
HISTORY_DIR="$HOME/Private/signing-os-history/sepolia/deploy/$RUN_ID"
mkdir -p "$HISTORY_DIR/smoke/postdeploy"
rsync -a "output/smoke/sepolia/$RUN_ID/" "$HISTORY_DIR/smoke/postdeploy/"
(cd "$HISTORY_DIR/smoke/postdeploy" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256 > SHA256SUMS.txt)
```

This does not change deploy qualification. It records postdeploy confidence
evidence beside, not inside, the Signing OS deploy ceremony.

## G) Stop conditions
- current ask cannot be determined
- buyer tx reverts
- wallet/provider submits calldata that differs from the page preview
- minted token owner is not the buyer
- treasury balance does not move as expected
- any privileged/admin action is needed just to complete the buyer flow

If any stop condition hits:
- keep the deploy history as-is
- record the smoke failure separately under `output/smoke/sepolia/<run-id>/`
- do not treat smoke as deploy invalidation by itself unless you find an actual
  protocol defect

## H) Meaning relative to handoff and audit

`handoff`:
- old/corrective/emergency authority movement lane
- not the normal next step after this deploy

`audit`:
- read-only evidence layer over completed runs
- plan -> collect -> verify -> report -> signoff
- use it when you need formal evidence/signoff, not to make the contracts work
