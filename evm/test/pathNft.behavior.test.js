import { expect } from "chai";
import hre from "hardhat";
import { deployPathNftEnv } from "./helpers/fixtures.js";

describe("PathNFT (Solidity)", function () {
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

  it("constructor sets metadata and admin role", async function () {
    const { deployer, nft, roles } = await deployPathNftEnv(ethers);

    expect(await nft.name()).to.equal("PATH NFT");
    expect(await nft.symbol()).to.equal("PATH");
    expect(await nft.hasRole(roles.DEFAULT_ADMIN_ROLE, deployer.address)).to.equal(true);
  });

  it("safeMint is MINTER_ROLE-gated", async function () {
    const { deployer, nft, roles } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    await expectAnyRevert(nft.connect(alice).safeMint(alice.address, 1n, "0x"));

    await (await nft.grantRole(roles.MINTER_ROLE, deployer.address)).wait();
    await (await nft.safeMint(alice.address, 1n, "0x")).wait();

    expect(await nft.ownerOf(1n)).to.equal(alice.address);
    expect(await nft.getStage(1n)).to.equal(0n);
    expect(await nft.getStageMinted(1n)).to.equal(0n);
  });

  it("setMovementConfig validates movement, minter, quota, and admin", async function () {
    const { nft, movements } = await deployPathNftEnv(ethers);
    const [, alice, bob] = await ethers.getSigners();

    await expectAnyRevert(nft.connect(alice).setMovementConfig(movements.THOUGHT, bob.address, 1));
    await expect(nft.setMovementConfig(movements.DREAM, bob.address, 1)).to.be.revertedWith("BAD_MOVEMENT");
    await expect(nft.setMovementConfig(movements.THOUGHT, ethers.ZeroAddress, 1)).to.be.revertedWith("ZERO_MINTER");
    await expect(nft.setMovementConfig(movements.THOUGHT, bob.address, 0)).to.be.revertedWith("ZERO_QUOTA");

    await (await nft.setMovementConfig(movements.THOUGHT, bob.address, 2)).wait();
    expect(await nft.getAuthorizedMinter(movements.THOUGHT)).to.equal(bob.address);
    expect(await nft.getMovementQuota(movements.THOUGHT)).to.equal(2n);
  });

  it("tokenURI returns on-chain metadata with raw svg using movement-config quotas", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await (await nft.grantRole(roles.MINTER_ROLE, deployer.address)).wait();
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 1)).wait();
    await (await nft.setMovementConfig(movements.WILL, await mover.getAddress(), 4)).wait();
    await (await nft.setMovementConfig(movements.AWA, await mover.getAddress(), 1)).wait();
    await (await nft.safeMint(alice.address, 5n, "0x1234")).wait();

    const uri0 = await nft.tokenURI(5n);

    expect(uri0).to.contain("data:application/json;utf8,");
    expect(uri0).to.contain('"name":"PATH #5"');
    expect(uri0).to.contain('"stage":"THOUGHT"');
    expect(uri0).to.contain('"thought":"Minted(0/1)"');
    expect(uri0).to.contain('"will":"Minted(0/4)"');
    expect(uri0).to.contain('"awa":"Minted(0/1)"');
    expect(uri0).to.contain('"image_data":"<svg');
    expect(uri0).to.contain("id='will-box'");

    await (await mover.connect(alice).consume(await nft.getAddress(), 5n, movements.THOUGHT, alice.address)).wait();
    await (await mover.connect(alice).consume(await nft.getAddress(), 5n, movements.WILL, alice.address)).wait();

    const uri1 = await nft.tokenURI(5n);
    expect(uri1).to.contain('"stage":"WILL"');
    expect(uri1).to.contain('"thought":"Minted(1/1)"');
    expect(uri1).to.contain('"will":"Minted(1/4)"');
    expect(uri1).to.contain("id='will-fill' x='270' y='270' width='15'");
  });

  it("consumeUnit enforces authorized movement minter", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice, bob] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await (await nft.grantRole(roles.MINTER_ROLE, deployer.address)).wait();
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 1)).wait();
    await (await nft.safeMint(alice.address, 21n, "0x")).wait();

    await expect(nft.connect(bob).consumeUnit(21n, movements.THOUGHT, bob.address)).to.be.revertedWith(
      "ERR_UNAUTHORIZED_MINTER"
    );
  });

  it("consumeUnit enforces BAD_CLAIMER and owner/approval checks", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice, bob, carol] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await (await nft.grantRole(roles.MINTER_ROLE, deployer.address)).wait();
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 1)).wait();
    await (await nft.safeMint(alice.address, 22n, "0x")).wait();

    await expect(
      mover.connect(bob).consume(await nft.getAddress(), 22n, movements.THOUGHT, carol.address)
    ).to.be.revertedWith("BAD_CLAIMER");

    await expect(
      mover.connect(bob).consume(await nft.getAddress(), 22n, movements.THOUGHT, bob.address)
    ).to.be.revertedWith("ERR_NOT_OWNER");

    await (await nft.connect(alice).approve(bob.address, 22n)).wait();
    await (await mover.connect(bob).consume(await nft.getAddress(), 22n, movements.THOUGHT, bob.address)).wait();

    expect(await nft.getStage(22n)).to.equal(1n);
    expect(await nft.getStageMinted(22n)).to.equal(0n);
  });

  it("consumeUnit accepts operator approval via setApprovalForAll", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice, bob] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await (await nft.grantRole(roles.MINTER_ROLE, deployer.address)).wait();
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 1)).wait();
    await (await nft.safeMint(alice.address, 23n, "0x")).wait();

    await (await nft.connect(alice).setApprovalForAll(bob.address, true)).wait();
    await (await mover.connect(bob).consume(await nft.getAddress(), 23n, movements.THOUGHT, bob.address)).wait();

    expect(await nft.getStage(23n)).to.equal(1n);
    expect(await nft.getStageMinted(23n)).to.equal(0n);
  });

  it("consumeUnit enforces movement order and advances stage by quota", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await (await nft.grantRole(roles.MINTER_ROLE, deployer.address)).wait();
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 2)).wait();
    await (await nft.setMovementConfig(movements.WILL, await mover.getAddress(), 2)).wait();
    await (await nft.setMovementConfig(movements.AWA, await mover.getAddress(), 1)).wait();
    await (await nft.safeMint(alice.address, 31n, "0x")).wait();

    await expect(
      mover.connect(alice).consume(await nft.getAddress(), 31n, movements.WILL, alice.address)
    ).to.be.revertedWith("BAD_MOVEMENT_ORDER");

    await (await mover.connect(alice).consume(await nft.getAddress(), 31n, movements.THOUGHT, alice.address)).wait();
    expect(await nft.getStage(31n)).to.equal(0n);
    expect(await nft.getStageMinted(31n)).to.equal(1n);

    await (await mover.connect(alice).consume(await nft.getAddress(), 31n, movements.THOUGHT, alice.address)).wait();
    expect(await nft.getStage(31n)).to.equal(1n);
    expect(await nft.getStageMinted(31n)).to.equal(0n);

    await (await mover.connect(alice).consume(await nft.getAddress(), 31n, movements.WILL, alice.address)).wait();
    await (await mover.connect(alice).consume(await nft.getAddress(), 31n, movements.WILL, alice.address)).wait();
    await (await mover.connect(alice).consume(await nft.getAddress(), 31n, movements.AWA, alice.address)).wait();

    expect(await nft.getStage(31n)).to.equal(3n);
    await expect(
      mover.connect(alice).consume(await nft.getAddress(), 31n, movements.AWA, alice.address)
    ).to.be.revertedWith("BAD_STAGE");
  });

  it("movement freeze is per-movement", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice, bob] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await (await nft.grantRole(roles.MINTER_ROLE, deployer.address)).wait();
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 1)).wait();
    await (await nft.setMovementConfig(movements.WILL, bob.address, 2)).wait();
    await (await nft.safeMint(alice.address, 41n, "0x")).wait();

    await (await mover.connect(alice).consume(await nft.getAddress(), 41n, movements.THOUGHT, alice.address)).wait();

    await expect(nft.setMovementConfig(movements.THOUGHT, bob.address, 2)).to.be.revertedWith("MOVEMENT_FROZEN");

    await (await nft.setMovementConfig(movements.WILL, alice.address, 3)).wait();
    expect(await nft.getAuthorizedMinter(movements.WILL)).to.equal(alice.address);
    expect(await nft.getMovementQuota(movements.WILL)).to.equal(3n);
  });

  it("emits MovementFrozen only on first consume of each movement", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await (await nft.grantRole(roles.MINTER_ROLE, deployer.address)).wait();
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 2)).wait();
    await (await nft.setMovementConfig(movements.WILL, await mover.getAddress(), 1)).wait();
    await (await nft.safeMint(alice.address, 51n, "0x")).wait();

    const first = await (await mover.connect(alice).consume(await nft.getAddress(), 51n, movements.THOUGHT, alice.address)).wait();
    const second = await (await mover.connect(alice).consume(await nft.getAddress(), 51n, movements.THOUGHT, alice.address)).wait();
    const third = await (await mover.connect(alice).consume(await nft.getAddress(), 51n, movements.WILL, alice.address)).wait();

    const frozenLogs = await nft.queryFilter(nft.filters.MovementFrozen(), first.blockNumber, third.blockNumber);
    const thoughtFrozen = frozenLogs.filter((log) => log.args.movement === movements.THOUGHT);
    const willFrozen = frozenLogs.filter((log) => log.args.movement === movements.WILL);

    expect(second.status).to.equal(1);
    expect(thoughtFrozen.length).to.equal(1);
    expect(willFrozen.length).to.equal(1);
  });
});
