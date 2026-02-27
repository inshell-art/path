import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import hre from "hardhat";

const here = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_DEPLOY_FILE = path.resolve(here, "../deployments/localhost-eth.json");
const DEFAULT_BID_COUNT = 5;
const DEFAULT_WAIT_SEC = 5;

function parsePositiveInt(name, raw) {
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed < 1) {
    throw new Error(`${name} must be an integer >= 1 (received: ${raw})`);
  }
  return parsed;
}

function parseNonNegativeInt(name, raw) {
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new Error(`${name} must be an integer >= 0 (received: ${raw})`);
  }
  return parsed;
}

function toSerializable(value) {
  if (typeof value === "bigint") return value.toString();
  if (Array.isArray(value)) return value.map((v) => toSerializable(v));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, toSerializable(v)]));
  }
  return value;
}

function toBigInt(v) {
  return typeof v === "bigint" ? v : BigInt(v);
}

function askAt(now, k, anchor, floorPrice) {
  if (now <= anchor) return floorPrice + k;
  return floorPrice + k / (now - anchor);
}

async function main() {
  const deployFile = process.env.DEPLOY_FILE ?? DEFAULT_DEPLOY_FILE;
  const bidCount = parsePositiveInt("BID_COUNT", process.env.BID_COUNT ?? `${DEFAULT_BID_COUNT}`);
  const bidWaitSec = parseNonNegativeInt("BID_WAIT_SEC", process.env.BID_WAIT_SEC ?? `${DEFAULT_WAIT_SEC}`);

  const raw = await fs.readFile(deployFile, "utf8");
  const deployment = JSON.parse(raw);

  const conn = await hre.network.connect();
  const { ethers, provider } = conn;

  const [, buyer] = await ethers.getSigners();
  const auction = await ethers.getContractAt("PulseAuction", deployment.contracts.pulseAuction);
  const nft = await ethers.getContractAt("PathNFT", deployment.contracts.pathNft);
  const minter = await ethers.getContractAt("PathMinter", deployment.contracts.pathMinter);
  const k = toBigInt(await auction.curveK());
  const genesisPrice = toBigInt(await auction.genesisPrice());
  const openTime = toBigInt(await auction.openTime());

  const latestBlock = await ethers.provider.getBlock("latest");
  let saleTime = openTime > toBigInt(latestBlock.timestamp) + 1n
    ? openTime
    : toBigInt(latestBlock.timestamp) + 1n;

  const records = [];

  for (let i = 0; i < bidCount; i += 1) {
    if (i > 0) {
      saleTime += BigInt(bidWaitSec);
    }

    const tokenIdBefore = await minter.nextId();
    const curveActiveBefore = await auction.curveActive();
    const stateBefore = await auction.getState();
    const ask = curveActiveBefore
      ? askAt(saleTime, k, toBigInt(stateBefore[2]), toBigInt(stateBefore[3]))
      : genesisPrice;

    const treasuryBefore = await ethers.provider.getBalance(deployment.treasury);

    await provider.send("evm_setNextBlockTimestamp", [Number(saleTime)]);
    const tx = await auction.connect(buyer).bid(ask, { value: ask });
    const receipt = await tx.wait();

    const treasuryAfter = await ethers.provider.getBalance(deployment.treasury);
    const owner = await nft.ownerOf(tokenIdBefore);
    const tokenIdAfter = await minter.nextId();
    const epochIndex = await auction.epochIndex();

    records.push({
      step: i + 1,
      txHash: receipt.hash,
      bidWei: ask,
      tokenId: tokenIdBefore,
      mintedOwner: owner,
      nextIdAfter: tokenIdAfter,
      nextIdIncremented: tokenIdAfter === tokenIdBefore + 1n,
      curveActiveBefore,
      treasuryDeltaWei: treasuryAfter - treasuryBefore,
      treasuryDeltaMatchesBid: treasuryAfter - treasuryBefore === ask,
      epochIndex
    });
  }

  const allChecksPass = records.every(
    (r) =>
      r.mintedOwner.toLowerCase() === buyer.address.toLowerCase() &&
      r.nextIdIncremented &&
      r.treasuryDeltaMatchesBid
  );

  const report = {
    generatedAt: new Date().toISOString(),
    network: conn.networkName,
    chainId: Number((await ethers.provider.getNetwork()).chainId),
    deployFile,
    buyer: buyer.address,
    bidCount,
    bidWaitSec,
    contracts: deployment.contracts,
    records,
    summary: {
      steps: records.length,
      allChecksPass
    }
  };

  const reportsDir = path.resolve(here, "../deployments/reports");
  await fs.mkdir(reportsDir, { recursive: true });
  const outFile = path.join(reportsDir, `${conn.networkName}-serial-bids-eth-report.json`);
  await fs.writeFile(outFile, `${JSON.stringify(toSerializable(report), null, 2)}\n`, "utf8");

  console.log("[serial-bids-local-eth] completed");
  console.log(`report: ${outFile}`);
  console.log(JSON.stringify(toSerializable(report.summary), null, 2));

  await conn.close();
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
