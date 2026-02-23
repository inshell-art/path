import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import hre from "hardhat";

const here = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_DEPLOY_FILE = path.resolve(here, "../deployments/localhost-eth.json");

async function main() {
  const deployFile = process.env.DEPLOY_FILE ?? DEFAULT_DEPLOY_FILE;
  const raw = await fs.readFile(deployFile, "utf8");
  const deployment = JSON.parse(raw);

  const conn = await hre.network.connect();
  const { ethers } = conn;

  const [, buyer] = await ethers.getSigners();
  const auction = await ethers.getContractAt("PulseAuction", deployment.contracts.pulseAuction);
  const nft = await ethers.getContractAt("PathNFT", deployment.contracts.pathNft);

  const firstId = BigInt(deployment.config.firstPublicId);
  const ask = await auction.getCurrentPrice();
  const treasuryBefore = await ethers.provider.getBalance(deployment.treasury);

  const tx = await auction.connect(buyer).bid(ask, { value: ask });
  const receipt = await tx.wait();

  const treasuryAfter = await ethers.provider.getBalance(deployment.treasury);
  const owner = await nft.ownerOf(firstId);
  const curveActive = await auction.curveActive();
  const epochIndex = await auction.epochIndex();

  const summary = {
    deployFile,
    network: conn.networkName,
    buyer: buyer.address,
    txHash: receipt.hash,
    askWei: ask.toString(),
    treasuryDeltaWei: (treasuryAfter - treasuryBefore).toString(),
    mintedTokenId: firstId.toString(),
    mintedOwner: owner,
    curveActive,
    epochIndex: epochIndex.toString()
  };

  console.log("[smoke-local-eth] bid executed");
  console.log(JSON.stringify(summary, null, 2));

  await conn.close();
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
