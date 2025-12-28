# Path Look metadata trait_type settings

This note describes the `attributes[]` emitted by PathLook token metadata.
It maps each `trait_type` to its value type and the logic used to derive it.

## Seed + randomness
- Seed: `token_seed = pedersen(token_id.low, token_id.high)`.
- Random values use `pprf.pseudo_random_range(address, token_seed, label, occurrence, min, max)`.
- Labels are fixed felts: `STEP`, `SHRP`, `PADD`, `TRGX`, `TRGY`, `THDX`, `THDY`, `WIDX`, `WIDY`, `AWDX`, `AWDY`.

## Trait list

### Steps (integer)
- Range: 1..50 (inclusive).
- Logic: `step_number = random_range(seed, LABEL_STEP_COUNT, 0, 1, 50)`.

### Voice (integer)
- Derived from Steps.
- Logic: `stroke_w = max(1, round_div(100, step_number))`.
- Lower Steps -> larger Voice, higher Steps -> thinner Voice.

### Tension (integer)
- Range: 1..20 (inclusive).
- Logic: `sharpness = random_range(seed, LABEL_SHARPNESS, 0, 1, 20)`.

### Margin (integer, percent)
- Range: 20..40 (percent of canvas width, rounded).
- Logic:
  - `padding = random_range(seed, LABEL_PADDING, 0, pad_min, pad_max)`
  - `pad_min = width * 20%`, `pad_max = width * 40%`
  - `pad_pct = round_div(padding * 100, width)`

### Breath (string or integer)
- If no movement minted: `"Dormant"`.
- If any movement minted: numeric sigma value in 3..30.
- Logic:
  - `any_minted = thought_minted || will_minted || awa_minted`
  - If `any_minted` then `sigma = random_range(seed, LABEL_SHARPNESS, 1, 3, 30)`

### Stage (string)
- Label derived from PathNFT stage:
  - `0` -> `"IDEAL"`
  - `1` -> `"THOUGHT"`
  - `2` -> `"WILL"`
  - `3` -> `"AWA"`
  - otherwise `"UNKNOWN"`

### THOUGHT / WILL / AWA (string)
- Each of these is a movement flag:
  - `"Manifested"` if the movement is considered minted.
  - `"Latent"` otherwise.
- Logic from stage:
  - thought_minted = stage >= 1
  - will_minted   = stage >= 2
  - awa_minted    = stage >= 3

## Data source notes
- Stage is read from `PathNFT.get_stage(token_id)`.
- PathLook does not store stage or movement flags; it derives them at read time.
