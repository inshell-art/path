import { expect } from "chai";
import hre from "hardhat";
import { GENESIS_FLOOR, GENESIS_PRICE, K, PTS } from "./helpers/constants.js";
import { deployPathPulseEthEnv } from "./helpers/fixtures.js";
import { setNextBlockTimestamp } from "./helpers/time.js";

describe("PulseAuction (Solidity)", function () {
  let conn;
  let ethers;
  let provider;

  beforeEach(async function () {
    conn = await hre.network.connect();
    ethers = conn.ethers;
    provider = conn.provider;
  });

  afterEach(async function () {
    await conn.close();
  });

  async function deployAuction({
    startDelaySec = 0n,
    k = K,
    genesisPrice = GENESIS_PRICE,
    genesisFloor = GENESIS_FLOOR,
    pts = PTS,
    paymentToken = ethers.ZeroAddress,
    treasury,
    mintAdapter = ethers.ZeroAddress
  } = {}) {
    const [deployer] = await ethers.getSigners();
    const Auction = await ethers.getContractFactory("PulseAuction", deployer);
    const auction = await Auction.deploy(
      startDelaySec,
      k,
      genesisPrice,
      genesisFloor,
      pts,
      paymentToken,
      treasury ?? deployer.address,
      mintAdapter
    );
    await auction.waitForDeployment();
    return { deployer, auction };
  }

  async function quoteAskAt(auction, saleTime) {
    const active = await auction.curveActive();
    if (!active) {
      return GENESIS_PRICE;
    }

    const [, , anchorTime, floorPrice] = await auction.getState();
    if (saleTime <= anchorTime) {
      return floorPrice + K;
    }

    return floorPrice + K / (saleTime - anchorTime);
  }

  it("constructor rejects invalid pricing params", async function () {
    const [deployer] = await ethers.getSigners();
    const Auction = await ethers.getContractFactory("PulseAuction", deployer);

    await expect(
      Auction.deploy(0n, 0n, GENESIS_PRICE, GENESIS_FLOOR, PTS, ethers.ZeroAddress, deployer.address, deployer.address)
    ).to.be.revertedWith("K_ZERO_OR_NEGATIVE");

    await expect(
      Auction.deploy(0n, K, GENESIS_FLOOR, GENESIS_FLOOR, PTS, ethers.ZeroAddress, deployer.address, deployer.address)
    ).to.be.revertedWith("GAP_ZERO_OR_NEGATIVE");

    await expect(
      Auction.deploy(0n, 50n, 1_000n, 900n, PTS, ethers.ZeroAddress, deployer.address, deployer.address)
    ).to.be.revertedWith("START_GAP_ABOVE_K");

    await expect(
      Auction.deploy(0n, K, GENESIS_PRICE, GENESIS_FLOOR, 0n, ethers.ZeroAddress, deployer.address, deployer.address)
    ).to.be.revertedWith("PTS_ZERO_OR_NEGATIVE");

    await expect(
      Auction.deploy(
        0n,
        K,
        GENESIS_PRICE,
        GENESIS_FLOOR,
        (1n << 128n) + 1n,
        ethers.ZeroAddress,
        deployer.address,
        deployer.address
      )
    ).to.be.revertedWith("PTS_OUT_OF_RANGE");

    await expect(
      Auction.deploy(
        0n,
        (1n << 64n) + 1n,
        GENESIS_PRICE,
        GENESIS_FLOOR,
        1n,
        ethers.ZeroAddress,
        deployer.address,
        deployer.address
      )
    ).to.be.revertedWith("K_OVER_PTS_OVERFLOW");

    await expect(
      Auction.deploy(0n, K, GENESIS_PRICE, GENESIS_FLOOR, PTS, ethers.ZeroAddress, ethers.ZeroAddress, deployer.address)
    ).to.be.revertedWith("ZERO_TREASURY");

    await expect(
      Auction.deploy(0n, K, GENESIS_PRICE, GENESIS_FLOOR, PTS, deployer.address, deployer.address, deployer.address)
    ).to.be.revertedWith("INVALID_PAYMENT_TOKEN");

    await expect(
      Auction.deploy(0n, K, GENESIS_PRICE, GENESIS_FLOOR, PTS, ethers.ZeroAddress, deployer.address, deployer.address)
    ).to.be.revertedWith("INVALID_ADAPTER");
  });

  it("initializeMintAdapter is deployer-only, rejects zero, and is one-shot", async function () {
    const { deployer, auction } = await deployAuction({ mintAdapter: ethers.ZeroAddress });
    const [, alice, bob] = await ethers.getSigners();

    const StubAdapter = await ethers.getContractFactory("StubPulseAdapter", deployer);
    const stubAdapter = await StubAdapter.deploy(bob.address);
    await stubAdapter.waitForDeployment();

    await expect(auction.connect(alice).initializeMintAdapter(bob.address)).to.be.revertedWith("ONLY_DEPLOYER");
    await expect(auction.initializeMintAdapter(ethers.ZeroAddress)).to.be.revertedWith("INVALID_ADAPTER");
    await expect(auction.initializeMintAdapter(bob.address)).to.be.revertedWith("INVALID_ADAPTER");

    await (await auction.initializeMintAdapter(await stubAdapter.getAddress())).wait();
    expect(await auction.mintAdapter()).to.equal(await stubAdapter.getAddress());

    await expect(auction.initializeMintAdapter(deployer.address)).to.be.revertedWith("ADAPTER_ALREADY_SET");
  });

  it("bid rejects maxPrice below current ask", async function () {
    const { auction, alice } = await deployPathPulseEthEnv(ethers, { startDelaySec: 0n });
    const openTime = await auction.openTime();
    const latestBlock = await ethers.provider.getBlock("latest");
    const saleTime = openTime > BigInt(latestBlock.timestamp) + 1n
      ? openTime
      : BigInt(latestBlock.timestamp) + 1n;
    await setNextBlockTimestamp(provider, saleTime);

    const ask = await quoteAskAt(auction, saleTime);
    await expect(auction.connect(alice).bid(ask - 1n, { value: ask })).to.be.revertedWith("ASK_ABOVE_MAX_PRICE");
  });

  it("bid rejects when adapter is not set", async function () {
    const { auction } = await deployAuction({ startDelaySec: 0n, mintAdapter: ethers.ZeroAddress });
    const openTime = await auction.openTime();
    const latestBlock = await ethers.provider.getBlock("latest");
    const saleTime = openTime > BigInt(latestBlock.timestamp) + 1n
      ? openTime
      : BigInt(latestBlock.timestamp) + 1n;
    await setNextBlockTimestamp(provider, saleTime);

    const ask = await quoteAskAt(auction, saleTime);
    await expect(auction.bid(ask, { value: ask })).to.be.revertedWith("ADAPTER_NOT_SET");
  });

  it("bid rejects ETH underpayment on the ETH settlement path", async function () {
    const { auction, alice } = await deployPathPulseEthEnv(ethers, { startDelaySec: 0n });
    const openTime = await auction.openTime();
    const latestBlock = await ethers.provider.getBlock("latest");
    const saleTime = openTime > BigInt(latestBlock.timestamp) + 1n
      ? openTime
      : BigInt(latestBlock.timestamp) + 1n;
    await setNextBlockTimestamp(provider, saleTime);

    const ask = await quoteAskAt(auction, saleTime);
    await expect(auction.connect(alice).bid(ask, { value: ask - 1n })).to.be.revertedWith("INVALID_MSG_VALUE");
  });
});
