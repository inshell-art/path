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

  it("stores explicit openTime value", async function () {
    const [deployer] = await ethers.getSigners();
    const latestBlock = await ethers.provider.getBlock("latest");
    const openTime = BigInt(latestBlock.timestamp) + 300n;

    const Auction = await ethers.getContractFactory("PulseAuction", deployer);
    const auction = await Auction.deploy(
      openTime,
      K,
      GENESIS_PRICE,
      GENESIS_FLOOR,
      PTS,
      ethers.ZeroAddress,
      deployer.address,
      deployer.address
    );
    await auction.waitForDeployment();

    expect(await auction.openTime()).to.equal(openTime);
  });

  it("reverts when openTime is in the past", async function () {
    const [deployer] = await ethers.getSigners();
    const Auction = await ethers.getContractFactory("PulseAuction", deployer);

    await expect(
      Auction.deploy(
        0n,
        K,
        GENESIS_PRICE,
        GENESIS_FLOOR,
        PTS,
        ethers.ZeroAddress,
        deployer.address,
        deployer.address
      )
    ).to.be.revertedWith("OPEN_TIME_IN_PAST");
  });
});
