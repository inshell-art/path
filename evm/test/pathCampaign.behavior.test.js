import { expect } from "chai";
import hre from "hardhat";
import {
  PATH_PHASE_A_KIND,
  PHASE_A_PERMITTED_ACTIONS,
  PHASE_B_CHECKPOINT_ACTIONS,
  ZERO_ADDRESS,
  assertFinalReceiptComplete,
  createProtocolReceiptEnvelope,
  runtimeCodeHash,
  sha256Bytes,
  sha256Json,
  validatePhaseAParams,
  validatePhaseAReceipt,
  validatePhaseBCheckpoint,
  validatePhaseBParams,
  verifyPhaseAOnChain,
  verifyPhaseBCheckpointOnChain,
  verifyThoughtOnChain
} from "../scripts/lib/path-campaign.mjs";

describe("PATH + THOUGHT deployment campaign", function () {
  let conn;
  let ethers;
  let signers;

  const pathRelease = {
    repository: "https://github.com/inshell-art/path.git",
    releaseTag: "v0.5.0",
    gitCommit: "085cfc084b0e568740e0da639e968eb535f7e5c8",
    artifactManifestSha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  };
  const thoughtRelease = {
    artifactId: "thought-v2-test",
    manifestSha256: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    publicationCommit: "4fbbd708dce7b35fe6c219cb130be794162980d4",
    sourceTag: "thought-v2-test"
  };
  const jsonRaw = (value) => `${JSON.stringify(value, null, 2)}\n`;
  const envelope = (phaseId, payload, inputReceiptSha256 = "") => {
    const value = createProtocolReceiptEnvelope({
      phaseId,
      campaignId: payload.campaignId,
      environment: payload.environment,
      chainId: payload.chainId,
      inputReceiptSha256,
      payload
    });
    const receiptRaw = jsonRaw(value);
    return { receiptSha256: sha256Bytes(Buffer.from(receiptRaw)), receiptRaw, receipt: value };
  };

  beforeEach(async function () {
    conn = await hre.network.connect();
    ethers = conn.ethers;
    signers = await ethers.getSigners();
  });

  afterEach(async function () {
    await conn.close();
  });

  async function deployPath(deployer = signers[0]) {
    const Factory = await ethers.getContractFactory("PathNFT", deployer);
    const nft = await Factory.deploy(deployer.address, "PATH", "PATH", "", 99, 604800);
    await nft.waitForDeployment();
    return nft;
  }

  async function phaseAReceipt(nft, deployer = signers[0]) {
    const deployTx = nft.deploymentTransaction();
    const receipt = await deployTx.wait();
    const chainId = (await ethers.provider.getNetwork()).chainId;
    return {
      receiptVersion: "1",
      kind: PATH_PHASE_A_KIND,
      status: "phase_a_complete",
      campaignId: "campaign-test-1",
      environment: "internal-sepolia",
      chainId: chainId.toString(),
      pathRelease,
      sourceBundleDigest: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      deployer: deployer.address,
      pathNft: {
        address: await nft.getAddress(),
        deploymentTx: deployTx.hash,
        blockNumber: receipt.blockNumber.toString(),
        runtimeBytecodeHash: await runtimeCodeHash(ethers, await nft.getAddress())
      },
      retainedAuthority: {
        holder: deployer.address,
        signerRef: "DEVNET_DEPLOY_SW_A",
        role: "DEFAULT_ADMIN_ROLE",
        permittedRemainingActions: [...PHASE_A_PERMITTED_ACTIONS],
        handoffComplete: false
      },
      movementStates: {
        THOUGHT: { minter: ZERO_ADDRESS, quota: "0", frozen: false },
        WILL: { minter: ZERO_ADDRESS, quota: "0", frozen: false },
        AWA: { minter: ZERO_ADDRESS, quota: "0", frozen: false }
      },
      publicExposure: {
        pathPulseAdapter: null,
        pulseAuction: null,
        openTime: null,
        publicMinter: ZERO_ADDRESS,
        publicMinterFrozen: false,
        publicMintEnabled: false
      },
      observedAtBlock: receipt.blockNumber.toString()
    };
  }

  async function deployMovement(pathNft, movement, deployer = signers[0]) {
    const Factory = await ethers.getContractFactory("MockMovementToken", deployer);
    const token = await Factory.deploy(pathNft, movement);
    await token.waitForDeployment();
    return token;
  }

  async function thoughtReceipt(phaseA, thoughtNft) {
    const tx = thoughtNft.deploymentTransaction();
    const receipt = await tx.wait();
    const phaseAEnvelope = envelope("path-a", phaseA);
    const otherContracts = {
      thoughtSpecRegistry: signers[3].address,
      protocolRegistry: signers[4].address,
      glyphDataPointer: signers[5].address,
      thoughtRenderer: signers[6].address,
      creationAttestationVerifier: signers[7].address
    };
    const contractEntries = Object.entries(otherContracts);
    return {
      schema: "inshell.thought.deployment.receipt.v1",
      campaignId: phaseA.campaignId,
      phase: "thought",
      environment: phaseA.environment,
      chainId: Number(phaseA.chainId),
      status: "complete",
      consumedPathPhaseAReceiptSha256: phaseAEnvelope.receiptSha256,
      consumedPathPhaseA: {
        envelopeSha256: phaseAEnvelope.receiptSha256,
        payloadSha256: phaseAEnvelope.receipt.protocol_payload.sha256
      },
      pathNft: phaseA.pathNft.address,
      thoughtRelease,
      bundleDigest: `0x${"d".repeat(64)}`,
      contracts: {
        ...otherContracts,
        thoughtNft: await thoughtNft.getAddress()
      },
      deployments: [
        ...contractEntries.map(([name, address], index) => ({
          name,
          address,
          transaction: `0x${String(index + 1).repeat(64)}`,
          block: receipt.blockNumber + index + 1,
          creationBytecodeHash: `0x${"a".repeat(64)}`,
          runtimeBytecodeHash: `0x${"b".repeat(64)}`
        })),
        {
          name: "thoughtNft",
          address: await thoughtNft.getAddress(),
          transaction: tx.hash,
          block: receipt.blockNumber,
          creationBytecodeHash: `0x${"a".repeat(64)}`,
          runtimeBytecodeHash: await runtimeCodeHash(ethers, await thoughtNft.getAddress())
        }
      ],
      registry: {
        thoughtSpecId: `0x${"1".repeat(64)}`,
        thoughtSpecHash: `0x${"2".repeat(64)}`,
        protocolReleaseId: `0x${"3".repeat(64)}`,
        protocolManifestHash: `0x${"4".repeat(64)}`,
        exactBytesVerified: true
      },
      compatibility: {
        pathNftImmutable: phaseA.pathNft.address,
        rendererIdHash: `0x${"5".repeat(64)}`,
        metadataProfileIdHash: `0x${"6".repeat(64)}`,
        workProfileIdHash: `0x${"7".repeat(64)}`,
        contextProfileIdHash: `0x${"8".repeat(64)}`,
        creationAttestationProfileId: `0x${"9".repeat(64)}`
      },
      authorities: {
        registryOwner: signers[4].address,
        protocolRegistryOwner: signers[4].address,
        attestationVerifierOwner: signers[4].address,
        attestationAuthority: signers[5].address,
        attestationAuthorityEpoch: 1
      },
      approvedPathIntegration: {
        movement: "THOUGHT", quota: 1, thoughtNft: await thoughtNft.getAddress()
      },
      pathMutationPerformed: false,
      pathMutationOwner: "PATH_PHASE_B",
      verification: { overall: "PASS", registry: "PASS", immutableDependencies: "PASS", profiles: "PASS" }
    };
  }

  async function phaseBParams(phaseA, thought, willMinter, awaMinter) {
    const latest = await ethers.provider.getBlock("latest");
    const authorizedAt = BigInt(latest.timestamp);
    const openTime = authorizedAt + 7200n;
    const expiresAt = openTime + 3600n;
    const authorizationBase = {
      campaignId: phaseA.campaignId,
      environment: phaseA.environment,
      authorizedOpenTime: openTime.toString(),
      minimumLeadTimeSec: "3600",
      authorizedAt: authorizedAt.toString(),
      expiresAt: expiresAt.toString(),
      authorizerRef: "DEVNET_OPEN_TIME_OPERATOR_A",
      authorizationId: "devnet-open-time-test-1"
    };
    return {
      campaignId: phaseA.campaignId,
      environment: phaseA.environment,
      expectedChainId: phaseA.chainId,
      releaseMatrix: { path: pathRelease, thought: thoughtRelease },
      pathPhaseA: envelope("path-a", phaseA),
      thoughtDeployment: envelope("thought", thought, envelope("path-a", phaseA).receiptSha256),
      remainingMovements: {
        WILL: {
          minter: await willMinter.getAddress(),
          runtimeBytecodeHash: await runtimeCodeHash(ethers, await willMinter.getAddress()),
          quota: "10"
        },
        AWA: {
          minter: await awaMinter.getAddress(),
          runtimeBytecodeHash: await runtimeCodeHash(ethers, await awaMinter.getAddress()),
          quota: "1"
        }
      },
      openTimeAuthorization: {
        ...authorizationBase,
        authorizationDigest: sha256Json(authorizationBase)
      },
      auction: {
        k: "600",
        genesisPrice: "1000",
        genesisFloor: "900",
        pts: "1",
        firstPublicId: "1",
        epochBase: "1",
        paymentToken: ZERO_ADDRESS
      },
      treasury: signers[4].address,
      treasurySignerRef: "DEVNET_TREASURY_A",
      finalAuthority: {
        admin: signers[1].address,
        adminSignerRef: "DEVNET_ADMIN_A",
        treasury: signers[4].address,
        treasurySignerRef: "DEVNET_TREASURY_A",
        sparkIssuer: signers[2].address,
        sparkIssuerSignerRef: "DEVNET_SPARK_ISSUER_A"
      }
    };
  }

  it("supports a bounded Phase A interval with all movements and public mint unset", async function () {
    const nft = await deployPath();
    const receipt = await phaseAReceipt(nft);

    validatePhaseAReceipt(receipt);
    await verifyPhaseAOnChain(ethers, receipt, signers[0].address);
    expect(await nft.getAuthorizedMinter(await nft.MOVEMENT_THOUGHT())).to.equal(ZERO_ADDRESS);
    expect(await nft.getMovementQuota(await nft.MOVEMENT_THOUGHT())).to.equal(0n);
    expect(await nft.isMovementFrozen(await nft.MOVEMENT_THOUGHT())).to.equal(false);
    expect(receipt.publicExposure.openTime).to.equal(null);
  });

  it("rejects openTime and auction fields from Phase A inputs", async function () {
    const params = {
      campaignId: "campaign-test-1",
      environment: "devnet",
      expectedChainId: "31337",
      pathRelease,
      name: "PATH",
      symbol: "PATH",
      baseUri: "",
      reservedCap: "99",
      sparkClaimDurationSec: "604800",
      retainedAuthority: { address: signers[0].address, signerRef: "DEVNET_DEPLOY_SW_A" },
      openTime: "2000000000"
    };
    expect(() => validatePhaseAParams(params)).to.throw("Phase A must not include openTime");
  });

  it("refuses to freeze a ThoughtNFT that binds a different PathNFT", async function () {
    const pathA = await deployPath();
    const pathB = await deployPath(signers[3]);
    const phaseA = await phaseAReceipt(pathA);
    const wrongThought = await deployMovement(
      await pathB.getAddress(),
      await pathA.MOVEMENT_THOUGHT()
    );
    const thought = await thoughtReceipt(phaseA, wrongThought);
    const will = await deployMovement(await pathA.getAddress(), await pathA.MOVEMENT_WILL());
    const awa = await deployMovement(await pathA.getAddress(), await pathA.MOVEMENT_AWA());
    const params = await phaseBParams(phaseA, thought, will, awa);

    validatePhaseBParams(params);
    await expect(verifyThoughtOnChain(ethers, params)).to.be.rejectedWith(
      "ThoughtNFT binds a different PathNFT"
    );
    expect(await pathA.getAuthorizedMinter(await pathA.MOVEMENT_THOUGHT())).to.equal(ZERO_ADDRESS);
    expect(await pathA.isMovementFrozen(await pathA.MOVEMENT_THOUGHT())).to.equal(false);
  });

  it("accepts only exact linked receipts and a still-safe authorized openTime", async function () {
    const nft = await deployPath();
    const phaseA = await phaseAReceipt(nft);
    const thoughtToken = await deployMovement(await nft.getAddress(), await nft.MOVEMENT_THOUGHT());
    const will = await deployMovement(await nft.getAddress(), await nft.MOVEMENT_WILL());
    const awa = await deployMovement(await nft.getAddress(), await nft.MOVEMENT_AWA());
    const thought = await thoughtReceipt(phaseA, thoughtToken);
    const params = await phaseBParams(phaseA, thought, will, awa);
    const latest = await ethers.provider.getBlock("latest");

    expect(() => validatePhaseBParams(params, { latestBlockTimestamp: latest.timestamp })).not.to.throw();

    const tampered = structuredClone(params);
    tampered.pathPhaseA.receipt.protocol_payload.payload.observedAtBlock = "999999";
    expect(() => validatePhaseBParams(tampered)).to.throw("differs from exact receiptRaw bytes");

    const unsafe = structuredClone(params);
    unsafe.openTimeAuthorization.authorizedOpenTime = (BigInt(latest.timestamp) + 60n).toString();
    unsafe.openTimeAuthorization.expiresAt = (BigInt(latest.timestamp) + 7200n).toString();
    const auth = unsafe.openTimeAuthorization;
    auth.authorizationDigest = sha256Json({
      campaignId: unsafe.campaignId,
      environment: auth.environment,
      authorizedOpenTime: auth.authorizedOpenTime,
      minimumLeadTimeSec: auth.minimumLeadTimeSec,
      authorizedAt: auth.authorizedAt,
      expiresAt: auth.expiresAt,
      authorizerRef: auth.authorizerRef,
      authorizationId: auth.authorizationId
    });
    expect(() => validatePhaseBParams(unsafe, { latestBlockTimestamp: latest.timestamp }))
      .to.throw("minimum lead time");
  });

  it("never treats a Phase A or partial Phase B receipt as complete", async function () {
    const nft = await deployPath();
    const phaseA = await phaseAReceipt(nft);
    expect(() => assertFinalReceiptComplete(phaseA)).to.throw(
      "partial deployment cannot be presented as campaign complete"
    );

    const partial = {
      receiptVersion: "1",
      kind: "path_campaign_phase_b_final_receipt",
      status: "blocked"
    };
    expect(() => assertFinalReceiptComplete(partial)).to.throw(
      "partial deployment cannot be presented as campaign complete"
    );
  });

  it("rejects wrong chains, unexpected retained authority, and forged authorization digests", async function () {
    const nft = await deployPath();
    const phaseA = await phaseAReceipt(nft);
    const thoughtToken = await deployMovement(await nft.getAddress(), await nft.MOVEMENT_THOUGHT());
    const will = await deployMovement(await nft.getAddress(), await nft.MOVEMENT_WILL());
    const awa = await deployMovement(await nft.getAddress(), await nft.MOVEMENT_AWA());
    const thought = await thoughtReceipt(phaseA, thoughtToken);
    const params = await phaseBParams(phaseA, thought, will, awa);

    const wrongChain = structuredClone(params);
    wrongChain.expectedChainId = "1";
    expect(() => validatePhaseBParams(wrongChain)).to.throw("protocol envelope chain mismatch");

    const retainedAdmin = structuredClone(params);
    retainedAdmin.finalAuthority.admin = phaseA.retainedAuthority.holder;
    expect(() => validatePhaseBParams(retainedAdmin)).to.throw("final admin must differ");

    const forgedOpenTime = structuredClone(params);
    forgedOpenTime.openTimeAuthorization.authorizationDigest =
      "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    expect(() => validatePhaseBParams(forgedOpenTime)).to.throw("authorization digest mismatch");
  });

  it("resumes only from an exact Phase B checkpoint and rejects unrecorded state", async function () {
    const nft = await deployPath();
    const phaseA = await phaseAReceipt(nft);
    const thoughtToken = await deployMovement(await nft.getAddress(), await nft.MOVEMENT_THOUGHT());
    const will = await deployMovement(await nft.getAddress(), await nft.MOVEMENT_WILL());
    const awa = await deployMovement(await nft.getAddress(), await nft.MOVEMENT_AWA());
    const thought = await thoughtReceipt(phaseA, thoughtToken);
    const params = await phaseBParams(phaseA, thought, will, awa);

    const setTx = await nft.setMovementConfig(
      await nft.MOVEMENT_THOUGHT(),
      await thoughtToken.getAddress(),
      1
    );
    const setReceipt = await setTx.wait();
    const freezeTx = await nft.freezeMovementConfig(await nft.MOVEMENT_THOUGHT());
    const freezeReceipt = await freezeTx.wait();
    const checkpoint = {
      checkpointVersion: "1",
      kind: "path_campaign_phase_b_checkpoint",
      status: "phase_running",
      campaignId: params.campaignId,
      environment: params.environment,
      chainId: params.expectedChainId,
      paramsSha256: sha256Json(params),
      sourceBundleDigest: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      linkedReceipts: {
        pathPhaseAReceiptSha256: params.pathPhaseA.receiptSha256,
        thoughtDeploymentReceiptSha256: params.thoughtDeployment.receiptSha256
      },
      completedActions: PHASE_B_CHECKPOINT_ACTIONS.slice(0, 2),
      contracts: {},
      transactions: {
        movement: {
          THOUGHT: {
            set: { hash: setTx.hash, blockNumber: setReceipt.blockNumber.toString() },
            freeze: { hash: freezeTx.hash, blockNumber: freezeReceipt.blockNumber.toString() }
          }
        },
        deployment: {},
        wiring: {},
        authority: {}
      }
    };

    expect(() => validatePhaseBCheckpoint(checkpoint, {
      campaignId: params.campaignId,
      paramsSha256: sha256Json(params)
    })).not.to.throw();
    await verifyPhaseBCheckpointOnChain(ethers, params, checkpoint, signers[0].address);

    const forgedEvidence = structuredClone(checkpoint);
    forgedEvidence.transactions.movement.THOUGHT.set = {
      hash: freezeTx.hash,
      blockNumber: freezeReceipt.blockNumber.toString()
    };
    await expect(
      verifyPhaseBCheckpointOnChain(ethers, params, forgedEvidence, signers[0].address)
    ).to.be.rejectedWith("method mismatch");

    await (await nft.setMovementConfig(await nft.MOVEMENT_WILL(), await will.getAddress(), 10)).wait();
    await expect(
      verifyPhaseBCheckpointOnChain(ethers, params, checkpoint, signers[0].address)
    ).to.be.rejectedWith("WILL changed without a Phase B checkpoint");
  });
});
