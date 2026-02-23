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

export function deriveGenesisState({ t, genesisPrice, genesisFloor, k }) {
  return {
    curveActive: true,
    epochIndex: 1n,
    curveStartTime: t,
    anchorTime: calculateAnchorTime(genesisPrice, genesisFloor, k, t),
    floorPrice: genesisFloor
  };
}

export function deriveNextState({ now, lastPrice, previousStartTime, k, pts, currentEpochIndex }) {
  const premium = (now - previousStartTime) * pts;
  const initialAsk = lastPrice + premium;

  return {
    curveActive: true,
    epochIndex: currentEpochIndex + 1n,
    curveStartTime: now,
    anchorTime: calculateAnchorTime(initialAsk, lastPrice, k, now),
    floorPrice: lastPrice,
    premium,
    initialAsk
  };
}

export function expectedAsk({ now, curveActive, genesisPrice, k, anchorTime, floorPrice }) {
  if (!curveActive) return genesisPrice;
  return priceAt(now, k, anchorTime, floorPrice);
}
