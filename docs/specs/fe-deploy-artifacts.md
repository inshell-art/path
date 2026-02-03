# spec.md — FE Deploy Artifacts (addresses + deploy)

**Owner:** Inshell  
**Scope:** path repo publishes contract metadata for inshell.art FE  
**Status:** Draft  
**Last updated:** 2026-02-03

## 1) Purpose

Provide **public, versioned JSON artifacts** that the FE can consume without local coupling to the protocol repo. These artifacts are safe to publish and contain **no secrets**.

The FE uses them to:
- resolve contract addresses
- backfill auction bids from deploy block
- align chain expectations (chain id, explorer base, payment token)

## 2) Outputs (per network)

Publish two JSON files for each network:

### 2.1 addresses.<net>.json
**Only contract addresses (no metadata).**

```json
{
  "pulse_auction": "0x…",
  "path_nft": "0x…",
  "path_look": "0x…",
  "path_minter": "0x…",
  "path_minter_adapter": "0x…",
  "step_curve": "0x…"
}
```

Rules:

- keys are snake_case
- values are 0x + 64-hex addresses
- no extra fields

### 2.2 deploy.<net>.json

Deployment metadata for the FE.

```json
{
  "deploy_block": 123456,
  "chain_id": "0x534e5f5345504f4c4941",
  "payment_token": "0x04718f…",
  "explorer_base": "https://sepolia.voyager.online"
}
```

Rules:

- deploy_block is a decimal block number (not a tx hash)
- chain_id is the Starknet chain id felt
- payment_token is the ERC20 used for bids
- explorer_base is the base URL for the block explorer

## 3) Publishing

Publish the JSONs at stable URLs, e.g. GitHub Raw:

- https://raw.githubusercontent.com/inshell-art/path/main/output/addresses.<net>.json
- https://raw.githubusercontent.com/inshell-art/path/main/output/deploy.<net>.json

These files are public by design. Do not include RPC keys or private data.

## 4) FE consumption (inshell.art)

The FE can:

- pull addresses.<net>.json → resolve contract addresses
- pull deploy.<net>.json → set environment:
  - VITE_PULSE_AUCTION_DEPLOY_BLOCK
  - VITE_EXPECTED_CHAIN_ID
  - VITE_PAYTOKEN
  - VITE_EXPLORER_BASE_URL

## 5) Update policy

- Update both JSONs on every deploy that changes addresses or deploy block.
- Keep old versions via git history (or tagged releases if needed).
- Do not reuse files across networks.

## 6) Safety

- ✅ Public info only.
- ❌ No RPC URLs with keys.
- ❌ No secrets or private keys.
