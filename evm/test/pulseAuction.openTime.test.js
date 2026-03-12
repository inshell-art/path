import { expect } from "chai";
import hre from "hardhat";
import { GENESIS_FLOOR, GENESIS_PRICE, K, PTS } from "./helpers/constants.js";

describe("PulseAuction openTime constructor", function () {
  let conn;
  let ethers;

  beforeEach(async function () {
    conn = await hre.network.connect();
    ethers = conn.ethers;
  });

  afterEach(async function () {
    await conn.close();
  });

  it("stores openTime as deployment timestamp plus startDelaySec", async function () {
    const [deployer] = await ethers.getSigners();
    const startDelaySec = 300n;

    const Auction = await ethers.getContractFactory("PulseAuction", deployer);
    const auction = await Auction.deploy(
      startDelaySec,
      K,
      GENESIS_PRICE,
      GENESIS_FLOOR,
      PTS,
      ethers.ZeroAddress,
      deployer.address,
      deployer.address
    );
    await auction.waitForDeployment();

    const deploymentTx = auction.deploymentTransaction();
    const deploymentReceipt = await deploymentTx.wait();
    const deploymentBlock = await ethers.provider.getBlock(deploymentReceipt.blockNumber);
    expect(await auction.openTime()).to.equal(BigInt(deploymentBlock.timestamp) + startDelaySec);
  });

  it("supports zero start delay", async function () {
    const [deployer] = await ethers.getSigners();
    const Auction = await ethers.getContractFactory("PulseAuction", deployer);

    const auction = await Auction.deploy(
      0n,
      K,
      GENESIS_PRICE,
      GENESIS_FLOOR,
      PTS,
      ethers.ZeroAddress,
      deployer.address,
      deployer.address
    );
    await auction.waitForDeployment();

    const deploymentTx = auction.deploymentTransaction();
    const deploymentReceipt = await deploymentTx.wait();
    const deploymentBlock = await ethers.provider.getBlock(deploymentReceipt.blockNumber);
    expect(await auction.openTime()).to.equal(BigInt(deploymentBlock.timestamp));
  });
});
