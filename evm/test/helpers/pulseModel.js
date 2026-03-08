const U64_MAX = (1n << 64n) - 1n;

export function calculateAnchorTime(initialAsk, floorPrice, k, curveStartTime) {
  if (initialAsk <= floorPrice) {
    throw new Error("initialAsk must be greater than floorPrice");
  }

  const gap = initialAsk - floorPrice;
  const kOverGap = k / gap;

  if (kOverGap > U64_MAX) {
    throw new Error("k / gap exceeds u64");
  }
  if (curveStartTime <= kOverGap) {
    throw new Error("anchor underflow");
  }

  return curveStartTime - kOverGap;
}

export function priceAt(now, k, anchor, floorPrice) {
  if (now <= anchor) {
    return floorPrice + k;
  }
  return floorPrice + k / (now - anchor);
}

export function deriveInitialState({ openTime, genesisPrice, genesisFloor, k }) {
  return {
    epochIndex: 0n,
    curveStartTime: openTime,
    anchorTime: calculateAnchorTime(genesisPrice, genesisFloor, k, openTime),
    floorPrice: genesisFloor
  };
}

export function deriveNextState({
  now,
  lastPrice,
  previousStartTime,
  k,
  pts,
  currentEpochIndex
}) {
  const deltaT = now - previousStartTime;
  const effectiveDeltaT = deltaT === 0n ? 1n : deltaT;
  const premium = effectiveDeltaT * pts;
  const initialAsk = lastPrice + premium;
  const nextFloor = lastPrice;

  return {
    epochIndex: currentEpochIndex + 1n,
    curveStartTime: now,
    anchorTime: calculateAnchorTime(initialAsk, nextFloor, k, now),
    floorPrice: nextFloor,
    premium,
    initialAsk
  };
}

export function expectedAsk({ now, openTime, k, anchorTime, floorPrice }) {
  const t = now < openTime ? openTime : now;
  return priceAt(t, k, anchorTime, floorPrice);
}
