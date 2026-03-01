import { expect } from "chai";
import hre from "hardhat";
import { FIRST_PUBLIC_ID, GENESIS_PRICE, K, PTS } from "./helpers/constants.js";
import { deployPathPulseErc20Env, deployPathPulseEthEnv, getSaleEventFromReceipt } from "./helpers/fixtures.js";
import { deriveGenesisState, deriveNextState, expectedAsk, priceAt } from "./helpers/pulseModel.js";
import { mine, setNextBlockTimestamp } from "./helpers/time.js";

describe("Path + Pulse ETH Integration (Solidity)", function () {
  let conn;
  let ethers;
  let provider;

  async function expectAnyRevert(txPromise) {
    try {
      await txPromise;
      expect.fail("expected tx to revert");
    } catch (error) {
      expect(error).to.exist;
    }
  }

  beforeEach(async function () {
    conn = await hre.network.connect();
    ethers = conn.ethers;
    provider = conn.provider;
  });

  afterEach(async function () {
    await conn.close();
  });

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

  it("blocks bids before open time and allows at open", async function () {
    const { auction, alice } = await deployPathPulseEthEnv(ethers, { startDelaySec: 120n });

    await expect(auction.connect(alice).bid(GENESIS_PRICE, { value: GENESIS_PRICE })).to.be.revertedWith(
      "AUCTION_NOT_OPEN"
    );

    const openTime = await auction.openTime();
    await setNextBlockTimestamp(provider, openTime);

    const ask = await quoteAskAt(auction, openTime);
    await (await auction.connect(alice).bid(ask, { value: ask })).wait();
  });

  it("genesis bid mints PATH token and activates curve", async function () {
    const { auction, nft, alice, treasury } = await deployPathPulseEthEnv(ethers, { startDelaySec: 0n });

    const ask = await auction.getCurrentPrice();
    const treasuryBefore = await ethers.provider.getBalance(treasury.address);

    const receipt = await (await auction.connect(alice).bid(ask, { value: ask })).wait();
    const sale = await getSaleEventFromReceipt(auction, receipt);

    const treasuryAfter = await ethers.provider.getBalance(treasury.address);

    expect(await nft.ownerOf(FIRST_PUBLIC_ID)).to.equal(alice.address);
    expect(await auction.curveActive()).to.equal(true);
    expect(await auction.epochIndex()).to.equal(1n);
    expect(sale.epochIndex).to.equal(1n);
    expect(treasuryAfter - treasuryBefore).to.equal(ask);
  });

  it("refunds ETH overpayment and only forwards ask to treasury", async function () {
    const { auction, alice, treasury } = await deployPathPulseEthEnv(ethers, { startDelaySec: 0n });
    const auctionAddr = await auction.getAddress();

    const ask = await auction.getCurrentPrice();
    const overpay = ask + 123n;
    const treasuryBefore = await ethers.provider.getBalance(treasury.address);

    await (await auction.connect(alice).bid(ask, { value: overpay })).wait();

    const treasuryAfter = await ethers.provider.getBalance(treasury.address);
    const auctionBalance = await ethers.provider.getBalance(auctionAddr);

    expect(treasuryAfter - treasuryBefore).to.equal(ask);
    expect(auctionBalance).to.equal(0n);
  });

  it("settles ERC20 payment path and rejects accidental ETH", async function () {
    const { auction, paymentToken, alice, treasury, nft } = await deployPathPulseErc20Env(ethers, { startDelaySec: 0n });
    const ask = await auction.getCurrentPrice();
    const mintAmount = ask * 2n;

    await (await paymentToken.mint(alice.address, mintAmount)).wait();
    await (await paymentToken.connect(alice).approve(await auction.getAddress(), mintAmount)).wait();

    await expect(auction.connect(alice).bid(ask, { value: 1n })).to.be.revertedWith("ETH_NOT_ACCEPTED");

    const treasuryBefore = await paymentToken.balanceOf(treasury.address);

    await (await auction.connect(alice).bid(ask)).wait();

    const treasuryAfter = await paymentToken.balanceOf(treasury.address);
    expect(treasuryAfter - treasuryBefore).to.equal(ask);
    expect(await paymentToken.balanceOf(alice.address)).to.equal(mintAmount - ask);
    expect(await nft.ownerOf(FIRST_PUBLIC_ID)).to.equal(alice.address);
  });

  it("fixture freezes sales caller to adapter before first sale", async function () {
    const { auction, adapter, minter, bob, roles } = await deployPathPulseEthEnv(ethers, { startDelaySec: 0n });

    expect(await minter.salesCaller()).to.equal(await adapter.getAddress());
    expect(await minter.salesCallerFrozen()).to.equal(true);
    expect(await minter.getRoleAdmin(roles.SALES_ROLE)).to.equal(await minter.FROZEN_SALES_ADMIN_ROLE());
    expect(await minter.hasRole(roles.SALES_ROLE, await adapter.getAddress())).to.equal(true);
    await expectAnyRevert(minter.grantRole(roles.SALES_ROLE, bob.address));

    const ask = await auction.getCurrentPrice();
    await (await auction.bid(ask, { value: ask })).wait();
  });

  it("reverts settlement when sales caller is frozen to a non-adapter address", async function () {
    const [deployer] = await ethers.getSigners();
    const { auction, adapter, minter, alice } = await deployPathPulseEthEnv(ethers, {
      startDelaySec: 0n,
      freezeSalesCallerTo: deployer.address
    });

    const ask = await auction.getCurrentPrice();

    await expect(auction.connect(alice).bid(ask, { value: ask }))
      .to.be.revertedWithCustomError(minter, "BadSalesCaller")
      .withArgs(await adapter.getAddress(), deployer.address);
  });

  it("second bid in later block mints next token id", async function () {
    const { auction, nft, alice, bob } = await deployPathPulseEthEnv(ethers, { startDelaySec: 0n });

    const t1 = (await auction.openTime()) + 1_000n;
    const t2 = t1 + 12n;

    await setNextBlockTimestamp(provider, t1);
    let ask = await quoteAskAt(auction, t1);
    await (await auction.connect(alice).bid(ask, { value: ask })).wait();

    await setNextBlockTimestamp(provider, t2);
    ask = await quoteAskAt(auction, t2);
    await (await auction.connect(bob).bid(ask, { value: ask })).wait();

    expect(await nft.ownerOf(FIRST_PUBLIC_ID)).to.equal(alice.address);
    expect(await nft.ownerOf(FIRST_PUBLIC_ID + 1n)).to.equal(bob.address);
    expect(await auction.epochIndex()).to.equal(2n);
  });

  it("matches hyperbolic ask model after second sale", async function () {
    const { auction, alice } = await deployPathPulseEthEnv(ethers, { startDelaySec: 0n });

    const t1 = (await auction.openTime()) + 1_000n;
    const t2 = t1 + 10n;
    const t3 = t2 + 10n;

    await setNextBlockTimestamp(provider, t1);
    await (await auction.connect(alice).bid(GENESIS_PRICE, { value: GENESIS_PRICE })).wait();

    const anchor1 = deriveGenesisState({
      t: t1,
      genesisPrice: GENESIS_PRICE,
      genesisFloor: 900n,
      k: K
    }).anchorTime;

    const lastPriceAtT2 = priceAt(t2, K, anchor1, 900n);

    await setNextBlockTimestamp(provider, t2);
    const ask2 = await quoteAskAt(auction, t2);
    await (await auction.connect(alice).bid(ask2, { value: ask2 })).wait();

    const model = deriveNextState({
      now: t2,
      lastPrice: lastPriceAtT2,
      previousStartTime: t1,
      k: K,
      pts: PTS,
      currentEpochIndex: 1n
    });

    await setNextBlockTimestamp(provider, t3);
    await mine(provider);

    const onchain = await auction.getCurrentPrice();
    const expected = expectedAsk({
      now: t3,
      curveActive: true,
      genesisPrice: GENESIS_PRICE,
      k: K,
      anchorTime: model.anchorTime,
      floorPrice: model.floorPrice
    });

    expect(onchain).to.equal(expected);
  });

  it("enforces one bid per block", async function () {
    const { auction, alice } = await deployPathPulseEthEnv(ethers, { startDelaySec: 0n });

    const Batcher = await ethers.getContractFactory("BidBatcher", alice);
    const batcher = await Batcher.deploy();
    await batcher.waitForDeployment();

    const t1 = (await auction.openTime()) + 1_000n;
    await setNextBlockTimestamp(provider, t1);

    const ask = await quoteAskAt(auction, t1);
    await expect(
      batcher.connect(alice).bidTwice(await auction.getAddress(), ask, ask, { value: ask * 2n })
    ).to.be.revertedWith("ONE_BID_PER_BLOCK");
  });

  it("handles 20 sequential bids without breaking settlement", async function () {
    const { auction, nft, alice } = await deployPathPulseEthEnv(ethers, { startDelaySec: 0n });

    let saleTime = (await auction.openTime()) + 1_000n;
    const totalBids = 20n;

    for (let i = 0n; i < totalBids; i += 1n) {
      if (i > 0n) {
        saleTime += 5n;
      }

      await setNextBlockTimestamp(provider, saleTime);
      const ask = await quoteAskAt(auction, saleTime);
      await (await auction.connect(alice).bid(ask, { value: ask })).wait();

      expect(await nft.ownerOf(FIRST_PUBLIC_ID + i)).to.equal(alice.address);
    }

    expect(await auction.epochIndex()).to.equal(totalBids);
    expect(await auction.curveActive()).to.equal(true);
  });

  it("pump component gets larger when waiting longer between sales", async function () {
    const shortEnv = await deployPathPulseEthEnv(ethers, { startDelaySec: 0n });
    const longEnv = await deployPathPulseEthEnv(ethers, { startDelaySec: 0n });

    const t1Short = (await shortEnv.auction.openTime()) + 1_000n;
    const t1Long = (await longEnv.auction.openTime()) + 2_000n;
    const t2Short = t1Short + 5n;
    const t2Long = t1Long + 30n;

    await setNextBlockTimestamp(provider, t1Short);
    await (await shortEnv.auction.connect(shortEnv.alice).bid(GENESIS_PRICE, { value: GENESIS_PRICE })).wait();

    await setNextBlockTimestamp(provider, t2Short);
    const askShort = await quoteAskAt(shortEnv.auction, t2Short);
    await (await shortEnv.auction.connect(shortEnv.alice).bid(askShort, { value: askShort })).wait();

    await setNextBlockTimestamp(provider, t1Long);
    await (await longEnv.auction.connect(longEnv.alice).bid(GENESIS_PRICE, { value: GENESIS_PRICE })).wait();

    await setNextBlockTimestamp(provider, t2Long);
    const askLong = await quoteAskAt(longEnv.auction, t2Long);
    await (await longEnv.auction.connect(longEnv.alice).bid(askLong, { value: askLong })).wait();

    const [, shortStart, shortAnchor, shortFloor] = await shortEnv.auction.getState();
    const [, longStart, longAnchor, longFloor] = await longEnv.auction.getState();

    const shortImmediateAsk = expectedAsk({
      now: shortStart,
      curveActive: true,
      genesisPrice: GENESIS_PRICE,
      k: K,
      anchorTime: shortAnchor,
      floorPrice: shortFloor
    });

    const longImmediateAsk = expectedAsk({
      now: longStart,
      curveActive: true,
      genesisPrice: GENESIS_PRICE,
      k: K,
      anchorTime: longAnchor,
      floorPrice: longFloor
    });

    const shortPump = shortImmediateAsk - shortFloor;
    const longPump = longImmediateAsk - longFloor;

    expect(shortPump).to.equal(5n);
    expect(longPump).to.equal(30n);
    expect(longPump).to.be.greaterThan(shortPump);
  });
});
