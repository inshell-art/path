import fs from "node:fs/promises";
import path from "node:path";
import hre from "hardhat";
import {
  createProtocolReceiptEnvelope,
  parseJsonStrict,
  runtimeCodeHash,
  sha256Bytes,
  sha256Json,
  validatePhaseAReceipt,
  validatePhaseBParams
} from "./lib/path-campaign.mjs";

async function deploymentEvidence(ethers, contract) {
  const tx = contract.deploymentTransaction();
  const receipt = await tx?.wait();
  if (!tx || !receipt) throw new Error("Deployment evidence unavailable");
  const address = await contract.getAddress();
  return {
    address,
    deploymentTx: tx.hash,
    blockNumber: receipt.blockNumber.toString(),
    runtimeBytecodeHash: await runtimeCodeHash(ethers, address)
  };
}

async function main() {
  const phaseAFile = process.env.PATH_PHASE_A_RECEIPT_FILE;
  const outDir = process.env.PATH_CAMPAIGN_DEVNET_OUT_DIR;
  if (!phaseAFile || !outDir) {
    throw new Error("Requires PATH_PHASE_A_RECEIPT_FILE and PATH_CAMPAIGN_DEVNET_OUT_DIR");
  }
  const phaseA = validatePhaseAReceipt(
    parseJsonStrict(
      await fs.readFile(path.resolve(phaseAFile), "utf8"),
      "PATH Phase A owner payload"
    )
  );

  const conn = await hre.network.connect();
  const { ethers } = conn;
  try {
    const network = await ethers.provider.getNetwork();
    if (network.chainId === 1n || network.chainId === 11155111n) {
      throw new Error("Devnet dependency rehearsal refuses Sepolia and mainnet");
    }
    if (network.chainId !== BigInt(phaseA.chainId)) throw new Error("Phase A chain mismatch");
    const signers = await ethers.getSigners();
    const nft = await ethers.getContractAt("PathNFT", phaseA.pathNft.address);

    const MovementToken = await ethers.getContractFactory("MockMovementToken", signers[0]);
    const thought = await MovementToken.deploy(phaseA.pathNft.address, await nft.MOVEMENT_THOUGHT());
    await thought.waitForDeployment();
    const thoughtEvidence = await deploymentEvidence(ethers, thought);

    const MovementMinter = await ethers.getContractFactory("MockMovementMinter", signers[0]);
    const will = await MovementMinter.deploy();
    await will.waitForDeployment();
    const awa = await MovementMinter.deploy();
    await awa.waitForDeployment();

    const thoughtRelease = {
      artifactId: "thought-v2-devnet-rehearsal-only",
      manifestSha256: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      publicationCommit: "4fbbd708dce7b35fe6c219cb130be794162980d4",
      sourceTag: "thought-v2-devnet-rehearsal-only"
    };
    const phaseAEnvelope = createProtocolReceiptEnvelope({
      phaseId: "path-a",
      campaignId: phaseA.campaignId,
      environment: phaseA.environment,
      chainId: phaseA.chainId,
      payload: phaseA
    });
    const phaseARaw = `${JSON.stringify(phaseAEnvelope, null, 2)}\n`;
    const phaseAEnvelopeSha256 = sha256Bytes(Buffer.from(phaseARaw));
    const dummyContracts = {
      thoughtSpecRegistry: signers[3].address,
      protocolRegistry: signers[4].address,
      glyphDataPointer: signers[5].address,
      thoughtRenderer: signers[6].address,
      creationAttestationVerifier: signers[7].address
    };
    const thoughtReceipt = {
      schema: "inshell.thought.deployment.receipt.v1",
      campaignId: phaseA.campaignId,
      phase: "thought",
      environment: phaseA.environment,
      chainId: Number(phaseA.chainId),
      status: "complete",
      consumedPathPhaseAReceiptSha256: phaseAEnvelopeSha256,
      consumedPathPhaseA: {
        envelopeSha256: phaseAEnvelopeSha256,
        payloadSha256: phaseAEnvelope.protocol_payload.sha256
      },
      pathNft: phaseA.pathNft.address,
      thoughtRelease,
      bundleDigest: `0x${"d".repeat(64)}`,
      contracts: {
        ...dummyContracts,
        thoughtNft: thoughtEvidence.address
      },
      deployments: [
        ...Object.entries(dummyContracts).map(([name, address], index) => ({
          name,
          address,
          transaction: `0x${String(index + 1).repeat(64)}`,
          block: Number(thoughtEvidence.blockNumber) + index + 1,
          creationBytecodeHash: `0x${"a".repeat(64)}`,
          runtimeBytecodeHash: `0x${"b".repeat(64)}`
        })),
        {
          name: "thoughtNft",
          address: thoughtEvidence.address,
          transaction: thoughtEvidence.deploymentTx,
          block: Number(thoughtEvidence.blockNumber),
          creationBytecodeHash: `0x${"a".repeat(64)}`,
          runtimeBytecodeHash: thoughtEvidence.runtimeBytecodeHash
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
      approvedPathIntegration: { movement: "THOUGHT", quota: 1, thoughtNft: thoughtEvidence.address },
      pathMutationPerformed: false,
      pathMutationOwner: "PATH_PHASE_B",
      verification: { overall: "PASS", registry: "PASS", immutableDependencies: "PASS", profiles: "PASS" }
    };
    const thoughtEnvelope = createProtocolReceiptEnvelope({
      phaseId: "thought",
      campaignId: phaseA.campaignId,
      environment: phaseA.environment,
      chainId: phaseA.chainId,
      inputReceiptSha256: phaseAEnvelopeSha256,
      payload: thoughtReceipt
    });
    const thoughtRaw = `${JSON.stringify(thoughtEnvelope, null, 2)}\n`;

    const latest = await ethers.provider.getBlock("latest");
    if (!latest) throw new Error("Latest block unavailable");
    const authorizedAt = BigInt(latest.timestamp);
    const authorizedOpenTime = authorizedAt + 7200n;
    const authorization = {
      campaignId: phaseA.campaignId,
      environment: phaseA.environment,
      authorizedOpenTime: authorizedOpenTime.toString(),
      minimumLeadTimeSec: "3600",
      authorizedAt: authorizedAt.toString(),
      expiresAt: (authorizedOpenTime + 3600n).toString(),
      authorizerRef: "DEVNET_OPEN_TIME_OPERATOR_A",
      authorizationId: `${phaseA.campaignId}-open-time`
    };
    const params = {
      campaignId: phaseA.campaignId,
      environment: phaseA.environment,
      expectedChainId: phaseA.chainId,
      releaseMatrix: { path: phaseA.pathRelease, thought: thoughtRelease },
      pathPhaseA: {
        receiptSha256: phaseAEnvelopeSha256,
        receiptRaw: phaseARaw,
        receipt: phaseAEnvelope
      },
      thoughtDeployment: {
        receiptSha256: sha256Bytes(Buffer.from(thoughtRaw)),
        receiptRaw: thoughtRaw,
        receipt: thoughtEnvelope
      },
      remainingMovements: {
        WILL: {
          minter: await will.getAddress(),
          runtimeBytecodeHash: await runtimeCodeHash(ethers, await will.getAddress()),
          quota: "10"
        },
        AWA: {
          minter: await awa.getAddress(),
          runtimeBytecodeHash: await runtimeCodeHash(ethers, await awa.getAddress()),
          quota: "1"
        }
      },
      openTimeAuthorization: {
        environment: authorization.environment,
        authorizedOpenTime: authorization.authorizedOpenTime,
        minimumLeadTimeSec: authorization.minimumLeadTimeSec,
        authorizedAt: authorization.authorizedAt,
        expiresAt: authorization.expiresAt,
        authorizerRef: authorization.authorizerRef,
        authorizationId: authorization.authorizationId,
        authorizationDigest: sha256Json(authorization)
      },
      auction: {
        k: "600",
        genesisPrice: "1000",
        genesisFloor: "900",
        pts: "1",
        firstPublicId: "1",
        epochBase: "1",
        paymentToken: ethers.ZeroAddress
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
    validatePhaseBParams(params, { latestBlockTimestamp: latest.timestamp });

    const output = path.resolve(outDir);
    await fs.mkdir(output, { recursive: true });
    await fs.writeFile(
      path.join(output, "path-a-envelope.json"),
      phaseARaw,
      "utf8"
    );
    await fs.writeFile(
      path.join(output, "thought-envelope.json"),
      thoughtRaw,
      "utf8"
    );
    await fs.writeFile(
      path.join(output, "path-phase-b-params.json"),
      `${JSON.stringify(params, null, 2)}\n`,
      "utf8"
    );
    console.log(`[path-campaign-devnet] phaseAEnvelope=${path.join(output, "path-a-envelope.json")}`);
    console.log(`[path-campaign-devnet] thoughtEnvelope=${path.join(output, "thought-envelope.json")}`);
    console.log(`[path-campaign-devnet] phaseBParams=${path.join(output, "path-phase-b-params.json")}`);
  } finally {
    await conn.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
