import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import hre from "hardhat";

const START_DELAY_SEC = 0n;
const K = 600n;
const GENESIS_PRICE = 1_000n;
const GENESIS_FLOOR = 900n;
const PTS = 1n;
const FIRST_PUBLIC_ID = 1n;
const EPOCH_BASE = 1n;
const RESERVED_CAP = 3n;

const NAME = "PATH NFT";
const SYMBOL = "PATH";
const BASE_URI = "";

const here = path.dirname(fileURLToPath(import.meta.url));

async function main() {
  const conn = await hre.network.connect();
  const { ethers } = conn;

  const [deployer, , treasury] = await ethers.getSigners();
  const networkInfo = await ethers.provider.getNetwork();
  const minterRole = ethers.id("MINTER_ROLE");
  const salesRole = ethers.id("SALES_ROLE");

  const PathNFT = await ethers.getContractFactory("PathNFT", deployer);
  const nft = await PathNFT.deploy(
    deployer.address,
    NAME,
    SYMBOL,
    BASE_URI
  );
  await nft.waitForDeployment();

  const PathMinter = await ethers.getContractFactory("PathMinter", deployer);
  const minter = await PathMinter.deploy(
    deployer.address,
    await nft.getAddress(),
    FIRST_PUBLIC_ID,
    RESERVED_CAP
  );
  await minter.waitForDeployment();

  const PathMinterAdapter = await ethers.getContractFactory("PathMinterAdapter", deployer);
  const adapter = await PathMinterAdapter.deploy(
    deployer.address,
    ethers.ZeroAddress,
    await minter.getAddress(),
    FIRST_PUBLIC_ID,
    EPOCH_BASE
  );
  await adapter.waitForDeployment();

  const PulseAuction = await ethers.getContractFactory("PulseAuction", deployer);
  const auction = await PulseAuction.deploy(
    START_DELAY_SEC,
    K,
    GENESIS_PRICE,
    GENESIS_FLOOR,
    PTS,
    ethers.ZeroAddress,
    treasury.address,
    await adapter.getAddress()
  );
  await auction.waitForDeployment();

  await (await adapter.setAuction(await auction.getAddress())).wait();
  await (await adapter.freezeWiring()).wait();
  await (await nft.grantRole(minterRole, await minter.getAddress())).wait();
  await (await minter.grantRole(salesRole, await adapter.getAddress())).wait();
  await (await minter.freezeSalesCaller(await adapter.getAddress())).wait();

  const deployment = {
    network: conn.networkName,
    chainId: Number(networkInfo.chainId),
    deployer: deployer.address,
    treasury: treasury.address,
    paymentToken: ethers.ZeroAddress,
    contracts: {
      pathNft: await nft.getAddress(),
      pathMinter: await minter.getAddress(),
      pathMinterAdapter: await adapter.getAddress(),
      pulseAuction: await auction.getAddress()
    },
    config: {
      name: NAME,
      symbol: SYMBOL,
      baseUri: BASE_URI,
      startDelaySec: START_DELAY_SEC.toString(),
      k: K.toString(),
      genesisPrice: GENESIS_PRICE.toString(),
      genesisFloor: GENESIS_FLOOR.toString(),
      pts: PTS.toString(),
      firstPublicId: FIRST_PUBLIC_ID.toString(),
      tokenBase: FIRST_PUBLIC_ID.toString(),
      epochBase: EPOCH_BASE.toString(),
      reservedCap: RESERVED_CAP.toString()
    },
    roles: {
      minterRole,
      salesRole
    }
  };

  const deploymentsDir = path.resolve(here, "../deployments");
  await fs.mkdir(deploymentsDir, { recursive: true });
  const outFile = path.join(deploymentsDir, `${conn.networkName}-eth.json`);
  await fs.writeFile(outFile, `${JSON.stringify(deployment, null, 2)}\n`, "utf8");

  console.log(`[deploy-local-eth] deployment saved to ${outFile}`);
  console.log(JSON.stringify(deployment, null, 2));

  await conn.close();
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
