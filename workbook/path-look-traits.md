# Path Look metadata trait_type settings

This note describes the `attributes[]` emitted by PathLook token metadata.
It maps each `trait_type` to its value type and the logic used to derive it.

## Seed + randomness
- Seed: `token_seed = pedersen(token_id.low, token_id.high)`.
- Random values use `pprf.pseudo_random_range(address, token_seed, label, occurrence, min, max)`.
- Labels are fixed felts: `STEP`, `SHRP`, `PADD`, `TRGX`, `TRGY`, `THDX`, `THDY`, `WIDX`, `WIDY`, `AWDX`, `AWDY`.

## Trait list

### segments (integer)
- Range: 1..50 (inclusive).
- Logic: `step_number = random_range(seed, LABEL_STEP_COUNT, 0, 1, 50)`.

### stroke-width (integer)
- Derived from segments.
- Logic: `stroke_w = max(1, round_div(100, step_number))`.
- Lower segments -> larger stroke-width, higher segments -> thinner stroke-width.

### sharpness (integer)
- Range: 1..20 (inclusive).
- Logic: `sharpness = random_range(seed, LABEL_SHARPNESS, 0, 1, 20)`.

### padding-pct (integer, percent)
- Range: 20..40 (percent of canvas width, rounded).
- Logic:
  - `padding = random_range(seed, LABEL_PADDING, 0, pad_min, pad_max)`
  - `pad_min = width * 20%`, `pad_max = width * 40%`
  - `pad_pct = round_div(padding * 100, width)`

### sigma (string or integer)
- If no movement minted: `"Dormant"`.
- If any movement minted: numeric sigma value in 3..30.
- Logic:
  - `any_minted = thought_minted > 0 || will_minted > 0 || awa_minted > 0`
  - If `any_minted` then `sigma = random_range(seed, LABEL_SHARPNESS, 1, 3, 30)`

### Stage (string)
- Label derived from PathNFT stage:
  - `0` -> `"THOUGHT"`
  - `1` -> `"WILL"`
  - `2` -> `"AWA"`
  - `3` -> `"COMPLETE"`
  - otherwise `"UNKNOWN"`

### THOUGHT / WILL / AWA (string)
- Each of these is a movement progress string: `Minted(x/N)`.
- Quotas are read from PathNFT for each movement.
- Logic from stage + stage_minted:
  - THOUGHT: `x_T = (stage > 0 ? N_T : stage_minted)`
  - WILL: `x_W = (stage > 1 ? N_W : stage == 1 ? stage_minted : 0)`
  - AWA: `x_A = (stage > 2 ? N_A : stage == 2 ? stage_minted : 0)`

## Data source notes
- Stage is read from `PathNFT.get_stage(token_id)`.
- Stage minted count is read from `PathNFT.get_stage_minted(token_id)`.
- Quotas are read from `PathNFT.get_movement_quota(movement)`.
- PathLook does not store stage or movement progress; it derives them at read time.
