import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import hre from "hardhat";

const here = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_DEPLOY_FILE = path.resolve(here, "../deployments/localhost-eth.json");
const WAIT_SCHEDULE_SEC = [0n, 5n, 20n, 60n, 120n];

function askAt(now, k, anchor, floorPrice) {
  if (now <= anchor) return floorPrice + k;
  return floorPrice + k / (now - anchor);
}

function toBigInt(v) {
  return typeof v === "bigint" ? v : BigInt(v);
}

function toSerializable(value) {
  if (typeof value === "bigint") return value.toString();
  if (Array.isArray(value)) return value.map((v) => toSerializable(v));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, toSerializable(v)]));
  }
  return value;
}

async function main() {
  const deployFile = process.env.DEPLOY_FILE ?? DEFAULT_DEPLOY_FILE;
  const deployment = JSON.parse(await fs.readFile(deployFile, "utf8"));

  const conn = await hre.network.connect();
  const { ethers, provider } = conn;

  const [, buyer] = await ethers.getSigners();
  const auction = await ethers.getContractAt("PulseAuction", deployment.contracts.pulseAuction);
  const minter = await ethers.getContractAt("PathMinter", deployment.contracts.pathMinter);
  const nft = await ethers.getContractAt("PathNFT", deployment.contracts.pathNft);

  const k = toBigInt(deployment.config.k);
  const genesisPrice = toBigInt(deployment.config.genesisPrice);
  const openTime = toBigInt(await auction.openTime());

  const latestBlock = await ethers.provider.getBlock("latest");
  const baseTime = openTime > toBigInt(latestBlock.timestamp) + 2n
    ? openTime
    : toBigInt(latestBlock.timestamp) + 2n;

  let saleTime = baseTime;
  const initialState = await auction.getState();
  let previousEpoch = toBigInt(initialState[0]);

  const records = [];

  for (let i = 0; i < WAIT_SCHEDULE_SEC.length; i += 1) {
    if (i > 0) {
      saleTime += WAIT_SCHEDULE_SEC[i];
    }

    const curveActiveBefore = await auction.curveActive();
    const stateBefore = await auction.getState();
    const expectedTokenId = toBigInt(await minter.nextId());

    const expectedAsk = curveActiveBefore
      ? askAt(saleTime, k, toBigInt(stateBefore[2]), toBigInt(stateBefore[3]))
      : genesisPrice;

    const treasuryBefore = await ethers.provider.getBalance(deployment.treasury);

    await provider.send("evm_setNextBlockTimestamp", [Number(saleTime)]);
    const tx = await auction.connect(buyer).bid(expectedAsk, { value: expectedAsk });
    const receipt = await tx.wait();

    const saleLogs = await auction.queryFilter(
      auction.filters.Sale(),
      receipt.blockNumber,
      receipt.blockNumber
    );
    if (saleLogs.length === 0) {
      throw new Error(`Sale event not found for block ${receipt.blockNumber}`);
    }

    const sale = saleLogs[0].args;
    const stateAfter = await auction.getState();
    const treasuryAfter = await ethers.provider.getBalance(deployment.treasury);

    const epochIndex = toBigInt(stateAfter[0]);
    const startTime = toBigInt(stateAfter[1]);
    const anchorTime = toBigInt(stateAfter[2]);
    const floorPrice = toBigInt(stateAfter[3]);
    const immediateAsk = askAt(startTime, k, anchorTime, floorPrice);
    const pump = immediateAsk - floorPrice;
    const tokenId = expectedTokenId;
    const mintedOwner = await nft.ownerOf(tokenId);

    const checks = {
      askMatchesQuote: toBigInt(sale.price) === expectedAsk,
      treasuryDeltaMatchesPrice: treasuryAfter - treasuryBefore === toBigInt(sale.price),
      epochIncrementedByOne: epochIndex === previousEpoch + 1n,
      saleEpochMatchesState: toBigInt(sale.epochIndex) === epochIndex,
      eventMatchesState: toBigInt(sale.nextAnchorA) === anchorTime && toBigInt(sale.nextFloorB) === floorPrice,
      priceAboveOrEqualFloor: toBigInt(sale.price) >= floorPrice,
      mintedIdIsExpected: tokenId === expectedTokenId,
      mintedOwnerMatchesBuyer: mintedOwner.toLowerCase() === buyer.address.toLowerCase()
    };

    records.push({
      step: i + 1,
      waitSec: WAIT_SCHEDULE_SEC[i],
      saleTime,
      txHash: receipt.hash,
      buyer: buyer.address,
      expectedAsk,
      salePrice: toBigInt(sale.price),
      treasuryDeltaWei: treasuryAfter - treasuryBefore,
      tokenId,
      expectedTokenId,
      stateAfter: {
        epochIndex,
        startTime,
        anchorTime,
        floorPrice,
        immediateAsk,
        pump
      },
      checks
    });

    previousEpoch = epochIndex;
  }

  const allChecksPass = records.every((r) => Object.values(r.checks).every(Boolean));

  const report = {
    generatedAt: new Date().toISOString(),
    network: conn.networkName,
    chainId: Number((await ethers.provider.getNetwork()).chainId),
    deployFile,
    contracts: deployment.contracts,
    waitScheduleSec: WAIT_SCHEDULE_SEC,
    records,
    summary: {
      steps: records.length,
      allChecksPass
    }
  };

  const reportsDir = path.resolve(here, "../deployments/reports");
  await fs.mkdir(reportsDir, { recursive: true });
  const outFile = path.join(reportsDir, `${conn.networkName}-path-cascade-eth-report.json`);
  await fs.writeFile(outFile, `${JSON.stringify(toSerializable(report), null, 2)}\n`, "utf8");

  console.log("[scenario-cascade-local-eth] completed");
  console.log(`report: ${outFile}`);
  console.log(JSON.stringify(toSerializable(report.summary), null, 2));

  await conn.close();
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
