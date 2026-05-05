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

  async function deployAdapter(deployer) {
    const StubAdapter = await ethers.getContractFactory("StubPulseAdapter", deployer);
    const adapter = await StubAdapter.deploy(deployer.address);
    await adapter.waitForDeployment();
    return adapter;
  }

  async function futureOpenTime(offsetSec = 300n) {
    const latest = await ethers.provider.getBlock("latest");
    return BigInt(latest.timestamp) + offsetSec;
  }

  it("stores the exact constructor openTime", async function () {
    const [deployer] = await ethers.getSigners();
    const adapter = await deployAdapter(deployer);
    const openTime = await futureOpenTime(300n);

    const Auction = await ethers.getContractFactory("PulseAuction", deployer);
    const auction = await Auction.deploy(
      openTime,
      K,
      GENESIS_PRICE,
      GENESIS_FLOOR,
      PTS,
      ethers.ZeroAddress,
      deployer.address,
      await adapter.getAddress()
    );
    await auction.waitForDeployment();

    expect(await auction.openTime()).to.equal(openTime);
  });

  it("emits launch configuration", async function () {
    const [deployer] = await ethers.getSigners();
    const adapter = await deployAdapter(deployer);
    const openTime = await futureOpenTime(300n);
    const Auction = await ethers.getContractFactory("PulseAuction", deployer);

    const tx = await Auction.deploy(
      openTime,
      K,
      GENESIS_PRICE,
      GENESIS_FLOOR,
      PTS,
      ethers.ZeroAddress,
      deployer.address,
      await adapter.getAddress()
    );
    const auction = await tx.waitForDeployment();

    const deploymentTx = auction.deploymentTransaction();
    const deploymentReceipt = await deploymentTx.wait();
    const deploymentBlock = await ethers.provider.getBlock(deploymentReceipt.blockNumber);
    await expect(deploymentTx)
      .to.emit(auction, "LaunchConfigured")
      .withArgs(openTime, BigInt(deploymentBlock.timestamp));
  });

  it("rejects an openTime before deployment timestamp", async function () {
    const [deployer] = await ethers.getSigners();
    const adapter = await deployAdapter(deployer);
    const latest = await ethers.provider.getBlock("latest");
    const Auction = await ethers.getContractFactory("PulseAuction", deployer);

    await expect(
      Auction.deploy(
        BigInt(latest.timestamp) - 1n,
        K,
        GENESIS_PRICE,
        GENESIS_FLOOR,
        PTS,
        ethers.ZeroAddress,
        deployer.address,
        await adapter.getAddress()
      )
    ).to.be.revertedWith("OPEN_TIME_IN_PAST");
  });
});
