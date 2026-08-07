import { expect } from "chai";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import hre from "hardhat";
import { RESERVED_CAP, SPARK_BASE, SPARK_CLAIM_DURATION_SEC } from "./helpers/constants.js";
import { deployPathNftEnv } from "./helpers/fixtures.js";
import { mineAt, setNextBlockTimestamp } from "./helpers/time.js";

const pathGlyphSliceBytes = readFileSync(
  new URL("../glyphs/inshell-mono-76-path-400.json", import.meta.url)
);
const pathGlyphSlice = JSON.parse(pathGlyphSliceBytes.toString("utf8"));
const pathGlyphSliceSha256 = createHash("sha256").update(pathGlyphSliceBytes).digest("hex");

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

  function expectCanonicalTokenSvg(svg) {
    expect(svg).to.contain("data-renderer='path-text-status'");
    expect(svg).to.contain("data-rendering='native-svg-paths'");
    expect(svg).to.contain("data-progress-model='text'");
    expect(svg).to.contain("data-family='Inshell Mono 76'");
    expect(svg).to.contain("data-face='Inshell Mono 76 Regular'");
    expect(svg).to.contain("data-weight='400'");
    expect(svg).to.contain(
      "data-release-commit='6fefbfaf762dce0148fe275baafb8e7dd2077beb'"
    );
    expect(svg).to.contain(`data-manifest-sha256='${pathGlyphSlice.source.manifestSha256}'`);
    expect(svg).to.contain(`data-glyph-json-sha256='${pathGlyphSlice.source.glyphJsonSha256}'`);
    expect(svg).to.contain(`data-glyph-slice-sha256='${pathGlyphSliceSha256}'`);
    expect(svg).to.contain("data-center-x='300' data-center-y='300'");
    expect(svg).to.contain("id='path-title'");
    expect(svg).to.contain("data-text-layout='centered-group'");
    expect(svg).to.contain("clip-path='url(#path-progress)'");
    expect(svg.match(/<path id='g-/g)).to.have.length(9);
    for (const glyph of pathGlyphSlice.glyphs) {
      expect(svg).to.contain(`<path id='g-${glyph.character}' d='${glyph.d}'/>`);
    }
    expect(svg).not.to.contain("<text");
    expect(svg).not.to.contain("<circle");
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
      "ConsumeAuthorization(address pathNft,uint256 chainId,uint256 pathId,bytes32 movement,address claimer,address executor,uint256 permissionEpoch,uint256 nonce,uint256 deadline)"
    );
    const permissionEpoch = await nft.getPermissionEpoch(pathId);
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
        "uint256",
        "uint256"
      ],
      [typeHash, pathNft, chainId, pathId, movement, claimer, executor, permissionEpoch, nonce, deadline]
    );
    const structHash = ethers.keccak256(encoded);
    const signature = await signer.signMessage(ethers.getBytes(structHash));
    return { deadline, signature, permissionEpoch, nonce };
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

  function sparkNameHash(name) {
    return ethers.keccak256(ethers.toUtf8Bytes(name));
  }

  async function allowSpark(nft, issuer, recipient, name) {
    return nft.connect(issuer).allowSparker(recipient, name);
  }

  async function claimSpark(nft, recipient, name, data = "0x") {
    return nft.connect(recipient).mintSparker(sparkNameHash(name), data);
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
    expect(await nft.SPARK_BASE()).to.equal(SPARK_BASE);
    expect(await nft.sparkClaimDuration()).to.equal(SPARK_CLAIM_DURATION_SEC);
    expect(await nft.getReservedCap()).to.equal(RESERVED_CAP);
    expect(await nft.getReservedRemaining()).to.equal(RESERVED_CAP);
    expect(await nft.getReservedPending()).to.equal(0n);
  });

  it("keeps at least 512 bytes of PathNFT runtime headroom under EIP-170", async function () {
    const { nft } = await deployPathNftEnv(ethers);
    const runtimeCode = await ethers.provider.getCode(await nft.getAddress());
    const runtimeBytes = (runtimeCode.length - 2) / 2;

    expect(runtimeBytes).to.be.lessThanOrEqual(24_064);
  });

  it("constructor rejects zero admin", async function () {
    const [deployer] = await ethers.getSigners();
    const Nft = await ethers.getContractFactory("PathNFT", deployer);

    await expect(
      Nft.deploy(ethers.ZeroAddress, "PATH", "PATH", "", RESERVED_CAP, SPARK_CLAIM_DURATION_SEC)
    ).to.be.revertedWithCustomError(Nft, "ZeroAdmin");

    await expect(
      Nft.deploy(deployer.address, "PATH", "PATH", "", RESERVED_CAP, 0)
    ).to.be.revertedWithCustomError(Nft, "ZeroSparkClaimDuration");
  });

  it("safeMint requires a frozen public minter", async function () {
    const { deployer, nft, roles } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    await expectAnyRevert(nft.connect(alice).safeMint(alice.address, 1n, "0x"));

    await (await nft.grantRole(roles.MINTER_ROLE, deployer.address)).wait();
    await expect(nft.safeMint(alice.address, 1n, "0x"))
      .to.be.revertedWithCustomError(nft, "PublicMinterNotFrozen");
    await expect(nft.freezePublicMinter(deployer.address))
      .to.emit(nft, "PublicMinterFrozen")
      .withArgs(deployer.address);
    await expect(nft.safeMint(alice.address, 1n, "0x"))
      .to.emit(nft, "Unlocked")
      .withArgs(1n);

    expect(await nft.ownerOf(1n)).to.equal(alice.address);
    expect(await nft.getStage(1n)).to.equal(0n);
    expect(await nft.getStageMinted(1n)).to.equal(0n);
    expect(await nft.getPermissionEpoch(1n)).to.equal(0n);
    expect(await nft.isSparker(1n)).to.equal(false);
  });

  it("safeMint reserves the SPARK_BASE token domain for sparkers", async function () {
    const { deployer, nft, roles } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);

    await (await nft.safeMint(alice.address, SPARK_BASE - 1n, "0x")).wait();
    expect(await nft.ownerOf(SPARK_BASE - 1n)).to.equal(alice.address);

    await expect(nft.safeMint(alice.address, SPARK_BASE, "0x"))
      .to.be.revertedWithCustomError(nft, "PublicTokenIdDomainExhausted");
    await expect(nft.safe_mint(alice.address, SPARK_BASE, "0x"))
      .to.be.revertedWithCustomError(nft, "PublicTokenIdDomainExhausted");
  });

  it("allowSparker enforces role, recipient, and JSON-safe short names", async function () {
    const { nft, roles } = await deployPathNftEnv(ethers);
    const [, issuer, alice, bob] = await ethers.getSigners();

    await expectAnyRevert(allowSpark(nft, issuer, alice.address, "Alice"));
    await (await nft.grantRole(roles.RESERVED_ROLE, issuer.address)).wait();

    await expect(allowSpark(nft, issuer, ethers.ZeroAddress, "Alice"))
      .to.be.revertedWithCustomError(nft, "ZeroSparkRecipient");
    for (const invalidName of ["", " Alice", "Alice ", "A".repeat(32), "Alice \"Ace\"", "Alice\\Bob", "Alice\nBob", "Alíce"]) {
      await expect(allowSpark(nft, issuer, alice.address, invalidName))
        .to.be.revertedWithCustomError(nft, "InvalidSparkName");
    }

    await expect(allowSpark(nft, issuer, alice.address, "Alice O'Neil"))
      .to.emit(nft, "SparkerAllowed");

    const maxName = "A".repeat(31);
    await (await allowSpark(nft, issuer, bob.address, maxName)).wait();
    await (await claimSpark(nft, bob, maxName)).wait();
    expect(await nft.sparkName(SPARK_BASE)).to.equal(maxName);
  });

  it("allowSparker reserves one guaranteed slot and stores the issuer name", async function () {
    const { nft, roles } = await deployPathNftEnv(ethers);
    const [, issuer, alice] = await ethers.getSigners();

    await (await nft.grantRole(roles.RESERVED_ROLE, issuer.address)).wait();
    const tx = await allowSpark(nft, issuer, alice.address, "Alice");
    const receipt = await tx.wait();
    const block = await ethers.provider.getBlock(receipt.blockNumber);
    const expectedExpiry = BigInt(block.timestamp) + SPARK_CLAIM_DURATION_SEC;
    const [expiresAt, name] = await nft.getSparkInvitation(alice.address);

    expect(expiresAt).to.equal(expectedExpiry);
    expect(name).to.equal("Alice");
    expect(await nft.getReservedRemaining()).to.equal(RESERVED_CAP - 1n);
    expect(await nft.getReservedPending()).to.equal(1n);
  });

  it("allowSparker prevents invitation overbooking", async function () {
    const { nft, roles } = await deployPathNftEnv(ethers, { reservedCap: 1n });
    const [, issuer, alice, bob] = await ethers.getSigners();

    await (await nft.grantRole(roles.RESERVED_ROLE, issuer.address)).wait();
    await (await allowSpark(nft, issuer, alice.address, "Alice")).wait();

    expect(await nft.getReservedRemaining()).to.equal(0n);
    expect(await nft.getReservedPending()).to.equal(1n);
    await expect(allowSpark(nft, issuer, bob.address, "Bob"))
      .to.be.revertedWithCustomError(nft, "NoReservedSparkAvailable");
  });

  it("allowSparker refreshes only the same active name without reserving twice", async function () {
    const { nft, roles } = await deployPathNftEnv(ethers);
    const [, issuer, alice] = await ethers.getSigners();

    await (await nft.grantRole(roles.RESERVED_ROLE, issuer.address)).wait();
    await (await allowSpark(nft, issuer, alice.address, "Alice")).wait();
    const [firstExpiry] = await nft.getSparkInvitation(alice.address);

    await mineAt(conn.provider, firstExpiry - (SPARK_CLAIM_DURATION_SEC / 2n));
    await expect(allowSpark(nft, issuer, alice.address, "Alice Two"))
      .to.be.revertedWithCustomError(nft, "SparkNameMismatch");
    await (await allowSpark(nft, issuer, alice.address, "Alice")).wait();

    const [refreshedExpiry, name] = await nft.getSparkInvitation(alice.address);
    expect(refreshedExpiry).to.be.greaterThan(firstExpiry);
    expect(name).to.equal("Alice");
    expect(await nft.getReservedRemaining()).to.equal(RESERVED_CAP - 1n);
    expect(await nft.getReservedPending()).to.equal(1n);
  });

  it("mintSparker binds the displayed name and creates named ERC-5192 metadata", async function () {
    const { nft, roles } = await deployPathNftEnv(ethers);
    const [, issuer, alice, bob] = await ethers.getSigners();
    const name = "Alice O'Neil";

    await (await nft.grantRole(roles.RESERVED_ROLE, issuer.address)).wait();
    await (await allowSpark(nft, issuer, alice.address, name)).wait();

    await expect(claimSpark(nft, bob, name))
      .to.be.revertedWithCustomError(nft, "SparkInvitationMissing");
    await expect(claimSpark(nft, alice, "Different Name"))
      .to.be.revertedWithCustomError(nft, "SparkNameMismatch");

    const id = await nft.connect(alice).mintSparker.staticCall(sparkNameHash(name), "0x");
    const claim = nft.connect(alice).mintSparker(sparkNameHash(name), "0x");
    await expect(claim).to.emit(nft, "SparkerMinted").withArgs(alice.address, id);
    await expect(claim).to.emit(nft, "Locked").withArgs(id);

    expect(id).to.equal(SPARK_BASE);
    expect(await nft.ownerOf(id)).to.equal(alice.address);
    expect(await nft.isSparker(id)).to.equal(true);
    expect(await nft.locked(id)).to.equal(true);
    expect(await nft.sparkName(id)).to.equal(name);
    expect(await nft.getSparkInvitation(alice.address)).to.deep.equal([0n, ""]);
    expect(await nft.getReservedRemaining()).to.equal(RESERVED_CAP - 1n);
    expect(await nft.getReservedPending()).to.equal(0n);

    const metadata = decodeMetadata(await nft.tokenURI(id));
    expect(metadata.name).to.equal(`PATH Spark #1: ${name}`);
    expect(metadata.description).to.equal(
      "Spark is a permanent acknowledgment by Inshell of those who resonate with Inshell's artistic vision, inviting them to participate in the unfolding journey of a movement. This soulbound PATH carries movement permission in order: THOUGHT, WILL, then AWA."
    );
    expect(metadata.token).to.equal(id.toString());
    expect(metadata.attributes.map((attribute) => attribute.trait_type)).to.deep.equal([
      "Stage",
      "THOUGHT",
      "WILL",
      "AWA"
    ]);
  });

  it("uses unpadded Spark numbers beyond 99 without changing ERC-721 token IDs", async function () {
    this.timeout(120_000);
    const { nft, roles } = await deployPathNftEnv(ethers, { reservedCap: 100n });
    const [, issuer, alice] = await ethers.getSigners();

    await (await nft.grantRole(roles.RESERVED_ROLE, issuer.address)).wait();
    for (let serial = 1; serial <= 100; serial += 1) {
      const name = `Recipient ${serial}`;
      await (await allowSpark(nft, issuer, alice.address, name)).wait();
      await (await claimSpark(nft, alice, name)).wait();
    }

    const tokenId = SPARK_BASE + 99n;
    const metadata = decodeMetadata(await nft.tokenURI(tokenId));
    expect(await nft.ownerOf(tokenId)).to.equal(alice.address);
    expect(metadata.name).to.equal("PATH Spark #100: Recipient 100");
    expect(metadata.name).not.to.contain("#0100");
    expect(metadata.token).to.equal(tokenId.toString());
  });

  it("mintSparker accepts the exact expiry block", async function () {
    const { nft, roles } = await deployPathNftEnv(ethers);
    const [, issuer, alice] = await ethers.getSigners();

    await (await nft.grantRole(roles.RESERVED_ROLE, issuer.address)).wait();
    await (await allowSpark(nft, issuer, alice.address, "Alice")).wait();
    const [expiresAt] = await nft.getSparkInvitation(alice.address);

    await setNextBlockTimestamp(conn.provider, expiresAt);
    await (await claimSpark(nft, alice, "Alice")).wait();
    expect(await nft.ownerOf(SPARK_BASE)).to.equal(alice.address);
  });

  it("releaseExpiredSparker is permissionless after expiry and returns the slot", async function () {
    const { nft, roles } = await deployPathNftEnv(ethers, { reservedCap: 1n });
    const [, issuer, alice, bob] = await ethers.getSigners();

    await (await nft.grantRole(roles.RESERVED_ROLE, issuer.address)).wait();
    await (await allowSpark(nft, issuer, alice.address, "Alice")).wait();
    const [expiresAt] = await nft.getSparkInvitation(alice.address);

    await expect(nft.connect(bob).releaseExpiredSparker(alice.address))
      .to.be.revertedWithCustomError(nft, "SparkInvitationActive");
    await mineAt(conn.provider, expiresAt + 1n);
    await expect(claimSpark(nft, alice, "Alice"))
      .to.be.revertedWithCustomError(nft, "SparkInvitationExpired");
    await expect(nft.connect(bob).releaseExpiredSparker(alice.address))
      .to.emit(nft, "SparkerInvitationReleased")
      .withArgs(alice.address);

    expect(await nft.getReservedRemaining()).to.equal(1n);
    expect(await nft.getReservedPending()).to.equal(0n);
    expect(await nft.getSparkInvitation(alice.address)).to.deep.equal([0n, ""]);
    await expect(nft.connect(bob).releaseExpiredSparker(alice.address))
      .to.be.revertedWithCustomError(nft, "SparkInvitationMissing");
  });

  it("revokeSparker lets only RESERVED_ROLE return an active slot", async function () {
    const { nft, roles } = await deployPathNftEnv(ethers, { reservedCap: 1n });
    const [, issuer, alice, bob] = await ethers.getSigners();

    await (await nft.grantRole(roles.RESERVED_ROLE, issuer.address)).wait();
    await (await allowSpark(nft, issuer, alice.address, "Alice")).wait();

    await expectAnyRevert(nft.connect(bob).revokeSparker(alice.address));
    await expect(nft.connect(issuer).revokeSparker(alice.address))
      .to.emit(nft, "SparkerInvitationReleased")
      .withArgs(alice.address);
    expect(await nft.getReservedRemaining()).to.equal(1n);
    expect(await nft.getReservedPending()).to.equal(0n);
  });

  it("allowSparker atomically recycles an expired invitation with a new name", async function () {
    const { nft, roles } = await deployPathNftEnv(ethers, { reservedCap: 1n });
    const [, issuer, alice] = await ethers.getSigners();

    await (await nft.grantRole(roles.RESERVED_ROLE, issuer.address)).wait();
    await (await allowSpark(nft, issuer, alice.address, "Alice")).wait();
    const [expiresAt] = await nft.getSparkInvitation(alice.address);
    await mineAt(conn.provider, expiresAt + 1n);

    await (await allowSpark(nft, issuer, alice.address, "Alice Two")).wait();
    const [replacementExpiry, replacementName] = await nft.getSparkInvitation(alice.address);
    expect(replacementExpiry).to.be.greaterThan(expiresAt);
    expect(replacementName).to.equal("Alice Two");
    expect(await nft.getReservedRemaining()).to.equal(0n);
    expect(await nft.getReservedPending()).to.equal(1n);
    await expect(claimSpark(nft, alice, "Alice"))
      .to.be.revertedWithCustomError(nft, "SparkNameMismatch");
    await (await claimSpark(nft, alice, "Alice Two")).wait();
    expect(await nft.sparkName(SPARK_BASE)).to.equal("Alice Two");
    await expect(claimSpark(nft, alice, "Alice Two"))
      .to.be.revertedWithCustomError(nft, "SparkInvitationMissing");
  });

  it("Spark slot accounting preserves sequential IDs across revocations", async function () {
    const { nft, roles } = await deployPathNftEnv(ethers);
    const [, issuer, alice, bob, carol, dave] = await ethers.getSigners();

    await (await nft.grantRole(roles.RESERVED_ROLE, issuer.address)).wait();
    await (await allowSpark(nft, issuer, alice.address, "Alice")).wait();
    await (await allowSpark(nft, issuer, bob.address, "Bob")).wait();
    await (await allowSpark(nft, issuer, carol.address, "Carol")).wait();
    expect(await nft.getReservedRemaining()).to.equal(0n);
    expect(await nft.getReservedPending()).to.equal(3n);
    await expect(allowSpark(nft, issuer, dave.address, "Dave"))
      .to.be.revertedWithCustomError(nft, "NoReservedSparkAvailable");

    await (await claimSpark(nft, alice, "Alice")).wait();
    await (await nft.connect(issuer).revokeSparker(bob.address)).wait();
    await (await claimSpark(nft, carol, "Carol")).wait();
    await (await allowSpark(nft, issuer, dave.address, "Dave")).wait();
    await (await claimSpark(nft, dave, "Dave")).wait();

    expect(await nft.ownerOf(SPARK_BASE)).to.equal(alice.address);
    expect(await nft.ownerOf(SPARK_BASE + 1n)).to.equal(carol.address);
    expect(await nft.ownerOf(SPARK_BASE + 2n)).to.equal(dave.address);
    expect(await nft.getReservedRemaining()).to.equal(0n);
    expect(await nft.getReservedPending()).to.equal(0n);
  });

  it("Spark is ERC-5192 locked while regular PATH remains transferable", async function () {
    const { deployer, nft, roles } = await deployPathNftEnv(ethers);
    const [, issuer, alice, bob] = await ethers.getSigners();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.safeMint(alice.address, 1n, "0x")).wait();
    await (await nft.grantRole(roles.RESERVED_ROLE, issuer.address)).wait();
    await (await allowSpark(nft, issuer, alice.address, "Alice")).wait();
    await (await claimSpark(nft, alice, "Alice")).wait();

    expect(await nft.supportsInterface("0xb45a3c0e")).to.equal(true);
    expect(await nft.locked(1n)).to.equal(false);
    expect(await nft.sparkName(1n)).to.equal("");
    expect(await nft.locked(SPARK_BASE)).to.equal(true);
    await expect(nft.locked(999n)).to.be.revertedWith("ERC721: invalid token ID");

    await (await nft.connect(alice).approve(bob.address, SPARK_BASE)).wait();
    await expect(nft.connect(bob).transferFrom(alice.address, bob.address, SPARK_BASE))
      .to.be.revertedWithCustomError(nft, "SparkSoulbound");
    await (await nft.connect(alice).setApprovalForAll(bob.address, true)).wait();
    await expect(
      nft.connect(bob)["safeTransferFrom(address,address,uint256)"](
        alice.address,
        bob.address,
        SPARK_BASE
      )
    ).to.be.revertedWithCustomError(nft, "SparkSoulbound");
    await expect(
      nft.connect(alice)["safeTransferFrom(address,address,uint256,bytes)"](
        alice.address,
        bob.address,
        SPARK_BASE,
        "0x1234"
      )
    ).to.be.revertedWithCustomError(nft, "SparkSoulbound");
    await expect(nft.connect(alice).transferFrom(alice.address, alice.address, SPARK_BASE))
      .to.be.revertedWithCustomError(nft, "SparkSoulbound");

    expect(await nft.ownerOf(SPARK_BASE)).to.equal(alice.address);
    expect(await nft.getPermissionEpoch(SPARK_BASE)).to.equal(0n);
    await (await nft.connect(alice).transferFrom(alice.address, bob.address, 1n)).wait();
    expect(await nft.ownerOf(1n)).to.equal(bob.address);
    expect(await nft.getPermissionEpoch(1n)).to.equal(1n);
  });

  it("Spark keeps normal PATH movement entitlement and named metadata", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, issuer, alice] = await ethers.getSigners();
    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 1)).wait();
    await (await nft.grantRole(roles.RESERVED_ROLE, issuer.address)).wait();
    await (await allowSpark(nft, issuer, alice.address, "Alice")).wait();
    await (await claimSpark(nft, alice, "Alice")).wait();
    await (await consumeViaMover(mover, alice, nft, SPARK_BASE, movements.THOUGHT, alice)).wait();

    expect(await nft.getStage(SPARK_BASE)).to.equal(1n);
    expect(decodeMetadata(await nft.tokenURI(SPARK_BASE)).name).to.equal("PATH Spark #1: Alice");
  });

  it("allowSparker rejects expiry overflow for oversized deployment duration", async function () {
    const UINT64_MAX = (1n << 64n) - 1n;
    const { nft, roles } = await deployPathNftEnv(ethers, { sparkClaimDurationSec: UINT64_MAX });
    const [, issuer, alice] = await ethers.getSigners();

    await (await nft.grantRole(roles.RESERVED_ROLE, issuer.address)).wait();
    await expect(allowSpark(nft, issuer, alice.address, "Alice"))
      .to.be.revertedWithCustomError(nft, "SparkAllowanceOverflow");
  });

  it("self-claimed Spark mint stays available after public minter freeze", async function () {
    const { deployer, nft, roles } = await deployPathNftEnv(ethers);
    const [, issuer, alice] = await ethers.getSigners();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.grantRole(roles.RESERVED_ROLE, issuer.address)).wait();
    await (await allowSpark(nft, issuer, alice.address, "Alice")).wait();
    await (await claimSpark(nft, alice, "Alice", "0x1234")).wait();

    expect(await nft.ownerOf(SPARK_BASE)).to.equal(alice.address);
    expect(await nft.isSparker(SPARK_BASE)).to.equal(true);
  });

  it("freezePublicMinter makes the selected minter exclusive and freezes MINTER_ROLE admin", async function () {
    const { deployer, nft, roles } = await deployPathNftEnv(ethers);
    const [, alice, bob, carol] = await ethers.getSigners();

    await expectAnyRevert(nft.connect(alice).freezePublicMinter(alice.address));
    await expect(nft.freezePublicMinter(ethers.ZeroAddress))
      .to.be.revertedWithCustomError(nft, "ZeroPublicMinter");
    await expect(nft.freezePublicMinter(alice.address))
      .to.be.revertedWithCustomError(nft, "MissingMinterRole");

    await (await nft.grantRole(roles.MINTER_ROLE, deployer.address)).wait();
    await (await nft.grantRole(roles.MINTER_ROLE, bob.address)).wait();
    await (await nft.freezePublicMinter(deployer.address)).wait();

    expect(await nft.publicMinter()).to.equal(deployer.address);
    expect(await nft.publicMinterFrozen()).to.equal(true);
    expect(await nft.getRoleAdmin(roles.MINTER_ROLE)).to.equal(roles.FROZEN_MINTER_ADMIN_ROLE);
    expect(await nft.hasRole(roles.FROZEN_MINTER_ADMIN_ROLE, deployer.address)).to.equal(false);

    await expect(nft.freezePublicMinter(bob.address))
      .to.be.revertedWithCustomError(nft, "PublicMinterAlreadyFrozen");
    await expect(nft.connect(bob).safeMint(bob.address, 3n, "0x"))
      .to.be.revertedWithCustomError(nft, "NotPublicMinter");
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
    await expect(nft.setMovementConfig(movements.DREAM, bob.address, 1))
      .to.be.revertedWithCustomError(nft, "BadMovement");
    await expect(nft.setMovementConfig(movements.THOUGHT, ethers.ZeroAddress, 1))
      .to.be.revertedWithCustomError(nft, "ZeroMinter");
    await expect(nft.setMovementConfig(movements.THOUGHT, bob.address, 0))
      .to.be.revertedWithCustomError(nft, "ZeroQuota");

    await expect(nft.setMovementConfig(movements.THOUGHT, bob.address, 2))
      .to.emit(nft, "BatchMetadataUpdate")
      .withArgs(0n, ethers.MaxUint256);
    expect(await nft.getAuthorizedMinter(movements.THOUGHT)).to.equal(bob.address);
    expect(await nft.getMovementQuota(movements.THOUGHT)).to.equal(2n);
  });

  it("freezeMovementConfig validates and explicitly locks configured movement settings", async function () {
    const { nft, movements } = await deployPathNftEnv(ethers);
    const [, alice, bob] = await ethers.getSigners();

    await expectAnyRevert(nft.connect(alice).freezeMovementConfig(movements.THOUGHT));
    await expect(nft.freezeMovementConfig(movements.DREAM))
      .to.be.revertedWithCustomError(nft, "BadMovement");
    await expect(nft.isMovementFrozen(movements.DREAM))
      .to.be.revertedWithCustomError(nft, "BadMovement");
    await expect(nft.freezeMovementConfig(movements.THOUGHT))
      .to.be.revertedWithCustomError(nft, "MovementNotConfigured");

    expect(await nft.isMovementFrozen(movements.THOUGHT)).to.equal(false);
    await (await nft.setMovementConfig(movements.THOUGHT, bob.address, 1)).wait();

    await expect(nft.freezeMovementConfig(movements.THOUGHT))
      .to.emit(nft, "MovementFrozen")
      .withArgs(movements.THOUGHT);

    expect(await nft.isMovementFrozen(movements.THOUGHT)).to.equal(true);
    await expect(nft.setMovementConfig(movements.THOUGHT, alice.address, 2))
      .to.be.revertedWithCustomError(nft, "MovementConfigFrozen");
    await expect(nft.freezeMovementConfig(movements.THOUGHT))
      .to.be.revertedWithCustomError(nft, "MovementConfigFrozen");
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
    expectCanonicalTokenSvg(svg0);
    expect(svg0).to.contain(
      "id='thought-progress' x='0' y='-240' width='0' height='1000'"
    );
    expect(svg0).to.contain(
      "id='will-progress' x='4800' y='-240' width='0' height='1000'"
    );
    expect(svg0).to.contain(
      "id='awa-progress' x='7800' y='-240' width='0' height='1000'"
    );

    await (await consumeViaMover(mover, alice, nft, 5n, movements.THOUGHT, alice)).wait();
    await (await consumeViaMover(mover, alice, nft, 5n, movements.WILL, alice)).wait();

    const m1 = decodeMetadata(await nft.tokenURI(5n));
    expect(m1.stage).to.equal("WILL");
    expect(m1.thought).to.equal("Minted(1/1)");
    expect(m1.will).to.equal("Minted(1/4)");

    const willTrait1 = m1.attributes.find((x) => x.trait_type === "WILL");
    expect(willTrait1.value).to.equal("Minted(1/4)");
    expectCanonicalTokenSvg(m1.image_data);
    expect(m1.image_data).to.contain(
      "id='thought-progress' x='0' y='-240' width='4200' height='1000'"
    );
    expect(m1.image_data).to.contain(
      "id='will-progress' x='4800' y='-240' width='600' height='1000'"
    );
    expect(m1.image_data).to.contain(
      "id='awa-progress' x='7800' y='-240' width='0' height='1000'"
    );
  });

  it("token image clips each movement word proportionally to quota progress", async function () {
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
    expectCanonicalTokenSvg(thoughtInProgress.image_data);
    expect(thoughtInProgress.image_data).to.contain(
      "id='thought-progress' x='0' y='-240' width='2800' height='1000'"
    );
    expect(thoughtInProgress.image_data).to.contain(
      "id='will-progress' x='4800' y='-240' width='0' height='1000'"
    );
    expect(thoughtInProgress.image_data).to.contain(
      "id='awa-progress' x='7800' y='-240' width='0' height='1000'"
    );

    await (await consumeViaMover(mover, alice, nft, 6n, movements.THOUGHT, alice)).wait();
    await (await consumeViaMover(mover, alice, nft, 6n, movements.WILL, alice)).wait();
    await (await consumeViaMover(mover, alice, nft, 6n, movements.WILL, alice)).wait();
    await (await consumeViaMover(mover, alice, nft, 6n, movements.AWA, alice)).wait();

    const awaInProgress = decodeMetadata(await nft.tokenURI(6n));
    expect(awaInProgress.stage).to.equal("AWA");
    expect(awaInProgress.thought).to.equal("Minted(3/3)");
    expect(awaInProgress.will).to.equal("Minted(2/2)");
    expect(awaInProgress.awa).to.equal("Minted(1/2)");
    expectCanonicalTokenSvg(awaInProgress.image_data);
    expect(awaInProgress.image_data).to.contain(
      "id='thought-progress' x='0' y='-240' width='4200' height='1000'"
    );
    expect(awaInProgress.image_data).to.contain(
      "id='will-progress' x='4800' y='-240' width='2400' height='1000'"
    );
    expect(awaInProgress.image_data).to.contain(
      "id='awa-progress' x='7800' y='-240' width='900' height='1000'"
    );
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
    expectCanonicalTokenSvg(metadata.image_data);
    expect(metadata.image_data).to.contain("<rect width='600' height='600' fill='#000000'/>");
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
    ).to.be.revertedWithCustomError(nft, "UnauthorizedMovementMinter");

    await expect(
      mover.connect(alice).consume(await nft.getAddress(), 21n, movements.DREAM, alice.address, 2n ** 255n, "0x")
    ).to.be.revertedWithCustomError(nft, "BadMovement");
  });

  it("consumeUnit rejects nonexistent token ids", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 1)).wait();

    await expect(
      mover
        .connect(alice)
        .consume(await nft.getAddress(), 999n, movements.THOUGHT, alice.address, 2n ** 255n, "0x")
    ).to.be.revertedWith("ERC721: invalid token ID");
    await expect(nft.getPermissionEpoch(999n)).to.be.revertedWith("ERC721: invalid token ID");
  });

  it("consumeUnit enforces signed authorization and current-owner checks", async function () {
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
    ).to.be.revertedWithCustomError(nft, "NotOwner");

    const badSignerAuth = await signConsumeAuthorization(
      nft,
      carol,
      alice.address,
      executor,
      22n,
      movements.THOUGHT
    );
    await expect(
      mover
        .connect(bob)
        .consume(await nft.getAddress(), 22n, movements.THOUGHT, alice.address, badSignerAuth.deadline, badSignerAuth.signature)
    ).to.be.revertedWithCustomError(nft, "BadConsumeAuthorization");

    const wrongExecutorAuth = await signConsumeAuthorization(
      nft,
      alice,
      alice.address,
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
          alice.address,
          wrongExecutorAuth.deadline,
          wrongExecutorAuth.signature
        )
    ).to.be.revertedWithCustomError(nft, "BadConsumeAuthorization");

    const expiringAuth = await signConsumeAuthorization(
      nft,
      alice,
      alice.address,
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
        .consume(await nft.getAddress(), 22n, movements.THOUGHT, alice.address, expiringAuth.deadline, expiringAuth.signature)
    ).to.be.revertedWithCustomError(nft, "ConsumeAuthorizationExpired");

    await (await nft.connect(alice).approve(bob.address, 22n)).wait();
    await expect(
      consumeViaMover(mover, bob, nft, 22n, movements.THOUGHT, bob)
    ).to.be.revertedWithCustomError(nft, "NotOwner");

    await (await consumeViaMover(mover, bob, nft, 22n, movements.THOUGHT, alice)).wait();

    expect(await nft.getStage(22n)).to.equal(1n);
    expect(await nft.getStageMinted(22n)).to.equal(0n);
  });

  it("consumeUnit denies semantic rights to setApprovalForAll operators", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice, bob] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 1)).wait();
    await (await nft.safeMint(alice.address, 23n, "0x")).wait();

    await (await nft.connect(alice).setApprovalForAll(bob.address, true)).wait();
    await expect(
      consumeViaMover(mover, bob, nft, 23n, movements.THOUGHT, bob)
    ).to.be.revertedWithCustomError(nft, "NotOwner");

    expect(await nft.getStage(23n)).to.equal(0n);
    expect(await nft.getStageMinted(23n)).to.equal(0n);
    expect(await nft.getConsumeNonce(bob.address)).to.equal(0n);
  });

  it("secondary transfer advances the epoch and preserves remaining entitlement", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice, bob, carol] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 1)).wait();
    await (await nft.setMovementConfig(movements.WILL, await mover.getAddress(), 3)).wait();
    await (await nft.setMovementConfig(movements.AWA, await mover.getAddress(), 1)).wait();
    await (await nft.safeMint(alice.address, 26n, "0x")).wait();

    await (await consumeViaMover(mover, alice, nft, 26n, movements.THOUGHT, alice)).wait();
    await (await consumeViaMover(mover, alice, nft, 26n, movements.WILL, alice)).wait();
    expect(await nft.getStage(26n)).to.equal(1n);
    expect(await nft.getStageMinted(26n)).to.equal(1n);
    expect(await nft.getPermissionEpoch(26n)).to.equal(0n);

    await (await nft.connect(alice).approve(bob.address, 26n)).wait();
    await expect(nft.connect(bob).transferFrom(alice.address, carol.address, 26n))
      .to.emit(nft, "PermissionEpochAdvanced")
      .withArgs(26n, 1n, alice.address, carol.address);

    expect(await nft.ownerOf(26n)).to.equal(carol.address);
    expect(await nft.getPermissionEpoch(26n)).to.equal(1n);
    expect(await nft.getStage(26n)).to.equal(1n);
    expect(await nft.getStageMinted(26n)).to.equal(1n);

    const transferredMetadata = decodeMetadata(await nft.tokenURI(26n));
    expect(transferredMetadata.thought).to.equal("Minted(1/1)");
    expect(transferredMetadata.will).to.equal("Minted(1/3)");
    expect(transferredMetadata.awa).to.equal("Minted(0/1)");

    await expect(
      consumeViaMover(mover, alice, nft, 26n, movements.WILL, alice)
    ).to.be.revertedWithCustomError(nft, "NotOwner");
    await (await consumeViaMover(mover, bob, nft, 26n, movements.WILL, carol)).wait();

    expect(await nft.getStage(26n)).to.equal(1n);
    expect(await nft.getStageMinted(26n)).to.equal(2n);
  });

  it("permission epoch prevents stale signatures from reviving after a transfer round trip", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice, bob] = await ethers.getSigners();

    const Mover = await ethers.getContractFactory("MockMovementMinter", deployer);
    const mover = await Mover.deploy();
    await mover.waitForDeployment();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.setMovementConfig(movements.THOUGHT, await mover.getAddress(), 2)).wait();
    await (await nft.safeMint(alice.address, 27n, "0x")).wait();

    const executor = await mover.getAddress();
    const stale = await signConsumeAuthorization(
      nft,
      alice,
      alice.address,
      executor,
      27n,
      movements.THOUGHT
    );
    expect(stale.permissionEpoch).to.equal(0n);

    await (await nft.connect(alice).transferFrom(alice.address, bob.address, 27n)).wait();
    expect(await nft.getPermissionEpoch(27n)).to.equal(1n);
    await expect(
      mover
        .connect(alice)
        .consume(await nft.getAddress(), 27n, movements.THOUGHT, alice.address, stale.deadline, stale.signature)
    ).to.be.revertedWithCustomError(nft, "NotOwner");

    await (await nft.connect(bob).transferFrom(bob.address, alice.address, 27n)).wait();
    expect(await nft.getPermissionEpoch(27n)).to.equal(2n);
    await expect(
      mover
        .connect(alice)
        .consume(await nft.getAddress(), 27n, movements.THOUGHT, alice.address, stale.deadline, stale.signature)
    ).to.be.revertedWithCustomError(nft, "BadConsumeAuthorization");

    expect(await nft.getConsumeNonce(alice.address)).to.equal(0n);
    await (await consumeViaMover(mover, bob, nft, 27n, movements.THOUGHT, alice)).wait();
    expect(await nft.getStageMinted(27n)).to.equal(1n);
    expect(await nft.getConsumeNonce(alice.address)).to.equal(1n);
  });

  it("self-transfer advances the permission epoch without changing ownership or progress", async function () {
    const { deployer, nft, roles } = await deployPathNftEnv(ethers);
    const [, alice] = await ethers.getSigners();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.safeMint(alice.address, 28n, "0x")).wait();

    await expect(nft.connect(alice).transferFrom(alice.address, alice.address, 28n))
      .to.emit(nft, "PermissionEpochAdvanced")
      .withArgs(28n, 1n, alice.address, alice.address);

    expect(await nft.ownerOf(28n)).to.equal(alice.address);
    expect(await nft.getPermissionEpoch(28n)).to.equal(1n);
    expect(await nft.getStage(28n)).to.equal(0n);
    expect(await nft.getStageMinted(28n)).to.equal(0n);
  });

  it("PATH transfer does not move already minted movement tokens", async function () {
    const { deployer, nft, roles, movements } = await deployPathNftEnv(ethers);
    const [, alice, bob] = await ethers.getSigners();

    await grantAndFreezePublicMinter(nft, roles, deployer.address);
    await (await nft.safeMint(alice.address, 29n, "0x")).wait();

    const Movement = await ethers.getContractFactory("MockMovementToken", deployer);
    const movementToken = await Movement.deploy(await nft.getAddress(), movements.THOUGHT);
    await movementToken.waitForDeployment();
    await (await nft.setMovementConfig(movements.THOUGHT, await movementToken.getAddress(), 2)).wait();

    const aliceAuth = await signConsumeAuthorization(
      nft,
      alice,
      alice.address,
      await movementToken.getAddress(),
      29n,
      movements.THOUGHT
    );
    await (
      await movementToken.connect(alice).mintWithPath(29n, aliceAuth.deadline, aliceAuth.signature)
    ).wait();

    expect(await movementToken.ownerOf(0n)).to.equal(alice.address);
    expect(await nft.getStageMinted(29n)).to.equal(1n);

    await (await nft.connect(alice).transferFrom(alice.address, bob.address, 29n)).wait();
    expect(await nft.ownerOf(29n)).to.equal(bob.address);
    expect(await movementToken.ownerOf(0n)).to.equal(alice.address);
    expect(await nft.getStageMinted(29n)).to.equal(1n);

    const bobAuth = await signConsumeAuthorization(
      nft,
      bob,
      bob.address,
      await movementToken.getAddress(),
      29n,
      movements.THOUGHT
    );
    await (
      await movementToken.connect(bob).mintWithPath(29n, bobAuth.deadline, bobAuth.signature)
    ).wait();

    expect(await movementToken.ownerOf(0n)).to.equal(alice.address);
    expect(await movementToken.ownerOf(1n)).to.equal(bob.address);
    expect(await nft.getStage(29n)).to.equal(1n);
    expect(await nft.getStageMinted(29n)).to.equal(0n);
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
    ).to.be.revertedWithCustomError(nft, "BadConsumeAuthorization");
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
    ).to.be.revertedWithCustomError(nft, "BadMovementOrder");

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
    ).to.be.revertedWithCustomError(nft, "BadStage");
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

    await expect(nft.setMovementConfig(movements.THOUGHT, bob.address, 2))
      .to.be.revertedWithCustomError(nft, "MovementConfigFrozen");

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
