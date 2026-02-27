import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import hre from "hardhat";

const here = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_DEPLOY_FILE = path.resolve(here, "../deployments/localhost-eth.json");

function toBigInt(v) {
  return typeof v === "bigint" ? v : BigInt(v);
}

function askAt(now, k, anchor, floorPrice) {
  if (now <= anchor) return floorPrice + k;
  return floorPrice + k / (now - anchor);
}

async function main() {
  const deployFile = process.env.DEPLOY_FILE ?? DEFAULT_DEPLOY_FILE;
  const raw = await fs.readFile(deployFile, "utf8");
  const deployment = JSON.parse(raw);

  const conn = await hre.network.connect();
  const { ethers, provider } = conn;

  const [, buyer] = await ethers.getSigners();
  const auction = await ethers.getContractAt("PulseAuction", deployment.contracts.pulseAuction);
  const adapter = await ethers.getContractAt("PathMinterAdapter", deployment.contracts.pathMinterAdapter);
  const nft = await ethers.getContractAt("PathNFT", deployment.contracts.pathNft);
  const minter = await ethers.getContractAt("PathMinter", deployment.contracts.pathMinter);

  const tokenIdBefore = await minter.nextId();
  const curveActive = await auction.curveActive();
  const k = toBigInt(await auction.curveK());
  const genesisPrice = toBigInt(await auction.genesisPrice());
  const openTime = toBigInt(await auction.openTime());
  const stateBefore = await auction.getState();
  const latestBlock = await ethers.provider.getBlock("latest");
  const plannedTime = openTime > toBigInt(latestBlock.timestamp) + 1n
    ? openTime
    : toBigInt(latestBlock.timestamp) + 1n;

  const ask = curveActive
    ? askAt(plannedTime, k, toBigInt(stateBefore[2]), toBigInt(stateBefore[3]))
    : genesisPrice;

  const treasuryBefore = await ethers.provider.getBalance(deployment.treasury);
  const authorizedAuction = await adapter.getAuthorizedAuction();
  const minterTarget = await adapter.getMinterTarget();

  await provider.send("evm_setNextBlockTimestamp", [Number(plannedTime)]);
  const tx = await auction.connect(buyer).bid(ask, { value: ask });
  const receipt = await tx.wait();

  const treasuryAfter = await ethers.provider.getBalance(deployment.treasury);
  const owner = await nft.ownerOf(tokenIdBefore);
  const curveActiveAfter = await auction.curveActive();
  const epochIndex = await auction.epochIndex();
  const tokenIdAfter = await minter.nextId();
  const tokenBase = toBigInt(deployment.config.tokenBase ?? deployment.config.firstPublicId);
  const epochBase = toBigInt(deployment.config.epochBase ?? "1");
  const expectedTokenIdByEpoch = tokenBase + (toBigInt(epochIndex) - epochBase);
  const adapterChecks = {
    authorizedAuctionMatches: authorizedAuction.toLowerCase() === deployment.contracts.pulseAuction.toLowerCase(),
    minterTargetMatches: minterTarget.toLowerCase() === deployment.contracts.pathMinter.toLowerCase()
  };

  if (!Object.values(adapterChecks).every(Boolean)) {
    throw new Error(`adapter wiring check failed: ${JSON.stringify(adapterChecks)}`);
  }

  const summary = {
    deployFile,
    network: conn.networkName,
    buyer: buyer.address,
    txHash: receipt.hash,
    askWei: ask.toString(),
    treasuryDeltaWei: (treasuryAfter - treasuryBefore).toString(),
    mintedTokenId: tokenIdBefore.toString(),
    mintedOwner: owner,
    couplingExpectedTokenId: expectedTokenIdByEpoch.toString(),
    couplingMatchesEpoch: tokenIdBefore === expectedTokenIdByEpoch,
    nextIdAfter: tokenIdAfter.toString(),
    nextIdIncremented: tokenIdAfter === tokenIdBefore + 1n,
    curveActiveBefore: curveActive,
    curveActiveAfter,
    epochIndex: epochIndex.toString(),
    adapterChecks
  };

  console.log("[smoke-local-eth] bid executed");
  console.log(JSON.stringify(summary, null, 2));

  await conn.close();
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
