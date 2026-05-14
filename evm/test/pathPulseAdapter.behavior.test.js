import { expect } from "chai";
import hre from "hardhat";
import { deployPathNftEnv } from "./helpers/fixtures.js";

describe("PathPulseAdapter (Solidity)", function () {
  let conn;
  let ethers;

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
  });

  afterEach(async function () {
    await conn.close();
  });

  async function deployFixture({ tokenBase = 100n, epochBase = 1n, freezeWiring = false } = {}) {
    const [deployer, alice, bob] = await ethers.getSigners();
    const nftEnv = await deployPathNftEnv(ethers, { admin: deployer.address });

    const StubAuction = await ethers.getContractFactory("StubPulseAuction", deployer);
    const auction = await StubAuction.deploy();
    await auction.waitForDeployment();

    const Adapter = await ethers.getContractFactory("PathPulseAdapter", deployer);
    const adapter = await Adapter.deploy(
      deployer.address,
      await auction.getAddress(),
      await nftEnv.nft.getAddress(),
      tokenBase,
      epochBase
    );
    await adapter.waitForDeployment();

    await (await nftEnv.nft.grantRole(nftEnv.roles.MINTER_ROLE, await adapter.getAddress())).wait();
    await (await nftEnv.nft.freezePublicMinter(await adapter.getAddress())).wait();

    if (freezeWiring) {
      await (await adapter.freezeWiring()).wait();
    }

    return { deployer, alice, bob, ...nftEnv, auction, adapter, tokenBase, epochBase };
  }

  it("constructor permits zero auction for deferred wiring", async function () {
    const [deployer] = await ethers.getSigners();
    const nftEnv = await deployPathNftEnv(ethers, { admin: deployer.address });

    const Adapter = await ethers.getContractFactory("PathPulseAdapter", deployer);
    const adapter = await Adapter.deploy(
      deployer.address,
      ethers.ZeroAddress,
      await nftEnv.nft.getAddress(),
      100n,
      1n
    );
    await adapter.waitForDeployment();

    expect(await adapter.getAuthorizedAuction()).to.equal(ethers.ZeroAddress);
    expect(await adapter.getPathNftTarget()).to.equal(await nftEnv.nft.getAddress());
    expect(await adapter.wiringFrozen()).to.equal(false);
  });

  it("constructor rejects zero owner and invalid contract wiring", async function () {
    const [deployer, alice] = await ethers.getSigners();
    const nftEnv = await deployPathNftEnv(ethers, { admin: deployer.address });

    const StubAuction = await ethers.getContractFactory("StubPulseAuction", deployer);
    const auction = await StubAuction.deploy();
    await auction.waitForDeployment();

    const Adapter = await ethers.getContractFactory("PathPulseAdapter", deployer);

    await expect(
      Adapter.deploy(ethers.ZeroAddress, await auction.getAddress(), await nftEnv.nft.getAddress(), 100n, 1n)
    ).to.be.revertedWith("ZERO_OWNER");

    await expect(
      Adapter.deploy(deployer.address, alice.address, await nftEnv.nft.getAddress(), 100n, 1n)
    ).to.be.revertedWithCustomError(Adapter, "InvalidAuction");

    await expect(
      Adapter.deploy(deployer.address, await auction.getAddress(), ethers.ZeroAddress, 100n, 1n)
    ).to.be.revertedWithCustomError(Adapter, "InvalidPathNft");

    await expect(
      Adapter.deploy(deployer.address, await auction.getAddress(), alice.address, 100n, 1n)
    ).to.be.revertedWithCustomError(Adapter, "InvalidPathNft");
  });

  it("sets config and explicit getters", async function () {
    const { nft, auction, adapter, tokenBase, epochBase } = await deployFixture();

    const [auctionAddr, pathNftAddr] = await adapter.getConfig();
    expect(auctionAddr).to.equal(await auction.getAddress());
    expect(pathNftAddr).to.equal(await nft.getAddress());
    expect(await adapter.getAuthorizedAuction()).to.equal(await auction.getAddress());
    expect(await adapter.getPathNftTarget()).to.equal(await nft.getAddress());
    expect(await adapter.getFunction("target")()).to.equal(await auction.getAddress());
    expect(await adapter.tokenBase()).to.equal(tokenBase);
    expect(await adapter.epochBase()).to.equal(epochBase);
    expect(await adapter.wiringFrozen()).to.equal(false);
  });

  it("owner-only updates auction/path nft and freezes wiring one-way", async function () {
    const { deployer, alice, bob, nft, auction, adapter } = await deployFixture();

    const StubAuction = await ethers.getContractFactory("StubPulseAuction", deployer);
    const nextAuction = await StubAuction.deploy();
    await nextAuction.waitForDeployment();

    const nextNftEnv = await deployPathNftEnv(ethers, { admin: deployer.address });

    await expectAnyRevert(adapter.connect(alice).setAuction(bob.address));
    await expect(adapter.setAuction(ethers.ZeroAddress)).to.be.revertedWithCustomError(adapter, "InvalidAuction");
    await expect(adapter.setAuction(bob.address)).to.be.revertedWithCustomError(adapter, "InvalidAuction");

    await expect(adapter.setAuction(await nextAuction.getAddress()))
      .to.emit(adapter, "AuctionSet")
      .withArgs(await auction.getAddress(), await nextAuction.getAddress());
    expect(await adapter.getAuthorizedAuction()).to.equal(await nextAuction.getAddress());

    await expectAnyRevert(adapter.connect(alice).setPathNft(bob.address));
    await expect(adapter.setPathNft(ethers.ZeroAddress)).to.be.revertedWithCustomError(adapter, "InvalidPathNft");
    await expect(adapter.setPathNft(bob.address)).to.be.revertedWithCustomError(adapter, "InvalidPathNft");

    await expect(adapter.setPathNft(await nextNftEnv.nft.getAddress()))
      .to.emit(adapter, "PathNftSet")
      .withArgs(await nft.getAddress(), await nextNftEnv.nft.getAddress());

    await expectAnyRevert(adapter.connect(alice).freezeWiring());
    await expect(adapter.freezeWiring()).to.emit(adapter, "WiringFrozenSet");
    expect(await adapter.wiringFrozen()).to.equal(true);

    await expect(adapter.setAuction(await auction.getAddress())).to.be.revertedWithCustomError(adapter, "WiringFrozen");
    await expect(adapter.setPathNft(await nft.getAddress())).to.be.revertedWithCustomError(adapter, "WiringFrozen");
    await expect(adapter.freezeWiring()).to.be.revertedWithCustomError(adapter, "WiringFrozen");
  });

  it("settle is callable only by configured auction", async function () {
    const { bob, adapter } = await deployFixture({ freezeWiring: true });

    await expect(adapter.connect(bob).settle(bob.address, 1, "0x")).to.be.revertedWithCustomError(
      adapter,
      "NotAuction"
    );
  });

  it("settle requires wiring to be frozen", async function () {
    const { bob, auction, adapter } = await deployFixture();

    await expect(auction.settleThroughAdapter(await adapter.getAddress(), bob.address, "0x"))
      .to.be.revertedWithCustomError(adapter, "WiringNotFrozen");
  });

  it("settle enforces epoch-to-token coupling and mints expected id", async function () {
    const { bob, nft, auction, adapter } = await deployFixture({ freezeWiring: true });

    await (await auction.setEpochIndex(6)).wait(); // next sale epoch = 7
    await expect(auction.settleThroughAdapter(await adapter.getAddress(), bob.address, "0x11223344"))
      .to.emit(adapter, "EpochMinted")
      .withArgs(7n, 106n, bob.address);

    expect(await nft.ownerOf(106n)).to.equal(bob.address);
  });

  it("settle maps non-default epochBase/tokenBase with tokenId = tokenBase + (epoch - epochBase)", async function () {
    const { bob, nft, auction, adapter } = await deployFixture({
      tokenBase: 1_000n,
      epochBase: 10n,
      freezeWiring: true
    });

    await (await auction.setEpochIndex(12)).wait(); // next sale epoch = 13
    await expect(auction.settleThroughAdapter(await adapter.getAddress(), bob.address, "0x"))
      .to.emit(adapter, "EpochMinted")
      .withArgs(13n, 1_003n, bob.address);
    expect(await nft.ownerOf(1_003n)).to.equal(bob.address);
  });

  it("settle reverts on auction epoch mismatch", async function () {
    const { bob, auction, adapter } = await deployFixture({ freezeWiring: true });

    await (await auction.setEpochIndex(3)).wait(); // observed epoch = 4
    await expect(auction.settleThroughAdapterWithForwardedEpoch(await adapter.getAddress(), bob.address, 9, "0x"))
      .to.be.revertedWithCustomError(adapter, "EpochMismatch")
      .withArgs(4n, 9n);
  });

  it("settle reverts when epoch is below epochBase", async function () {
    const { bob, auction, adapter } = await deployFixture({ epochBase: 5n, freezeWiring: true });

    await (await auction.setEpochIndex(3)).wait(); // observed epoch = 4 (< epochBase=5)

    await expect(auction.settleThroughAdapter(await adapter.getAddress(), bob.address, "0x"))
      .to.be.revertedWithCustomError(adapter, "EpochBeforeBase")
      .withArgs(4n, 5n);
  });
});
