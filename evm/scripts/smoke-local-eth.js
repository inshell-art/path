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
  const adapter = await ethers.getContractAt("PathPulseAdapter", deployment.contracts.pathPulseAdapter);
  const nft = await ethers.getContractAt("PathNFT", deployment.contracts.pathNft);

  const tokenBase = toBigInt(deployment.config.tokenBase ?? deployment.config.firstPublicId);
  const epochBase = toBigInt(deployment.config.epochBase ?? "1");
  const epochBefore = toBigInt(await auction.getEpochIndex());
  const nextSaleEpoch = epochBefore + 1n;
  if (nextSaleEpoch < epochBase) {
    throw new Error(`next sale epoch ${nextSaleEpoch} is below epochBase ${epochBase}`);
  }
  const expectedTokenId = tokenBase + (nextSaleEpoch - epochBase);
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
  const pathNftTarget = await adapter.getPathNftTarget();

  await provider.send("evm_setNextBlockTimestamp", [Number(plannedTime)]);
  const tx = await auction.connect(buyer).bid(ask, { value: ask });
  const receipt = await tx.wait();

  const treasuryAfter = await ethers.provider.getBalance(deployment.treasury);
  const owner = await nft.ownerOf(expectedTokenId);
  const curveActiveAfter = await auction.curveActive();
  const epochIndex = await auction.epochIndex();
  const expectedTokenIdByEpoch = tokenBase + (toBigInt(epochIndex) - epochBase);
  const adapterChecks = {
    authorizedAuctionMatches: authorizedAuction.toLowerCase() === deployment.contracts.pulseAuction.toLowerCase(),
    pathNftTargetMatches: pathNftTarget.toLowerCase() === deployment.contracts.pathNft.toLowerCase()
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
    mintedTokenId: expectedTokenId.toString(),
    mintedOwner: owner,
    couplingExpectedTokenId: expectedTokenIdByEpoch.toString(),
    couplingMatchesEpoch: expectedTokenId === expectedTokenIdByEpoch,
    epochBefore: epochBefore.toString(),
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
