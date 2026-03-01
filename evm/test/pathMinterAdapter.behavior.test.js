import { expect } from "chai";
import hre from "hardhat";

describe("PathMinterAdapter (Solidity)", function () {
  let conn;
  let ethers;

  beforeEach(async function () {
    conn = await hre.network.connect();
    ethers = conn.ethers;
  });

  afterEach(async function () {
    await conn.close();
  });

  async function deployFixture({ tokenBase = 100n, epochBase = 1n } = {}) {
    const [deployer, alice, bob] = await ethers.getSigners();

    const StubMinter = await ethers.getContractFactory("StubPathMinter", deployer);
    const minter = await StubMinter.deploy(100n);
    await minter.waitForDeployment();

    const StubAuction = await ethers.getContractFactory("StubPulseAuction", deployer);
    const auction = await StubAuction.deploy();
    await auction.waitForDeployment();

    const Adapter = await ethers.getContractFactory("PathMinterAdapter", deployer);
    const adapter = await Adapter.deploy(
      deployer.address,
      await auction.getAddress(),
      await minter.getAddress(),
      tokenBase,
      epochBase
    );
    await adapter.waitForDeployment();

    return { deployer, alice, bob, minter, auction, adapter, tokenBase, epochBase };
  }

  it("constructor sets config and explicit getters", async function () {
    const { minter, auction, adapter, tokenBase, epochBase } = await deployFixture();

    const [auctionAddr, minterAddr] = await adapter.getConfig();
    expect(auctionAddr).to.equal(await auction.getAddress());
    expect(minterAddr).to.equal(await minter.getAddress());
    expect(await adapter.getAuthorizedAuction()).to.equal(await auction.getAddress());
    expect(await adapter.getMinterTarget()).to.equal(await minter.getAddress());
    expect(await adapter.getFunction("target")()).to.equal(await auction.getAddress());
    expect(await adapter.tokenBase()).to.equal(tokenBase);
    expect(await adapter.epochBase()).to.equal(epochBase);
    expect(await adapter.wiringFrozen()).to.equal(false);
  });

  it("owner-only updates auction/minter, rejects zero, and freezes wiring one-way", async function () {
    const { alice, bob, minter, adapter } = await deployFixture();

    await expect(adapter.connect(alice).setAuction(bob.address)).to.be.revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(adapter.setAuction(ethers.ZeroAddress)).to.be.revertedWith("ZERO_AUCTION");

    await (await adapter.setAuction(bob.address)).wait();
    expect(await adapter.getAuthorizedAuction()).to.equal(bob.address);

    await expect(adapter.connect(alice).setMinter(bob.address)).to.be.revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(adapter.setMinter(ethers.ZeroAddress)).to.be.revertedWith("ZERO_MINTER");

    await (await adapter.setMinter(await minter.getAddress())).wait();

    const [, minterAddr] = await adapter.getConfig();
    expect(minterAddr).to.equal(await minter.getAddress());
    expect(await adapter.getMinterTarget()).to.equal(await minter.getAddress());

    await expect(adapter.connect(alice).freezeWiring()).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(adapter.freezeWiring()).to.emit(adapter, "WiringFrozenSet");
    expect(await adapter.wiringFrozen()).to.equal(true);

    await expect(adapter.setAuction(bob.address))
      .to.be.revertedWithCustomError(adapter, "WiringFrozen");
    await expect(adapter.setMinter(await minter.getAddress()))
      .to.be.revertedWithCustomError(adapter, "WiringFrozen");
    await expect(adapter.freezeWiring())
      .to.be.revertedWithCustomError(adapter, "WiringFrozen");
  });

  it("settle is callable only by configured auction", async function () {
    const { bob, adapter } = await deployFixture();

    await expect(adapter.connect(bob).settle(bob.address, 1, "0x")).to.be.revertedWithCustomError(
      adapter,
      "NotAuction"
    );
  });

  it("settle enforces epoch-to-token coupling and mints expected id", async function () {
    const { bob, minter, auction, adapter } = await deployFixture();
    const payload = "0x11223344";

    await (await auction.setEpochIndex(6)).wait(); // next sale epoch = 7
    await (await minter.setNextTokenId(106n)).wait(); // tokenBase + (7 - 1) = 106

    await expect(auction.settleThroughAdapter(await adapter.getAddress(), bob.address, payload))
      .to.emit(adapter, "EpochMinted")
      .withArgs(7n, 106n, bob.address);

    expect(await minter.lastTo()).to.equal(bob.address);
    expect(await minter.lastData()).to.equal(payload);
    expect(await minter.nextTokenId()).to.equal(107n);
  });

  it("settle maps non-default epochBase/tokenBase with tokenId = tokenBase + (epoch - epochBase)", async function () {
    const { bob, minter, auction, adapter } = await deployFixture({ tokenBase: 1_000n, epochBase: 10n });

    await (await auction.setEpochIndex(12)).wait(); // next sale epoch = 13
    await (await minter.setNextTokenId(1_003n)).wait(); // 1000 + (13 - 10) = 1003

    await expect(auction.settleThroughAdapter(await adapter.getAddress(), bob.address, "0x"))
      .to.emit(adapter, "EpochMinted")
      .withArgs(13n, 1_003n, bob.address);
  });

  it("settle reverts on auction epoch mismatch", async function () {
    const { bob, minter, auction, adapter } = await deployFixture();

    await (await auction.setEpochIndex(3)).wait(); // observed epoch = 4
    await (await minter.setNextTokenId(103n)).wait();

    await expect(
      auction.settleThroughAdapterWithForwardedEpoch(await adapter.getAddress(), bob.address, 9, "0x")
    )
      .to.be.revertedWithCustomError(adapter, "EpochMismatch")
      .withArgs(4n, 9n);
  });

  it("settle reverts when minter nextId drifts from expected id", async function () {
    const { bob, minter, auction, adapter } = await deployFixture();

    await (await auction.setEpochIndex(1)).wait(); // expected epoch = 2, expected id = 101
    await (await minter.setNextTokenId(555n)).wait();

    await expect(auction.settleThroughAdapter(await adapter.getAddress(), bob.address, "0x"))
      .to.be.revertedWithCustomError(adapter, "MintIdMismatch")
      .withArgs(2n, 101n, 555n);
  });

  it("settle reverts when epoch is below epochBase", async function () {
    const { bob, auction, adapter } = await deployFixture({ epochBase: 5n });

    await (await auction.setEpochIndex(3)).wait(); // observed epoch = 4 (< epochBase=5)

    await expect(auction.settleThroughAdapter(await adapter.getAddress(), bob.address, "0x"))
      .to.be.revertedWithCustomError(adapter, "EpochBeforeBase")
      .withArgs(4n, 5n);
  });

  it("settle reverts when minter returns a token id different from expected", async function () {
    const [deployer, bob] = await ethers.getSigners();

    const BadMinter = await ethers.getContractFactory("StubPathMinterBadReturn", deployer);
    const minter = await BadMinter.deploy(100n);
    await minter.waitForDeployment();

    const StubAuction = await ethers.getContractFactory("StubPulseAuction", deployer);
    const auction = await StubAuction.deploy();
    await auction.waitForDeployment();

    const Adapter = await ethers.getContractFactory("PathMinterAdapter", deployer);
    const adapter = await Adapter.deploy(
      deployer.address,
      await auction.getAddress(),
      await minter.getAddress(),
      100n,
      1n
    );
    await adapter.waitForDeployment();

    await expect(auction.settleThroughAdapter(await adapter.getAddress(), bob.address, "0x"))
      .to.be.revertedWithCustomError(adapter, "MintIdMismatch")
      .withArgs(1n, 100n, 101n);

    expect(await minter.nextTokenId()).to.equal(100n);
  });
});
