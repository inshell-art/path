import { expect } from "chai";
import hre from "hardhat";
import { FIRST_PUBLIC_ID } from "./helpers/constants.js";
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

  it("constructor initializes public mint state", async function () {
    const { nft, minter } = await deployPathMinterEnv(ethers);

    expect(await minter.pathNft()).to.equal(await nft.getAddress());
    expect(await minter.nextId()).to.equal(FIRST_PUBLIC_ID);
    expect(await minter.salesCaller()).to.equal(ethers.ZeroAddress);
    expect(await minter.salesCallerFrozen()).to.equal(false);
  });

  it("constructor rejects zero admin or zero path nft address", async function () {
    const [deployer] = await ethers.getSigners();
    const Minter = await ethers.getContractFactory("PathMinter", deployer);

    await expect(
      Minter.deploy(ethers.ZeroAddress, deployer.address, FIRST_PUBLIC_ID)
    ).to.be.revertedWith("ZERO_ADMIN");

    await expect(
      Minter.deploy(deployer.address, ethers.ZeroAddress, FIRST_PUBLIC_ID)
    ).to.be.revertedWith("ZERO_PATH_NFT");
  });

  it("mintPublic requires explicit sales caller freeze", async function () {
    const { nft, minter, roles } = await deployPathMinterEnv(ethers);
    const [, alice] = await ethers.getSigners();

    await (await nft.grantRole(roles.MINTER_ROLE, await minter.getAddress())).wait();
    await (await minter.grantRole(roles.SALES_ROLE, alice.address)).wait();

    await expect(minter.connect(alice).mintPublic(alice.address, "0x"))
      .to.be.revertedWithCustomError(minter, "SalesCallerNotFrozen");

    await (await minter.freezeSalesCaller(alice.address)).wait();
    await (await minter.connect(alice).mintPublic(alice.address, "0x")).wait();

    expect(await nft.ownerOf(FIRST_PUBLIC_ID)).to.equal(alice.address);
  });

  it("mintPublic sequences IDs and preserves rollback on downstream revert", async function () {
    const { minter, nft, roles } = await deployPathMinterEnv(ethers);
    const [, alice] = await ethers.getSigners();

    await (await minter.grantRole(roles.SALES_ROLE, alice.address)).wait();

    await expect(minter.connect(alice).mintPublic(alice.address, "0x"))
      .to.be.revertedWithCustomError(minter, "SalesCallerNotFrozen");
    expect(await minter.nextId()).to.equal(FIRST_PUBLIC_ID);
    expect(await minter.salesCaller()).to.equal(ethers.ZeroAddress);
    expect(await minter.salesCallerFrozen()).to.equal(false);

    await (await nft.grantRole(roles.MINTER_ROLE, await minter.getAddress())).wait();
    await (await minter.freezeSalesCaller(alice.address)).wait();

    await (await minter.connect(alice).mintPublic(alice.address, "0x")).wait();
    await (await minter.connect(alice).mintPublic(alice.address, "0x")).wait();

    expect(await nft.ownerOf(FIRST_PUBLIC_ID)).to.equal(alice.address);
    expect(await nft.ownerOf(FIRST_PUBLIC_ID + 1n)).to.equal(alice.address);
    expect(await minter.nextId()).to.equal(FIRST_PUBLIC_ID + 2n);
  });

  it("freezeSalesCaller is admin-gated, one-way, and enforces caller", async function () {
    const { minter, nft, roles } = await deployPathMinterEnv(ethers);
    const [deployer, alice, bob] = await ethers.getSigners();

    await (await nft.grantRole(roles.MINTER_ROLE, await minter.getAddress())).wait();
    await (await minter.grantRole(roles.SALES_ROLE, alice.address)).wait();
    await (await minter.grantRole(roles.SALES_ROLE, bob.address)).wait();

    await expect(minter.connect(alice).freezeSalesCaller(alice.address)).to.be.revertedWith(
      `AccessControl: account ${alice.address.toLowerCase()} is missing role ${roles.DEFAULT_ADMIN_ROLE}`
    );
    await expect(minter.freezeSalesCaller(ethers.ZeroAddress)).to.be.revertedWith("ZERO_SALES_CALLER");

    const [, , , carol] = await ethers.getSigners();
    await expect(minter.freezeSalesCaller(carol.address)).to.be.revertedWith("MISSING_SALES_ROLE");

    await expect(minter.freezeSalesCaller(alice.address))
      .to.emit(minter, "SalesCallerFrozen")
      .withArgs(alice.address);

    expect(await minter.salesCaller()).to.equal(alice.address);
    expect(await minter.salesCallerFrozen()).to.equal(true);
    expect(await minter.getRoleAdmin(roles.SALES_ROLE)).to.equal(await minter.FROZEN_SALES_ADMIN_ROLE());
    expect(await minter.hasRole(await minter.FROZEN_SALES_ADMIN_ROLE(), deployer.address)).to.equal(false);

    await expect(minter.freezeSalesCaller(bob.address)).to.be.revertedWith("SALES_CALLER_FROZEN");

    await expect(minter.connect(bob).mintPublic(bob.address, "0x"))
      .to.be.revertedWithCustomError(minter, "BadSalesCaller")
      .withArgs(bob.address, alice.address);
  });

  it("cannot reconfigure SALES_ROLE after explicit freeze", async function () {
    const { minter, nft, roles } = await deployPathMinterEnv(ethers);
    const [deployer, alice, bob] = await ethers.getSigners();

    await (await nft.grantRole(roles.MINTER_ROLE, await minter.getAddress())).wait();
    await (await minter.grantRole(roles.SALES_ROLE, alice.address)).wait();
    await (await minter.freezeSalesCaller(alice.address)).wait();
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
    await (await minter.freezeSalesCaller(alice.address)).wait();

    await expectAnyRevert(minter.connect(alice).mintPublic(await rejector.getAddress(), "0x"));
    expect(await minter.nextId()).to.equal(FIRST_PUBLIC_ID);
  });

  it("mintPublic has no legacy domain cap and can continue from a high token id", async function () {
    const HIGH_START = 1_000_000_000_000_000n;
    const { minter, nft, roles } = await deployPathMinterEnv(ethers, { firstPublicId: HIGH_START });
    const [, alice] = await ethers.getSigners();

    await (await nft.grantRole(roles.MINTER_ROLE, await minter.getAddress())).wait();
    await (await minter.grantRole(roles.SALES_ROLE, alice.address)).wait();
    await (await minter.freezeSalesCaller(alice.address)).wait();

    await (await minter.connect(alice).mintPublic(alice.address, "0x")).wait();
    expect(await minter.nextId()).to.equal(HIGH_START + 1n);
    expect(await nft.ownerOf(HIGH_START)).to.equal(alice.address);
  });
});
