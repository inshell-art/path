import fs from "node:fs/promises";
import path from "node:path";
import hre from "hardhat";
import {
  PATH_PHASE_A_KIND,
  PHASE_A_PERMITTED_ACTIONS,
  ZERO_ADDRESS,
  assertSha256,
  parseJsonStrict,
  runtimeCodeHash,
  sameAddress,
  sha256Json,
  validatePhaseACheckpoint,
  validatePhaseAParams,
  validatePhaseAReceipt,
  verifyPhaseAConstructorOnChain,
  verifyPhaseAOnChain
} from "./lib/path-campaign.mjs";

async function readJson(file) {
  return parseJsonStrict(await fs.readFile(path.resolve(file), "utf8"), path.resolve(file));
}

async function fileExists(file) {
  try {
    await fs.access(file);
    return true;
  } catch {
    return false;
  }
}

async function writeJsonAtomic(file, value) {
  const resolved = path.resolve(file);
  const temporary = `${resolved}.tmp`;
  await fs.mkdir(path.dirname(resolved), { recursive: true });
  await fs.writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, "utf8");
  await fs.rename(temporary, resolved);
}

async function main() {
  const paramsFile = process.env.DEPLOY_PARAMS_FILE;
  const outFile = process.env.DEPLOY_OUT_FILE;
  const sourceBundleDigest = process.env.PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST;
  if (!paramsFile || !outFile || !sourceBundleDigest) {
    throw new Error(
      "Phase A requires DEPLOY_PARAMS_FILE, DEPLOY_OUT_FILE, and PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST"
    );
  }
  assertSha256(sourceBundleDigest, "PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST");
  const params = validatePhaseAParams(await readJson(paramsFile));
  const paramsSha256 = sha256Json(params);
  const resolvedOutFile = path.resolve(outFile);
  const checkpointFile = path.resolve(
    process.env.PATH_CAMPAIGN_CHECKPOINT_FILE
      ?? path.join(path.dirname(resolvedOutFile), "path-phase-a-checkpoint.json")
  );

  const conn = await hre.network.connect();
  const { ethers } = conn;
  try {
    const [deployer] = await ethers.getSigners();
    const network = await ethers.provider.getNetwork();
    if (network.chainId !== BigInt(params.expectedChainId)) {
      throw new Error(`CHAIN_MISMATCH: expected=${params.expectedChainId} observed=${network.chainId}`);
    }
    if (!sameAddress(deployer.address, params.retainedAuthority.address)) {
      throw new Error(
        `AUTHORITY_MISMATCH: expected=${params.retainedAuthority.address} observed=${deployer.address}`
      );
    }
    const stopAfterDeploy = process.env.PATH_CAMPAIGN_TEST_STOP_AFTER_DEPLOY === "1";
    if (stopAfterDeploy && [1n, 11155111n].includes(network.chainId)) {
      throw new Error("PATH_CAMPAIGN_TEST_STOP_AFTER_DEPLOY is ephemeral-chain-only");
    }

    if (await fileExists(resolvedOutFile)) {
      const existingReceipt = validatePhaseAReceipt(await readJson(resolvedOutFile), {
        campaignId: params.campaignId,
        environment: params.environment,
        chainId: network.chainId,
        pathRelease: params.pathRelease
      });
      if (existingReceipt.sourceBundleDigest !== sourceBundleDigest) {
        throw new Error("Existing Phase A receipt belongs to a different bundle");
      }
      await verifyPhaseAConstructorOnChain(ethers, params, existingReceipt.pathNft, deployer.address);
      await verifyPhaseAOnChain(ethers, existingReceipt, deployer.address);
      console.log(`[path-campaign-phase-a] already complete receipt=${resolvedOutFile}`);
      return;
    }

    let checkpoint;
    let nft;
    if (await fileExists(checkpointFile)) {
      checkpoint = await readJson(checkpointFile);
      validatePhaseACheckpoint(checkpoint, {
        campaignId: params.campaignId,
        environment: params.environment,
        chainId: network.chainId,
        paramsSha256,
        sourceBundleDigest
      });
      nft = await ethers.getContractAt("PathNFT", checkpoint.pathNft.address, deployer);
    } else {
      const PathNFT = await ethers.getContractFactory("PathNFT", deployer);
      nft = await PathNFT.deploy(
        deployer.address,
        params.name,
        params.symbol,
        params.baseUri,
        params.reservedCap,
        params.sparkClaimDurationSec
      );
      await nft.waitForDeployment();

      const deployTx = nft.deploymentTransaction();
      if (!deployTx) throw new Error("PathNFT deployment transaction unavailable");
      const deployReceipt = await deployTx.wait();
      if (!deployReceipt) throw new Error("PathNFT deployment receipt unavailable");
      const nftAddress = await nft.getAddress();
      checkpoint = {
        checkpointVersion: "1",
        kind: "path_campaign_phase_a_checkpoint",
        status: "path_nft_deployed",
        campaignId: params.campaignId,
        environment: params.environment,
        chainId: network.chainId.toString(),
        paramsSha256,
        sourceBundleDigest,
        pathNft: {
          address: nftAddress,
          deploymentTx: deployTx.hash,
          blockNumber: deployReceipt.blockNumber.toString(),
          runtimeBytecodeHash: await runtimeCodeHash(ethers, nftAddress)
        }
      };
      await writeJsonAtomic(checkpointFile, checkpoint);
      if (stopAfterDeploy) throw new Error("PATH_CAMPAIGN_TEST_STOP:PATH_NFT_DEPLOYED");
    }
    const nftAddress = await nft.getAddress();
    const observedRuntimeHash = await runtimeCodeHash(ethers, nftAddress);
    if (observedRuntimeHash.toLowerCase() !== checkpoint.pathNft.runtimeBytecodeHash.toLowerCase()) {
      throw new Error("Phase A checkpoint PathNFT bytecode mismatch");
    }
    await verifyPhaseAConstructorOnChain(ethers, params, checkpoint.pathNft, deployer.address);

    const movementStates = {};
    for (const label of ["THOUGHT", "WILL", "AWA"]) {
      const movement = await nft[`MOVEMENT_${label}`]();
      movementStates[label] = {
        minter: await nft.getAuthorizedMinter(movement),
        quota: (await nft.getMovementQuota(movement)).toString(),
        frozen: await nft.isMovementFrozen(movement)
      };
    }
    const publicMinter = await nft.publicMinter();
    const publicMinterFrozen = await nft.publicMinterFrozen();
    if (!sameAddress(publicMinter, ZERO_ADDRESS) || publicMinterFrozen) {
      throw new Error("PHASE_A_EXPOSURE: PathNFT public mint state is not disabled");
    }
    const latest = await ethers.provider.getBlock("latest");
    if (!latest) throw new Error("latest block unavailable");

    const receipt = {
      receiptVersion: "1",
      kind: PATH_PHASE_A_KIND,
      status: "phase_a_complete",
      campaignId: params.campaignId,
      environment: params.environment,
      chainId: network.chainId.toString(),
      pathRelease: params.pathRelease,
      sourceBundleDigest,
      deployer: deployer.address,
      pathNft: {
        address: nftAddress,
        deploymentTx: checkpoint.pathNft.deploymentTx,
        blockNumber: checkpoint.pathNft.blockNumber,
        runtimeBytecodeHash: observedRuntimeHash
      },
      retainedAuthority: {
        holder: deployer.address,
        signerRef: params.retainedAuthority.signerRef,
        role: "DEFAULT_ADMIN_ROLE",
        permittedRemainingActions: [...PHASE_A_PERMITTED_ACTIONS],
        handoffComplete: false
      },
      movementStates,
      publicExposure: {
        pathPulseAdapter: null,
        pulseAuction: null,
        openTime: null,
        publicMinter,
        publicMinterFrozen,
        publicMintEnabled: false
      },
      observedAtBlock: latest.number.toString()
    };
    validatePhaseAReceipt(receipt, {
      campaignId: params.campaignId,
      environment: params.environment,
      chainId: network.chainId,
      pathRelease: params.pathRelease
    });
    await verifyPhaseAOnChain(ethers, receipt, deployer.address);

    await writeJsonAtomic(resolvedOutFile, receipt);
    console.log(`[path-campaign-phase-a] receipt=${resolvedOutFile}`);
    console.log(`[path-campaign-phase-a] pathNft=${nftAddress}`);
  } finally {
    await conn.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
