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

  function decodeContractMetadata(uri) {
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

  async function grantAndFreezePublicMinter(nft, roles, minterAddress) {
    await (await nft.grantRole(roles.MINTER_ROLE, minterAddress)).wait();
    await (await nft.freezePublicMinter(minterAddress)).wait();
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

    expect(await nft.name()).to.equal("PATH");
    expect(await nft.symbol()).to.equal("PATH");
    expect(await nft.hasRole(roles.DEFAULT_ADMIN_ROLE, deployer.address)).to.equal(true);
  });

  it("constructor rejects zero admin", async function () {
    const [deployer] = await ethers.getSigners();
    const Nft = await ethers.getContractFactory("PathNFT", deployer);

    await expect(
      Nft.deploy(ethers.ZeroAddress, "PATH", "PATH", "")
    ).to.be.revertedWith("ZERO_ADMIN");
  });

  it("safeMint requires a frozen public minter", async function () {
    const { deployer, nft, roles } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    await expectAnyRevert(nft.connect(alice).safeMint(alice.address, 1n, "0x"));

    await (await nft.grantRole(roles.MINTER_ROLE, deployer.address)).wait();
    await expect(nft.safeMint(alice.address, 1n, "0x")).to.be.revertedWith("PUBLIC_MINTER_NOT_FROZEN");
    await expect(nft.freezePublicMinter(deployer.address))
      .to.emit(nft, "PublicMinterFrozen")
      .withArgs(deployer.address);
    await (await nft.safeMint(alice.address, 1n, "0x")).wait();

    expect(await nft.ownerOf(1n)).to.equal(alice.address);
    expect(await nft.getStage(1n)).to.equal(0n);
    expect(await nft.getStageMinted(1n)).to.equal(0n);
  });

  it("freezePublicMinter makes the selected minter exclusive and freezes MINTER_ROLE admin", async function () {
    const { deployer, nft, roles } = await deployPathNftEnv(ethers);
    const [, alice, bob, carol] = await ethers.getSigners();

    await expectAnyRevert(nft.connect(alice).freezePublicMinter(alice.address));
    await expect(nft.freezePublicMinter(ethers.ZeroAddress)).to.be.revertedWith("ZERO_PUBLIC_MINTER");
    await expect(nft.freezePublicMinter(alice.address)).to.be.revertedWith("MISSING_MINTER_ROLE");

    await (await nft.grantRole(roles.MINTER_ROLE, deployer.address)).wait();
    await (await nft.grantRole(roles.MINTER_ROLE, bob.address)).wait();
    await (await nft.freezePublicMinter(deployer.address)).wait();

    expect(await nft.publicMinter()).to.equal(deployer.address);
    expect(await nft.publicMinterFrozen()).to.equal(true);
    expect(await nft.getRoleAdmin(roles.MINTER_ROLE)).to.equal(roles.FROZEN_MINTER_ADMIN_ROLE);
    expect(await nft.hasRole(roles.FROZEN_MINTER_ADMIN_ROLE, deployer.address)).to.equal(false);

    await expect(nft.freezePublicMinter(bob.address)).to.be.revertedWith("PUBLIC_MINTER_FROZEN");
    await expect(nft.connect(bob).safeMint(bob.address, 3n, "0x")).to.be.revertedWith("NOT_PUBLIC_MINTER");
    await expectAnyRevert(nft.grantRole(roles.MINTER_ROLE, carol.address));
    await expectAnyRevert(nft.revokeRole(roles.MINTER_ROLE, deployer.address));
    expect(await nft.hasRole(roles.MINTER_ROLE, deployer.address)).to.equal(true);
  });

  it("safe_mint alias matches safeMint behavior", async function () {
    const { deployer, nft, roles } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.safe_mint(alice.address, 2n, "0x1234")).wait();

    expect(await nft.ownerOf(2n)).to.equal(alice.address);
    expect(await nft.getStage(2n)).to.equal(0n);
    expect(await nft.getStageMinted(2n)).to.equal(0n);
  });

  it("token getters and tokenURI reject nonexistent token ids", async function () {
    const { nft } = await deployPathNftEnv(ethers);

    await expect(nft.getStage(999n)).to.be.revertedWith("ERC721: invalid token ID");
    await expect(nft.getStageMinted(999n)).to.be.revertedWith("ERC721: invalid token ID");
    await expect(nft.tokenURI(999n)).to.be.revertedWith("ERC721: invalid token ID");
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

  it("freezeMovementConfig validates and explicitly locks configured movement settings", async function () {
    const { nft, movements } = await deployPathNftEnv(ethers);
    const [, alice, bob] = await ethers.getSigners();

    await expectAnyRevert(nft.connect(alice).freezeMovementConfig(movements.THOUGHT));
    await expect(nft.freezeMovementConfig(movements.DREAM)).to.be.revertedWith("BAD_MOVEMENT");
    await expect(nft.isMovementFrozen(movements.DREAM)).to.be.revertedWith("BAD_MOVEMENT");
    await expect(nft.freezeMovementConfig(movements.THOUGHT)).to.be.revertedWith("MOVEMENT_NOT_CONFIGURED");

    expect(await nft.isMovementFrozen(movements.THOUGHT)).to.equal(false);
    await (await nft.setMovementConfig(movements.THOUGHT, bob.address, 1)).wait();

    await expect(nft.freezeMovementConfig(movements.THOUGHT))
      .to.emit(nft, "MovementFrozen")
      .withArgs(movements.THOUGHT);

    expect(await nft.isMovementFrozen(movements.THOUGHT)).to.equal(true);
    await expect(nft.setMovementConfig(movements.THOUGHT, alice.address, 2)).to.be.revertedWith("MOVEMENT_FROZEN");
    await expect(nft.freezeMovementConfig(movements.THOUGHT)).to.be.revertedWith("MOVEMENT_FROZEN");
  });

  it("tokenURI returns base64 metadata with conventional keys and movement progress", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 1)).wait();
    await (await nft.setMovementConfig(movements.WILL, await mover.getAddress(), 4)).wait();
    await (await nft.setMovementConfig(movements.AWA, await mover.getAddress(), 1)).wait();
    await (await nft.safeMint(alice.address, 5n, "0x1234")).wait();

    const m0 = decodeMetadata(await nft.tokenURI(5n));
    expect(m0.name).to.equal("PATH #5");
    expect(m0.description).to.equal(
      "PATH is a permission token for Inshell generative artworks. Holding PATH authorizes movement mints in order: THOUGHT, WILL, then AWA. The image and traits show this PATH token's movement progress."
    );
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
    expect(svg0).to.contain("id='blank-mark-thought'");
    expect(svg0).to.contain("id='blank-mark-will'");
    expect(svg0).to.contain("id='blank-mark-awa'");

    await (await consumeViaMover(mover, alice, nft, 5n, movements.THOUGHT, alice)).wait();
    await (await consumeViaMover(mover, alice, nft, 5n, movements.WILL, alice)).wait();

    const m1 = decodeMetadata(await nft.tokenURI(5n));
    expect(m1.stage).to.equal("WILL");
    expect(m1.thought).to.equal("Minted(1/1)");
    expect(m1.will).to.equal("Minted(1/4)");

    const willTrait1 = m1.attributes.find((x) => x.trait_type === "WILL");
    expect(willTrait1.value).to.equal("Minted(1/4)");
    expect(m1.image_data).to.contain("<circle id='thought-box' cx='210' cy='300' r='30'");
    expect(m1.image_data).to.contain("id='thought-fill' cx='210' cy='300' r='30'");
    expect(m1.image_data).to.contain("id='will-fill' cx='300' cy='300' r='7.5'");
    expect(m1.image_data).not.to.contain("clip-path");
    expect(m1.image_data).not.to.contain("id='blank-mark-thought'");
    expect(m1.image_data).not.to.contain("id='blank-mark-will'");
    expect(m1.image_data).to.contain("id='blank-mark-awa'");
  });

  it("token image fills each movement slot proportionally to quota progress", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 3)).wait();
    await (await nft.setMovementConfig(movements.WILL, await mover.getAddress(), 2)).wait();
    await (await nft.setMovementConfig(movements.AWA, await mover.getAddress(), 2)).wait();
    await (await nft.safeMint(alice.address, 6n, "0x")).wait();

    await (await consumeViaMover(mover, alice, nft, 6n, movements.THOUGHT, alice)).wait();
    await (await consumeViaMover(mover, alice, nft, 6n, movements.THOUGHT, alice)).wait();

    const thoughtInProgress = decodeMetadata(await nft.tokenURI(6n));
    expect(thoughtInProgress.stage).to.equal("THOUGHT");
    expect(thoughtInProgress.thought).to.equal("Minted(2/3)");
    expect(thoughtInProgress.image_data).to.contain("<circle id='thought-box' cx='210' cy='300' r='30'");
    expect(thoughtInProgress.image_data).to.contain("id='thought-fill' cx='210' cy='300' r='20'");
    expect(thoughtInProgress.image_data).not.to.contain("clip-path");
    expect(thoughtInProgress.image_data).not.to.contain("id='will-fill'");
    expect(thoughtInProgress.image_data).not.to.contain("id='awa-fill'");

    await (await consumeViaMover(mover, alice, nft, 6n, movements.THOUGHT, alice)).wait();
    await (await consumeViaMover(mover, alice, nft, 6n, movements.WILL, alice)).wait();
    await (await consumeViaMover(mover, alice, nft, 6n, movements.WILL, alice)).wait();
    await (await consumeViaMover(mover, alice, nft, 6n, movements.AWA, alice)).wait();

    const awaInProgress = decodeMetadata(await nft.tokenURI(6n));
    expect(awaInProgress.stage).to.equal("AWA");
    expect(awaInProgress.thought).to.equal("Minted(3/3)");
    expect(awaInProgress.will).to.equal("Minted(2/2)");
    expect(awaInProgress.awa).to.equal("Minted(1/2)");
    expect(awaInProgress.image_data).to.contain("id='thought-fill' cx='210' cy='300' r='30'");
    expect(awaInProgress.image_data).to.contain("id='will-fill' cx='300' cy='300' r='30'");
    expect(awaInProgress.image_data).to.contain("id='awa-fill' cx='390' cy='300' r='15'");
    expect(awaInProgress.image_data).not.to.contain("clip-path");
  });

  it("contractURI returns on-chain collection metadata", async function () {
    const { nft } = await deployPathNftEnv(ethers);
    const metadata = decodeContractMetadata(await nft.contractURI());

    expect(metadata.name).to.equal("PATH");
    expect(metadata.description).to.equal(
      "PATH is the permission-token collection for Inshell generative artworks. Each PATH progresses through THOUGHT, WILL, and AWA by consuming movement units."
    );
    expect(metadata.image.startsWith("data:image/svg+xml;base64,")).to.equal(true);
    expect(metadata.external_link).to.equal("https://github.com/inshell-art/path");
  });

  it("tokenURI remains self-contained and marketplace-shaped when movements are not configured", async function () {
    const { deployer, nft, roles } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.safeMint(alice.address, 7n, "0x")).wait();

    const metadata = decodeMetadata(await nft.tokenURI(7n));
    const decodedImage = Buffer.from(metadata.image.split(",")[1], "base64").toString("utf8");

    expect(metadata.name).to.equal("PATH #7");
    expect(metadata.image.startsWith("data:image/svg+xml;base64,")).to.equal(true);
    expect(metadata.image_data).to.equal(decodedImage);
    expect(metadata.image_data).to.contain("<svg");
    expect(metadata.image_data).to.contain("<rect width='600' height='600' fill='black'/>");
    expect(metadata.attributes.map((x) => x.trait_type)).to.deep.equal([
      "Stage",
      "THOUGHT",
      "WILL",
      "AWA"
    ]);
    expect(metadata.stage).to.equal("THOUGHT");
    expect(metadata.thought).to.equal("Minted(0/0)");
    expect(metadata.will).to.equal("Minted(0/0)");
    expect(metadata.awa).to.equal("Minted(0/0)");
  });

  it("supports ERC-4906 and emits MetadataUpdate on consumeUnit", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 2)).wait();
    await (await nft.safeMint(alice.address, 6n, "0x")).wait();

    expect(await nft.supportsInterface("0x49064906")).to.equal(true);
    expect(await nft.supportsInterface("0x80ac58cd")).to.equal(true); // ERC721
    expect(await nft.supportsInterface("0x7965db0b")).to.equal(true); // AccessControl
    expect(await nft.supportsInterface("0x01ffc9a7")).to.equal(true); // IERC165
    expect(await nft.supportsInterface("0xffffffff")).to.equal(false);

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

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 1)).wait();
    await (await nft.safeMint(alice.address, 21n, "0x")).wait();

    await expect(
      nft.connect(bob).consumeUnit(21n, movements.THOUGHT, bob.address, 2n ** 255n, "0x")
    ).to.be.revertedWith("ERR_UNAUTHORIZED_MINTER");

    await expect(
      mover.connect(alice).consume(await nft.getAddress(), 21n, movements.DREAM, alice.address, 2n ** 255n, "0x")
    ).to.be.revertedWith("BAD_MOVEMENT");
  });

  it("consumeUnit rejects nonexistent token ids", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 1)).wait();

    const executor = await mover.getAddress();
    const auth = await signConsumeAuthorization(
      nft,
      alice,
      alice.address,
      executor,
      999n,
      movements.THOUGHT
    );

    await expect(
      mover
        .connect(alice)
        .consume(await nft.getAddress(), 999n, movements.THOUGHT, alice.address, auth.deadline, auth.signature)
    ).to.be.revertedWith("ERC721: invalid token ID");
  });

  it("consumeUnit enforces signed authorization and owner/approval checks", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice, bob, carol] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
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

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
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

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
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

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
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

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
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

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 1)).wait();
    await (await nft.setMovementConfig(movements.WILL, bob.address, 2)).wait();
    await (await nft.safeMint(alice.address, 41n, "0x")).wait();

    expect(await nft.isMovementFrozen(movements.THOUGHT)).to.equal(false);
    await (await consumeViaMover(mover, alice, nft, 41n, movements.THOUGHT, alice)).wait();
    expect(await nft.isMovementFrozen(movements.THOUGHT)).to.equal(true);

    await expect(nft.setMovementConfig(movements.THOUGHT, bob.address, 2)).to.be.revertedWith("MOVEMENT_FROZEN");

    await (await nft.setMovementConfig(movements.WILL, alice.address, 3)).wait();
    expect(await nft.getAuthorizedMinter(movements.WILL)).to.equal(alice.address);
    expect(await nft.getMovementQuota(movements.WILL)).to.equal(3n);
  });

  it("consumeUnit works after explicit movement freeze without emitting another freeze event", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 1)).wait();
    await (await nft.freezeMovementConfig(movements.THOUGHT)).wait();
    await (await nft.safeMint(alice.address, 42n, "0x")).wait();

    await expect(
      consumeViaMover(mover, alice, nft, 42n, movements.THOUGHT, alice)
    ).not.to.emit(nft, "MovementFrozen");

    expect(await nft.getStage(42n)).to.equal(1n);
    expect(await nft.getStageMinted(42n)).to.equal(0n);
  });

  it("emits MovementConsumed with serial progression", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 2)).wait();
    await (await nft.safeMint(alice.address, 52n, "0x")).wait();

    await expect(consumeViaMover(mover, alice, nft, 52n, movements.THOUGHT, alice))
      .to.emit(nft, "MovementConsumed")
      .withArgs(52n, movements.THOUGHT, alice.address, 0n);

    await expect(consumeViaMover(mover, alice, nft, 52n, movements.THOUGHT, alice))
      .to.emit(nft, "MovementConsumed")
      .withArgs(52n, movements.THOUGHT, alice.address, 1n);
  });

  it("emits MovementFrozen only on first consume of each movement", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
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
