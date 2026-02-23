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

  async function deployFixture() {
    const [deployer, alice, bob] = await ethers.getSigners();

    const StubMinter = await ethers.getContractFactory("StubPathMinter", deployer);
    const minter = await StubMinter.deploy(100n);
    await minter.waitForDeployment();

    const Adapter = await ethers.getContractFactory("PathMinterAdapter", deployer);
    const adapter = await Adapter.deploy(deployer.address, alice.address, await minter.getAddress());
    await adapter.waitForDeployment();

    return { deployer, alice, bob, minter, adapter };
  }

  it("constructor sets config and target", async function () {
    const { alice, minter, adapter } = await deployFixture();

    const [auction, minterAddr] = await adapter.getConfig();
    expect(auction).to.equal(alice.address);
    expect(minterAddr).to.equal(await minter.getAddress());
    expect(await adapter.getFunction("target")()).to.equal(alice.address);
  });

  it("owner-only updates auction/minter and rejects zero", async function () {
    const { alice, bob, minter, adapter } = await deployFixture();

    await expect(adapter.connect(alice).setAuction(bob.address)).to.be.revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(adapter.setAuction(ethers.ZeroAddress)).to.be.revertedWith("ZERO_AUCTION");

    await (await adapter.setAuction(bob.address)).wait();
    expect(await adapter.getFunction("target")()).to.equal(bob.address);

    await expect(adapter.connect(alice).setMinter(bob.address)).to.be.revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(adapter.setMinter(ethers.ZeroAddress)).to.be.revertedWith("ZERO_MINTER");

    await (await adapter.setMinter(minter.target)).wait();

    const [, minterAddr] = await adapter.getConfig();
    expect(minterAddr).to.equal(minter.target);
  });

  it("settle is callable only by configured auction", async function () {
    const { bob, adapter } = await deployFixture();

    await expect(adapter.connect(bob).settle(bob.address, "0x")).to.be.revertedWith("ONLY_AUCTION");
  });

  it("settle forwards buyer/data to minter and returns token id", async function () {
    const { alice, bob, minter, adapter } = await deployFixture();
    const payload = "0x11223344";

    const minted = await adapter.connect(alice).settle.staticCall(bob.address, payload);
    expect(minted).to.equal(100n);

    await (await adapter.connect(alice).settle(bob.address, payload)).wait();

    expect(await minter.lastTo()).to.equal(bob.address);
    expect(await minter.lastData()).to.equal(payload);
    expect(await minter.nextTokenId()).to.equal(101n);
  });
});
