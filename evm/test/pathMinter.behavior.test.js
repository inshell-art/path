import { expect } from "chai";
import hre from "hardhat";
import { FIRST_PUBLIC_ID, RESERVED_CAP } from "./helpers/constants.js";
import { deployPathMinterEnv } from "./helpers/fixtures.js";

describe("PathMinter (Solidity)", function () {
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

  it("constructor initializes reserved cap and remaining", async function () {
    const { minter } = await deployPathMinterEnv(ethers);

    expect(await minter.getReservedCap()).to.equal(RESERVED_CAP);
    expect(await minter.getReservedRemaining()).to.equal(RESERVED_CAP);
    expect(await minter.SPARK_BASE()).to.equal(1_000_000_000_000_000n);
    expect(await minter.salesCaller()).to.equal(ethers.ZeroAddress);
    expect(await minter.salesCallerFrozen()).to.equal(false);
  });

  it("constructor rejects zero admin or zero path nft address", async function () {
    const [deployer] = await ethers.getSigners();
    const Minter = await ethers.getContractFactory("PathMinter", deployer);

    await expect(
      Minter.deploy(ethers.ZeroAddress, deployer.address, FIRST_PUBLIC_ID, RESERVED_CAP)
    ).to.be.revertedWith("ZERO_ADMIN");

    await expect(
      Minter.deploy(deployer.address, ethers.ZeroAddress, FIRST_PUBLIC_ID, RESERVED_CAP)
    ).to.be.revertedWith("ZERO_PATH_NFT");
  });

  it("mintPublic requires SALES_ROLE", async function () {
    const { deployer, nft, minter, roles } = await deployPathMinterEnv(ethers);
    const [, alice] = await ethers.getSigners();

    await (await nft.grantRole(roles.MINTER_ROLE, await minter.getAddress())).wait();

    await expectAnyRevert(minter.connect(alice).mintPublic(alice.address, "0x"));

    await (await minter.grantRole(roles.SALES_ROLE, alice.address)).wait();
    await (await minter.connect(alice).mintPublic(alice.address, "0x")).wait();

    expect(await nft.ownerOf(FIRST_PUBLIC_ID)).to.equal(alice.address);
  });

  it("mintPublic sequences IDs and preserves rollback on downstream revert", async function () {
    const { minter, nft, roles } = await deployPathMinterEnv(ethers);
    const [, alice] = await ethers.getSigners();

    await (await minter.grantRole(roles.SALES_ROLE, alice.address)).wait();

    await expectAnyRevert(minter.connect(alice).mintPublic(alice.address, "0x"));
    expect(await minter.nextId()).to.equal(FIRST_PUBLIC_ID);
    expect(await minter.salesCaller()).to.equal(ethers.ZeroAddress);
    expect(await minter.salesCallerFrozen()).to.equal(false);

    await (await nft.grantRole(roles.MINTER_ROLE, await minter.getAddress())).wait();

    await (await minter.connect(alice).mintPublic(alice.address, "0x")).wait();
    await (await minter.connect(alice).mintPublic(alice.address, "0x")).wait();

    expect(await nft.ownerOf(FIRST_PUBLIC_ID)).to.equal(alice.address);
    expect(await nft.ownerOf(FIRST_PUBLIC_ID + 1n)).to.equal(alice.address);
    expect(await minter.nextId()).to.equal(FIRST_PUBLIC_ID + 2n);
  });

  it("first successful public mint freezes sales caller", async function () {
    const { minter, nft, roles } = await deployPathMinterEnv(ethers);
    const [, alice, bob] = await ethers.getSigners();

    await (await nft.grantRole(roles.MINTER_ROLE, await minter.getAddress())).wait();
    await (await minter.grantRole(roles.SALES_ROLE, alice.address)).wait();
    await (await minter.grantRole(roles.SALES_ROLE, bob.address)).wait();

    await expect(minter.connect(alice).mintPublic(alice.address, "0x"))
      .to.emit(minter, "SalesCallerFrozen")
      .withArgs(alice.address);

    expect(await minter.salesCaller()).to.equal(alice.address);
    expect(await minter.salesCallerFrozen()).to.equal(true);
    expect(await minter.getRoleAdmin(roles.SALES_ROLE)).to.equal(await minter.FROZEN_SALES_ADMIN_ROLE());

    await expect(minter.connect(bob).mintPublic(bob.address, "0x"))
      .to.be.revertedWithCustomError(minter, "BadSalesCaller")
      .withArgs(bob.address, alice.address);
  });

  it("cannot reconfigure SALES_ROLE after first successful public mint", async function () {
    const { minter, nft, roles } = await deployPathMinterEnv(ethers);
    const [deployer, alice, bob] = await ethers.getSigners();

    await (await nft.grantRole(roles.MINTER_ROLE, await minter.getAddress())).wait();
    await (await minter.grantRole(roles.SALES_ROLE, alice.address)).wait();
    await (await minter.connect(alice).mintPublic(alice.address, "0x")).wait();

    await expectAnyRevert(minter.grantRole(roles.SALES_ROLE, bob.address));
    await expectAnyRevert(minter.revokeRole(roles.SALES_ROLE, alice.address));
    expect(await minter.hasRole(roles.SALES_ROLE, alice.address)).to.equal(true);
    expect(await minter.hasRole(await minter.FROZEN_SALES_ADMIN_ROLE(), deployer.address)).to.equal(false);
  });

  it("mintPublic reverts when receiver rejects ERC721 and does not increment nextId", async function () {
    const { minter, nft, roles } = await deployPathMinterEnv(ethers);
    const [deployer, alice] = await ethers.getSigners();

    const Rejector = await ethers.getContractFactory("RejectingERC721Receiver", deployer);
    const rejector = await Rejector.deploy();
    await rejector.waitForDeployment();

    await (await nft.grantRole(roles.MINTER_ROLE, await minter.getAddress())).wait();
    await (await minter.grantRole(roles.SALES_ROLE, alice.address)).wait();

    await expectAnyRevert(minter.connect(alice).mintPublic(await rejector.getAddress(), "0x"));
    expect(await minter.nextId()).to.equal(FIRST_PUBLIC_ID);
  });

  it("mintSparker requires RESERVED_ROLE", async function () {
    const { minter, nft, roles } = await deployPathMinterEnv(ethers);
    const [, alice] = await ethers.getSigners();

    await (await nft.grantRole(roles.MINTER_ROLE, await minter.getAddress())).wait();

    await expectAnyRevert(minter.connect(alice).mintSparker(alice.address, "0x"));
  });

  it("mintSparker counts down reserved pool and exhausts", async function () {
    const { minter, nft, roles } = await deployPathMinterEnv(ethers);
    const [, alice] = await ethers.getSigners();
    const sparkBase = await minter.SPARK_BASE();

    await (await nft.grantRole(roles.MINTER_ROLE, await minter.getAddress())).wait();
    await (await minter.grantRole(roles.RESERVED_ROLE, alice.address)).wait();

    const id0 = await minter.connect(alice).mintSparker.staticCall(alice.address, "0x");
    await (await minter.connect(alice).mintSparker(alice.address, "0x")).wait();
    expect(await nft.ownerOf(id0)).to.equal(alice.address);
    expect(id0).to.equal(sparkBase);
    expect(await minter.getReservedRemaining()).to.equal(RESERVED_CAP - 1n);

    const id1 = await minter.connect(alice).mintSparker.staticCall(alice.address, "0x");
    await (await minter.connect(alice).mintSparker(alice.address, "0x")).wait();
    expect(id1).to.equal(id0 + 1n);

    const id2 = await minter.connect(alice).mintSparker.staticCall(alice.address, "0x");
    await (await minter.connect(alice).mintSparker(alice.address, "0x")).wait();
    expect(id2).to.equal(id1 + 1n);
    expect(await minter.getReservedRemaining()).to.equal(0n);

    await expect(minter.connect(alice).mintSparker(alice.address, "0x")).to.be.revertedWith("NO_RESERVED_LEFT");
  });

  it("reserved IDs are in high range above public IDs", async function () {
    const { minter, nft, roles } = await deployPathMinterEnv(ethers);
    const [, alice] = await ethers.getSigners();

    await (await nft.grantRole(roles.MINTER_ROLE, await minter.getAddress())).wait();
    await (await minter.grantRole(roles.SALES_ROLE, alice.address)).wait();
    await (await minter.grantRole(roles.RESERVED_ROLE, alice.address)).wait();

    const pubId = await minter.connect(alice).mintPublic.staticCall(alice.address, "0x");
    await (await minter.connect(alice).mintPublic(alice.address, "0x")).wait();

    const resId = await minter.connect(alice).mintSparker.staticCall(alice.address, "0x");
    await (await minter.connect(alice).mintSparker(alice.address, "0x")).wait();

    expect(resId).to.be.greaterThan(pubId);
  });

  it("public mint domain stops at SPARK_BASE boundary", async function () {
    const SPARK_BASE = 1_000_000_000_000_000n;
    const { minter, nft, roles } = await deployPathMinterEnv(ethers, { firstPublicId: SPARK_BASE - 1n, reservedCap: 1n });
    const [, alice] = await ethers.getSigners();

    await (await nft.grantRole(roles.MINTER_ROLE, await minter.getAddress())).wait();
    await (await minter.grantRole(roles.SALES_ROLE, alice.address)).wait();

    await (await minter.connect(alice).mintPublic(alice.address, "0x")).wait();
    expect(await minter.nextId()).to.equal(SPARK_BASE);
    expect(await nft.ownerOf(SPARK_BASE - 1n)).to.equal(alice.address);

    await expect(minter.connect(alice).mintPublic(alice.address, "0x")).to.be.revertedWith(
      "PUBLIC_ID_DOMAIN_EXHAUSTED"
    );
    expect(await minter.nextId()).to.equal(SPARK_BASE);
  });
});
