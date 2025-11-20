# Pulse Bidding Trigger Engine — Specification (v1.0)

**Audience:** developer implementing a real‑time bidder for the PATH “Pulse” auction on Starknet.  
**Authoring assumptions:** PTS = 1, k = 1,000,000 (STRK·s), genesis sale at fixed price, and the “carry‑forward pump” model agreed with Inshell.

---

## 0) Purpose

Automate bids on Pulse without time‑warping, using block timestamps only. The engine waits the right amount of **in‑auction time** `τ` per epoch and submits a bid when the **markup over floor** falls to a target tolerance `θ`.

**Key properties**
- **Carry:** new floor = last hammer (from epoch 3 onward).
- **One time per epoch:** `τ` = seconds from epoch start (previous bid) to this bid.
- **Pump (per‑epoch constant):** for epoch `i ≥ 3`, `D_i = τ_{i‑1}` (PTS = 1 ⇒ seconds == STRK of pump).
- **Hyperbola inside epoch `i ≥ 3`:** premium `P_i(τ) = k / (τ + k / D_i)`; ask `= floor_i + P_i(τ)`.
- **Trigger rule:** bid at the first `τ` with `(ask(τ) / floor) − 1 ≤ θ`.
- **Epoch 2 special:** genesis hammer *not* considered a previous bid; floor = genesis floor; no carried `D`.

---

## 1) Symbols & Units

- `k` — hyperbola constant, unit **STRK·seconds** (e.g., 1,000,000).  
- `PTS` — **STRK/second**. Here **PTS = 1**, so seconds and STRK amounts align for the pump.  
- `floor_i` — floor during epoch `i` (STRK). For `i ≥ 3`: `floor_i = hammer_{i‑1}`.  
- `D_i` — **pump** at epoch start (STRK). For `i ≥ 3`: `D_i = τ_{i‑1}`.  
- `τ_i` — **in‑auction** time to bid in epoch `i` (seconds since previous bid).  
- `P_i(τ)` — premium above floor at elapsed time `τ`.  
- `ask_i(τ)` — price shown in epoch `i` at elapsed time `τ`.  
- `θ_i` — markup tolerance (fraction over floor; e.g., `0.04` = 4%).  
- **STRK units:** use human units for logic; convert to **18‑dec base units** (STRK “base units”) when sending tx; pack as Uint256 `(low, high)` if the entrypoint requires.

---

## 2) Epoch Model

### 2.1 Genesis (epoch 1)
- Fixed sale at `genesis_price`. Not part of the curve logic.

### 2.2 Epoch 2 (first real auction; special)
- `floor_2 = genesis_floor` (e.g., 1,000 STRK).  
- No previous bid ⇒ no carried `D_2`. Treat as **limit `D → ∞`**:
  ```
  P_2(τ) = k / τ
  ask_2(τ) = floor_2 + k / τ
  hammer_2 = floor_2 + k / τ_2
  ```
- Engine either takes `τ_2` from config (manual hand‑trigger) or computes it from a chosen `θ_2`:
  ```
  τ_2 = k / (θ_2 * floor_2)
  ```

### 2.3 Epoch i ≥ 3 (regular cycle)
- **Carry:** `floor_i = hammer_{i‑1}`.  
- **Pump:** `D_i = τ_{i‑1}` (seconds ⇒ STRK because PTS=1).  
- **Start ask:** `init_ask_i = floor_i + D_i` (since `P_i(0) = D_i`).  
- **Premium path:** `P_i(τ) = k / (τ + k / D_i)`.  
- **Ask path:** `ask_i(τ) = floor_i + P_i(τ)`.  
- **Half‑life:** `T_{1/2,i} = k / D_i`.

---

## 3) Trigger Rule

Bid at the **earliest** `τ ≥ 0` such that the markup is within tolerance:
```
(ask_i(τ) / floor_i) − 1 ≤ θ_i    ⇔    P_i(τ) ≤ θ_i · floor_i
```

### 3.1 Solving for τ

- **Epoch i ≥ 3:**
  ```
  k / (τ_i + k / D_i) = θ_i · floor_i
  ⇒ τ_i = k / (θ_i · floor_i) − k / D_i
  ```

- **Epoch 2 (limit D→∞):**
  ```
  k / τ_2 = θ_2 · floor_2
  ⇒ τ_2 = k / (θ_2 · floor_2)
  ```

### 3.2 Clamp (safety)
If the computed `τ_i ≤ 0`, set `τ_i := MIN_TAU_SEC` (e.g., 60), then recompute the **actual** tolerance (for logs/metrics) from the curve:
```
θ_i = k / ( floor_i · ( τ_i + k / D_i ) )
```

---

## 4) Configuration (suggested defaults)

```yaml
# pulse-engine.yaml
contract:
  address: "0x…PULSE"
  abi_path: "./pulse_abi.json"
  entrypoint: "bid"           # or "bid_with_max_price"
  has_max_price_arg: true
  slippage_bps: 30            # 0.30% price guard

constants:
  k_strk_seconds: 1000000     # k in STRK·s (logic)
  PTS: 1                      # STRK/s (informational)
  genesis_price_strk: 10000
  genesis_floor_strk: 1000

tolerance:
  mode: "sample"              # "fixed" or "sample"
  fixed_theta: 0.04           # only used if mode=fixed
  sample_mean: 0.04
  sample_sd: 0.01
  sample_min: 0.02
  sample_max: 0.06

timing:
  min_tau_sec: 60             # clamp for τ
  epoch2_tau_sec: 600         # hand‑trigger delay for epoch 2 (optional)

io:
  log_csv_path: "./pulse_runs.csv"
```

---

## 5) Engine State (persisted)

- `epoch_index` — start at **2** once genesis is sold.  
- `last_bid_time_sec` — block timestamp of prior hammer.  
- `last_tau_sec` — measured `τ` of the previous epoch; becomes next epoch’s `D`.  
- `last_hammer_strk` — previous hammer; becomes next `floor`.  
- `cum_time_from_genesis_sec` — sum of τ’s (for logging).

---

## 6) Algorithm (pseudocode)

```text
BOOT:
  # Epoch 1 handled elsewhere (genesis fixed sale).
  epoch_index = 2
  last_bid_time_sec = t_genesis     # block time of genesis sale
  last_hammer_strk = genesis_price_strk
  cum_time_from_genesis_sec = 0

EPOCH 2:
  floor = genesis_floor_strk
  if epoch2_tau_sec is set:
      tau = epoch2_tau_sec
  else:
      theta = choose_theta()                          # fixed or sampled
      tau = k / (theta * floor)

  premium = k / tau
  hammer  = floor + premium

  wait_until(last_bid_time_sec + tau)
  send_bid(max_price = hammer * (1 + slippage_bps/10000))

  # On confirmation (read from events/receipt):
  measured_tau = block_timestamp - last_bid_time_sec
  last_tau_sec = measured_tau                         # D for next epoch
  last_hammer_strk = actual_hammer_onchain
  last_bid_time_sec = block_timestamp
  cum_time_from_genesis_sec += measured_tau
  epoch_index = 3

EPOCH i ≥ 3 (loop):
  floor = last_hammer_strk
  D     = last_tau_sec                                # carry-forward
  init_ask = floor + D
  half_life = k / D

  theta = choose_theta()
  tau_star = k / (theta * floor) - k / D
  if tau_star <= 0:
      tau = min_tau_sec
      theta = k / (floor * (tau + k/D))
  else:
      tau = tau_star

  premium = k / (tau + k / D)
  hammer  = floor + premium

  wait_until(last_bid_time_sec + tau)
  send_bid(max_price = hammer * (1 + slippage_bps/10000))

  # confirmation:
  measured_tau = block_timestamp - last_bid_time_sec
  last_tau_sec = measured_tau
  last_hammer_strk = actual_hammer_onchain
  last_bid_time_sec = block_timestamp
  cum_time_from_genesis_sec += measured_tau
  epoch_index += 1

  log_row(
    epoch_index, prev_bid_price=floor, bumped_d=D, init_ask=init_ask,
    floor_price=floor, hammer_price=last_hammer_strk,
    bid_in_auction_sec=measured_tau,
    bid_from_genesis_sec=cum_time_from_genesis_sec,
    half_life_sec=half_life, theta_pct=100 * premium / floor,
    checks = {
      "curve": abs((hammer - floor) - k / (tau + k/D)) < eps,
      "theta": abs((hammer / floor) - 1 - premium / floor) < eps
    }
  )
```

**Helper `choose_theta()`**
- If `mode == "fixed"`: return `fixed_theta`.
- If `mode == "sample"`: draw from Normal(`sample_mean`, `sample_sd`), clipped to [`sample_min`, `sample_max`].
- Or wire your own function (e.g., based on demand metrics).

---

## 7) Contract Call & Units

If the entrypoint supports a guard (recommended):
```
max_price = hammer * (1 + slippage_bps/10000)

# Convert STRK → base units (18-dec), then pack u256(low, high):
amount_wei = round(max_price * 10^18)
low  = amount_wei % 2^128
high = amount_wei // 2^128
bid(max_price = {low, high})
```
If no guard, just call `bid()` at the target time.

---

## 8) Invariants & Validation

- **Curve identity (i ≥ 3):**  
  `(hammer − floor) == k / (τ + k/D)`

- **Epoch 2 identity:**  
  `(hammer_2 − floor_2) == k / τ_2`

- **Tolerance at fill:**  
  `theta_real == (hammer − floor) / floor`

- **Carry:**  
  `next floor == last hammer`, `next D == last τ`

---

## 9) Example (numbers)

Given `k = 1_000_000`, epoch‑2 with `τ_2 = 600 s`:
```
floor_2 = 1000
premium_2 = 1e6 / 600 = 1666.6667
hammer_2  = 2666.6667  (becomes floor_3)
D_3       = τ_2 = 600
T_half_3  = 1e6 / 600 = 1666.6667 s
θ_3 = 0.04 ⇒ τ_3 = 1e6 / (0.04 · 2666.6667) − 1e6 / 600 ≈ 7708.3333 s
premium_3 = k / (τ_3 + k/D_3) = θ_3 · floor_3 = 106.6667
hammer_3  = 2773.3334
```
This `τ_3` becomes `D_4`, and so on.

---

## 10) Edge Cases

- If `τ_star ≤ 0`, enforce `min_tau_sec` to avoid instantaneous fills; recompute `θ` from the identity.  
- If network delay risks missing the boundary, submit slightly early with a guard; the curve enforces that you never overpay beyond the guard.  
- Always read the **confirmed** on‑chain hammer and **block timestamp** to update state (not local estimates).

---

## 11) Deliverables for implementation

- `pulse-engine.yaml` (config as above).  
- A script that:
  1) Reads config and ABI, connects to the RPC.  
  2) Tracks state (`epoch_index`, `last_*`).  
  3) Computes `τ` via the formulas above; sleeps until `last_bid_time + τ`.  
  4) Calls `bid()` or `bid(max_price)` with correct base‑unit `u256`.  
  5) On receipt, updates state and appends a CSV log row with all fields and checks.
