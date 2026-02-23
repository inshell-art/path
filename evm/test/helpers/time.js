export async function setNextBlockTimestamp(provider, timestamp) {
  await provider.send("evm_setNextBlockTimestamp", [Number(timestamp)]);
}

export async function mine(provider) {
  await provider.send("evm_mine");
}

export async function mineAt(provider, timestamp) {
  await setNextBlockTimestamp(provider, timestamp);
  await mine(provider);
}
