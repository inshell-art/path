import { expect } from "chai";
import hre from "hardhat";
import { deployPathNftEnv } from "./helpers/fixtures.js";

describe("PathNFT (Solidity)", function () {
  let conn;
  let ethers;

  function decodeMetadata(uri) {
    const prefix = "data:application/json;base64,";
    expect(uri.startsWith(prefix)).to.equal(true);
    const b64 = uri.slice(prefix.length);
    return JSON.parse(Buffer.from(b64, "base64").toString("utf8"));
  }

  async function expectAnyRevert(txPromise) {
    try {
      await txPromise;
      expect.fail("expected tx to revert");
    } catch (error) {
      expect(error).to.exist;
    }
  }

  async function signConsumeAuthorization(
    nft,
    signer,
    claimer,
    executor,
    pathId,
    movement,
    deadlineOffset = 3600n
  ) {
    const chainId = (await signer.provider.getNetwork()).chainId;
    const pathNft = await nft.getAddress();
    const typeHash = ethers.id(
      "ConsumeAuthorization(address pathNft,uint256 chainId,uint256 pathId,bytes32 movement,address claimer,address executor,uint256 nonce,uint256 deadline)"
    );
    const nonce = await nft.getConsumeNonce(claimer);
    const now = BigInt((await signer.provider.getBlock("latest")).timestamp);
    const deadline = now + deadlineOffset;
    const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
      [
        "bytes32",
        "address",
        "uint256",
        "uint256",
        "bytes32",
        "address",
        "address",
        "uint256",
        "uint256"
      ],
      [typeHash, pathNft, chainId, pathId, movement, claimer, executor, nonce, deadline]
    );
    const structHash = ethers.keccak256(encoded);
    const signature = await signer.signMessage(ethers.getBytes(structHash));
    return { deadline, signature, nonce };
  }

  async function consumeViaMover(mover, callerSigner, nft, pathId, movement, claimerSigner) {
    const executor = await mover.getAddress();
    const { deadline, signature } = await signConsumeAuthorization(
      nft,
      claimerSigner,
      claimerSigner.address,
      executor,
      pathId,
      movement
    );
    return mover
      .connect(callerSigner)
      .consume(await nft.getAddress(), pathId, movement, claimerSigner.address, deadline, signature);
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

  it("tokenURI returns base64 metadata with conventional keys and movement progress", async function () {
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

    const m0 = decodeMetadata(await nft.tokenURI(5n));
    expect(m0.name).to.equal("PATH #5");
    expect(m0.description).to.be.a("string");
    expect(m0.description).to.contain("permission token");
    expect(m0.image.startsWith("data:image/svg+xml;base64,")).to.equal(true);
    expect(Array.isArray(m0.attributes)).to.equal(true);
    expect(m0.stage).to.equal("THOUGHT");
    expect(m0.thought).to.equal("Minted(0/1)");
    expect(m0.will).to.equal("Minted(0/4)");
    expect(m0.awa).to.equal("Minted(0/1)");
    expect(m0.token).to.equal("5");

    const stageTrait0 = m0.attributes.find((x) => x.trait_type === "Stage");
    const thoughtTrait0 = m0.attributes.find((x) => x.trait_type === "THOUGHT");
    const willTrait0 = m0.attributes.find((x) => x.trait_type === "WILL");
    expect(stageTrait0.value).to.equal("THOUGHT");
    expect(thoughtTrait0.value).to.equal("Minted(0/1)");
    expect(willTrait0.value).to.equal("Minted(0/4)");

    const svg0 = Buffer.from(m0.image.split(",")[1], "base64").toString("utf8");
    expect(svg0).to.contain("<svg");
    expect(svg0).to.contain("id='will-box'");

    await (await consumeViaMover(mover, alice, nft, 5n, movements.THOUGHT, alice)).wait();
    await (await consumeViaMover(mover, alice, nft, 5n, movements.WILL, alice)).wait();

    const m1 = decodeMetadata(await nft.tokenURI(5n));
    expect(m1.stage).to.equal("WILL");
    expect(m1.thought).to.equal("Minted(1/1)");
    expect(m1.will).to.equal("Minted(1/4)");

    const willTrait1 = m1.attributes.find((x) => x.trait_type === "WILL");
    expect(willTrait1.value).to.equal("Minted(1/4)");
    expect(m1.image_data).to.contain("id='will-fill' x='270' y='270' width='15'");
  });

  it("supports ERC-4906 and emits MetadataUpdate on consumeUnit", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await (await nft.grantRole(roles.MINTER_ROLE, deployer.address)).wait();
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 2)).wait();
    await (await nft.safeMint(alice.address, 6n, "0x")).wait();

    expect(await nft.supportsInterface("0x49064906")).to.equal(true);

    await expect(
      consumeViaMover(mover, alice, nft, 6n, movements.THOUGHT, alice)
    ).to.emit(nft, "MetadataUpdate").withArgs(6n);
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

    await expect(
      nft.connect(bob).consumeUnit(21n, movements.THOUGHT, bob.address, 2n ** 255n, "0x")
    ).to.be.revertedWith("ERR_UNAUTHORIZED_MINTER");
  });

  it("consumeUnit enforces signed authorization and owner/approval checks", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice, bob, carol] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await (await nft.grantRole(roles.MINTER_ROLE, deployer.address)).wait();
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 1)).wait();
    await (await nft.safeMint(alice.address, 22n, "0x")).wait();

    const executor = await mover.getAddress();
    const bobAuth = await signConsumeAuthorization(
      nft,
      bob,
      bob.address,
      executor,
      22n,
      movements.THOUGHT
    );
    await expect(
      mover
        .connect(bob)
        .consume(await nft.getAddress(), 22n, movements.THOUGHT, bob.address, bobAuth.deadline, bobAuth.signature)
    ).to.be.revertedWith("ERR_NOT_OWNER");

    const badSignerAuth = await signConsumeAuthorization(
      nft,
      carol,
      bob.address,
      executor,
      22n,
      movements.THOUGHT
    );
    await expect(
      mover
        .connect(bob)
        .consume(await nft.getAddress(), 22n, movements.THOUGHT, bob.address, badSignerAuth.deadline, badSignerAuth.signature)
    ).to.be.revertedWith("BAD_CONSUME_AUTH");

    const wrongExecutorAuth = await signConsumeAuthorization(
      nft,
      bob,
      bob.address,
      alice.address,
      22n,
      movements.THOUGHT
    );
    await expect(
      mover
        .connect(bob)
        .consume(
          await nft.getAddress(),
          22n,
          movements.THOUGHT,
          bob.address,
          wrongExecutorAuth.deadline,
          wrongExecutorAuth.signature
        )
    ).to.be.revertedWith("BAD_CONSUME_AUTH");

    const expiringAuth = await signConsumeAuthorization(
      nft,
      bob,
      bob.address,
      executor,
      22n,
      movements.THOUGHT,
      1n
    );
    await ethers.provider.send("evm_increaseTime", [2]);
    await ethers.provider.send("evm_mine", []);

    await expect(
      mover
        .connect(bob)
        .consume(await nft.getAddress(), 22n, movements.THOUGHT, bob.address, expiringAuth.deadline, expiringAuth.signature)
    ).to.be.revertedWith("CONSUME_AUTH_EXPIRED");

    await (await nft.connect(alice).approve(bob.address, 22n)).wait();
    await (await consumeViaMover(mover, bob, nft, 22n, movements.THOUGHT, bob)).wait();

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
    await (await consumeViaMover(mover, bob, nft, 23n, movements.THOUGHT, bob)).wait();

    expect(await nft.getStage(23n)).to.equal(1n);
    expect(await nft.getStageMinted(23n)).to.equal(0n);
  });

  it("consumeUnit uses nonce-based auth and rejects signature replay", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, bob] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await (await nft.grantRole(roles.MINTER_ROLE, deployer.address)).wait();
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 2)).wait();
    await (await nft.safeMint(bob.address, 24n, "0x")).wait();

    const executor = await mover.getAddress();
    const auth = await signConsumeAuthorization(
      nft,
      bob,
      bob.address,
      executor,
      24n,
      movements.THOUGHT
    );
    await (
      await mover
        .connect(bob)
        .consume(await nft.getAddress(), 24n, movements.THOUGHT, bob.address, auth.deadline, auth.signature)
    ).wait();

    expect(await nft.getConsumeNonce(bob.address)).to.equal(1n);
    await expect(
      mover
        .connect(bob)
        .consume(await nft.getAddress(), 24n, movements.THOUGHT, bob.address, auth.deadline, auth.signature)
    ).to.be.revertedWith("BAD_CONSUME_AUTH");
  });

  it("consumeUnit accepts ERC-1271 contract-wallet signatures", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice, bob] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    const Wallet = await ethers.getContractFactory("Mock1271Wallet", deployer);
    const wallet = await Wallet.deploy(alice.address);
    await wallet.waitForDeployment();

    const walletAddress = await wallet.getAddress();
    const executor = await mover.getAddress();

    await (await nft.grantRole(roles.MINTER_ROLE, deployer.address)).wait();
    await (await nft.setMovementConfig(movements.THOUGHT, executor, 1)).wait();
    await (await nft.safeMint(walletAddress, 25n, "0x")).wait();

    const auth = await signConsumeAuthorization(
      nft,
      alice,
      walletAddress,
      executor,
      25n,
      movements.THOUGHT
    );

    await (
      await mover
        .connect(bob)
        .consume(await nft.getAddress(), 25n, movements.THOUGHT, walletAddress, auth.deadline, auth.signature)
    ).wait();

    expect(await nft.getStage(25n)).to.equal(1n);
    expect(await nft.getConsumeNonce(walletAddress)).to.equal(1n);
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
      consumeViaMover(mover, alice, nft, 31n, movements.WILL, alice)
    ).to.be.revertedWith("BAD_MOVEMENT_ORDER");

    await (await consumeViaMover(mover, alice, nft, 31n, movements.THOUGHT, alice)).wait();
    expect(await nft.getStage(31n)).to.equal(0n);
    expect(await nft.getStageMinted(31n)).to.equal(1n);

    await (await consumeViaMover(mover, alice, nft, 31n, movements.THOUGHT, alice)).wait();
    expect(await nft.getStage(31n)).to.equal(1n);
    expect(await nft.getStageMinted(31n)).to.equal(0n);

    await (await consumeViaMover(mover, alice, nft, 31n, movements.WILL, alice)).wait();
    await (await consumeViaMover(mover, alice, nft, 31n, movements.WILL, alice)).wait();
    await (await consumeViaMover(mover, alice, nft, 31n, movements.AWA, alice)).wait();

    expect(await nft.getStage(31n)).to.equal(3n);
    await expect(
      consumeViaMover(mover, alice, nft, 31n, movements.AWA, alice)
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

    await (await consumeViaMover(mover, alice, nft, 41n, movements.THOUGHT, alice)).wait();

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

    const first = await (await consumeViaMover(mover, alice, nft, 51n, movements.THOUGHT, alice)).wait();
    const second = await (await consumeViaMover(mover, alice, nft, 51n, movements.THOUGHT, alice)).wait();
    const third = await (await consumeViaMover(mover, alice, nft, 51n, movements.WILL, alice)).wait();

    const frozenLogs = await nft.queryFilter(nft.filters.MovementFrozen(), first.blockNumber, third.blockNumber);
    const thoughtFrozen = frozenLogs.filter((log) => log.args.movement === movements.THOUGHT);
    const willFrozen = frozenLogs.filter((log) => log.args.movement === movements.WILL);

    expect(second.status).to.equal(1);
    expect(thoughtFrozen.length).to.equal(1);
    expect(willFrozen.length).to.equal(1);
  });
});
