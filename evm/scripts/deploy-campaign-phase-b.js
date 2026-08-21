import fs from "node:fs/promises";
import path from "node:path";
import hre from "hardhat";
import {
  PATH_PHASE_B_KIND,
  PHASE_B_ACTION_ORDER,
  PHASE_B_CHECKPOINT_ACTIONS,
  ZERO_ADDRESS,
  assertFinalReceiptComplete,
  assertSha256,
  parseJsonStrict,
  phaseAProtocolPayload,
  phaseBCheckpointHas,
  runtimeCodeHash,
  sameAddress,
  sha256Json,
  thoughtNftContractEvidence,
  validatePhaseBCheckpoint,
  validatePhaseBParams,
  verifyPhaseBCheckpointOnChain
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

async function waitHash(tx) {
  const receipt = await tx.wait();
  if (!receipt) throw new Error(`Missing receipt for ${tx.hash}`);
  return { hash: tx.hash, blockNumber: receipt.blockNumber.toString() };
}

async function deploymentEvidence(ethers, contract) {
  const tx = contract.deploymentTransaction();
  const receipt = await tx?.wait();
  if (!tx || !receipt) throw new Error("Deployment evidence unavailable");
  const address = await contract.getAddress();
  return {
    contract: {
      address,
      deploymentTx: tx.hash,
      blockNumber: receipt.blockNumber.toString(),
      runtimeBytecodeHash: await runtimeCodeHash(ethers, address)
    },
    transaction: { hash: tx.hash, blockNumber: receipt.blockNumber.toString() }
  };
}

function isRecorded(checkpoint, action) {
  return phaseBCheckpointHas(checkpoint, action);
}

async function main() {
  const paramsFile = process.env.DEPLOY_PARAMS_FILE;
  const outFile = process.env.DEPLOY_OUT_FILE;
  const sourceBundleDigest = process.env.PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST;
  if (!paramsFile || !outFile || !sourceBundleDigest) {
    throw new Error(
      "Phase B requires DEPLOY_PARAMS_FILE, DEPLOY_OUT_FILE, and PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST"
    );
  }
  assertSha256(sourceBundleDigest, "PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST");
  const rawParams = await readJson(paramsFile);
  validatePhaseBParams(rawParams);
  const paramsSha256 = sha256Json(rawParams);
  const resolvedOutFile = path.resolve(outFile);
  const checkpointFile = path.resolve(
    process.env.PATH_CAMPAIGN_CHECKPOINT_FILE
      ?? path.join(path.dirname(resolvedOutFile), "path-phase-b-checkpoint.json")
  );

  const conn = await hre.network.connect();
  const { ethers } = conn;
  try {
    const [deployer] = await ethers.getSigners();
    const network = await ethers.provider.getNetwork();
    if (network.chainId !== BigInt(rawParams.expectedChainId)) {
      throw new Error(`CHAIN_MISMATCH: expected=${rawParams.expectedChainId} observed=${network.chainId}`);
    }
    const stopAfterAction = process.env.PATH_CAMPAIGN_TEST_STOP_AFTER_ACTION;
    if (stopAfterAction) {
      if ([1n, 11155111n].includes(network.chainId)) {
        throw new Error("PATH_CAMPAIGN_TEST_STOP_AFTER_ACTION is ephemeral-chain-only");
      }
      if (!PHASE_B_CHECKPOINT_ACTIONS.includes(stopAfterAction)) {
        throw new Error(`Unknown test stop action: ${stopAfterAction}`);
      }
    }

    if (await fileExists(resolvedOutFile)) {
      const existing = await readJson(resolvedOutFile);
      assertFinalReceiptComplete(existing, {
        campaignId: rawParams.campaignId,
        chainId: network.chainId
      });
      if (existing.sourceBundleDigest !== sourceBundleDigest
        || existing.linkedReceipts.pathPhaseAReceiptSha256 !== rawParams.pathPhaseA.receiptSha256
        || existing.linkedReceipts.thoughtDeploymentReceiptSha256 !== rawParams.thoughtDeployment.receiptSha256) {
        throw new Error("Existing Phase B receipt belongs to another exact campaign input");
      }
      console.log(`[path-campaign-phase-b] already complete receipt=${resolvedOutFile}`);
      return;
    }

    let checkpoint;
    if (await fileExists(checkpointFile)) {
      checkpoint = await readJson(checkpointFile);
      validatePhaseBCheckpoint(checkpoint, {
        campaignId: rawParams.campaignId,
        environment: rawParams.environment,
        chainId: network.chainId,
        paramsSha256,
        sourceBundleDigest,
        pathPhaseAReceiptSha256: rawParams.pathPhaseA.receiptSha256,
        thoughtDeploymentReceiptSha256: rawParams.thoughtDeployment.receiptSha256
      });
    } else {
      checkpoint = {
        checkpointVersion: "1",
        kind: "path_campaign_phase_b_checkpoint",
        status: "phase_running",
        campaignId: rawParams.campaignId,
        environment: rawParams.environment,
        chainId: network.chainId.toString(),
        paramsSha256,
        sourceBundleDigest,
        linkedReceipts: {
          pathPhaseAReceiptSha256: rawParams.pathPhaseA.receiptSha256,
          thoughtDeploymentReceiptSha256: rawParams.thoughtDeployment.receiptSha256
        },
        completedActions: [],
        contracts: {},
        transactions: {
          movement: {},
          deployment: {},
          wiring: {},
          authority: {}
        }
      };
      await writeJsonAtomic(checkpointFile, checkpoint);
    }

    const allActionsRecorded = checkpoint.completedActions.length === PHASE_B_CHECKPOINT_ACTIONS.length;
    const latestBefore = await ethers.provider.getBlock("latest");
    if (!latestBefore) throw new Error("Latest block unavailable");
    const params = validatePhaseBParams(
      rawParams,
      allActionsRecorded ? {} : { latestBlockTimestamp: latestBefore.timestamp }
    );

    async function mark(action, mutate) {
      const expected = PHASE_B_CHECKPOINT_ACTIONS[checkpoint.completedActions.length];
      if (expected !== action) {
        throw new Error(`Checkpoint order mismatch: expected ${expected}, got ${action}`);
      }
      mutate();
      checkpoint.completedActions.push(action);
      await writeJsonAtomic(checkpointFile, checkpoint);
      if (stopAfterAction === action) {
        throw new Error(`PATH_CAMPAIGN_TEST_STOP:${action}`);
      }
    }

    const phaseAReceipt = phaseAProtocolPayload(params);
    const thoughtNftEvidence = thoughtNftContractEvidence(params);
    const checkpointState = await verifyPhaseBCheckpointOnChain(
      ethers,
      params,
      checkpoint,
      deployer.address
    );
    const nft = checkpointState.nft.connect(deployer);
    const thoughtNft = checkpointState.thoughtNft;
    const defaultAdminRole = await nft.DEFAULT_ADMIN_ROLE();

    async function configureMovement(label, minter, quota) {
      const setAction = `SET_${label}_MOVEMENT`;
      const freezeAction = `FREEZE_${label}_MOVEMENT`;
      const movement = await nft[`MOVEMENT_${label}`]();
      const setRecorded = isRecorded(checkpoint, setAction);
      const freezeRecorded = isRecorded(checkpoint, freezeAction);
      let observedMinter = await nft.getAuthorizedMinter(movement);
      let observedQuota = await nft.getMovementQuota(movement);
      let observedFrozen = await nft.isMovementFrozen(movement);

      if (setRecorded) {
        if (!sameAddress(observedMinter, minter) || observedQuota !== quota) {
          throw new Error(`${label} configured state does not match its checkpoint`);
        }
      } else {
        if (!sameAddress(observedMinter, ZERO_ADDRESS) || observedQuota !== 0n || observedFrozen) {
          throw new Error(`UNRECORDED_PARTIAL_STATE: ${label} changed without a checkpoint`);
        }
        const evidence = await waitHash(await nft.setMovementConfig(movement, minter, quota));
        await mark(setAction, () => {
          checkpoint.transactions.movement[label] ??= {};
          checkpoint.transactions.movement[label].set = evidence;
        });
        observedMinter = await nft.getAuthorizedMinter(movement);
        observedQuota = await nft.getMovementQuota(movement);
        if (!sameAddress(observedMinter, minter) || observedQuota !== quota) {
          throw new Error(`${label} verification failed after set`);
        }
      }

      observedFrozen = await nft.isMovementFrozen(movement);
      if (freezeRecorded) {
        if (!observedFrozen) throw new Error(`${label} freeze checkpoint does not match on-chain state`);
      } else {
        if (observedFrozen) throw new Error(`UNRECORDED_PARTIAL_STATE: ${label} froze without a checkpoint`);
        const evidence = await waitHash(await nft.freezeMovementConfig(movement));
        await mark(freezeAction, () => {
          checkpoint.transactions.movement[label] ??= {};
          checkpoint.transactions.movement[label].freeze = evidence;
        });
        if (!(await nft.isMovementFrozen(movement))) throw new Error(`${label} freeze verification failed`);
      }
    }

    await configureMovement("THOUGHT", thoughtNft, 1n);
    await configureMovement("WILL", params.remainingMovements.WILL.minter, 10n);
    await configureMovement("AWA", params.remainingMovements.AWA.minter, 1n);

    let adapter;
    if (isRecorded(checkpoint, "DEPLOY_PATH_PULSE_ADAPTER")) {
      const evidence = checkpoint.contracts.pathPulseAdapter;
      if (!evidence) throw new Error("Adapter checkpoint evidence missing");
      const observed = await runtimeCodeHash(ethers, evidence.address);
      if (observed.toLowerCase() !== evidence.runtimeBytecodeHash.toLowerCase()) {
        throw new Error("Adapter checkpoint bytecode mismatch");
      }
      adapter = await ethers.getContractAt("PathPulseAdapter", evidence.address, deployer);
      if (!sameAddress(await adapter.pathNft(), phaseAReceipt.pathNft.address)
        || await adapter.tokenBase() !== BigInt(params.auction.firstPublicId)
        || await adapter.epochBase() !== BigInt(params.auction.epochBase)) {
        throw new Error("Adapter checkpoint constructor mismatch");
      }
    } else {
      const Adapter = await ethers.getContractFactory("PathPulseAdapter", deployer);
      adapter = await Adapter.deploy(
        deployer.address,
        ethers.ZeroAddress,
        phaseAReceipt.pathNft.address,
        params.auction.firstPublicId,
        params.auction.epochBase
      );
      await adapter.waitForDeployment();
      const evidence = await deploymentEvidence(ethers, adapter);
      await mark("DEPLOY_PATH_PULSE_ADAPTER", () => {
        checkpoint.contracts.pathPulseAdapter = evidence.contract;
        checkpoint.transactions.deployment.pathPulseAdapter = evidence.transaction;
      });
    }
    const adapterAddress = await adapter.getAddress();

    let auction;
    if (isRecorded(checkpoint, "DEPLOY_PULSE_AUCTION_WITH_AUTHORIZED_OPEN_TIME")) {
      const evidence = checkpoint.contracts.pulseAuction;
      if (!evidence) throw new Error("Auction checkpoint evidence missing");
      const observed = await runtimeCodeHash(ethers, evidence.address);
      if (observed.toLowerCase() !== evidence.runtimeBytecodeHash.toLowerCase()) {
        throw new Error("Auction checkpoint bytecode mismatch");
      }
      auction = await ethers.getContractAt("PulseAuction", evidence.address, deployer);
      if (BigInt(await auction.openTime()) !== BigInt(params.openTimeAuthorization.authorizedOpenTime)
        || !sameAddress(await auction.mintAdapter(), adapterAddress)
        || !sameAddress(await auction.treasury(), params.treasury)
        || !sameAddress(await auction.paymentToken(), params.auction.paymentToken)) {
        throw new Error("Auction checkpoint constructor mismatch");
      }
    } else {
      const Auction = await ethers.getContractFactory("PulseAuction", deployer);
      auction = await Auction.deploy(
        params.openTimeAuthorization.authorizedOpenTime,
        params.auction.k,
        params.auction.genesisPrice,
        params.auction.genesisFloor,
        params.auction.pts,
        params.auction.paymentToken,
        params.treasury,
        adapterAddress
      );
      await auction.waitForDeployment();
      const evidence = await deploymentEvidence(ethers, auction);
      await mark("DEPLOY_PULSE_AUCTION_WITH_AUTHORIZED_OPEN_TIME", () => {
        checkpoint.contracts.pulseAuction = evidence.contract;
        checkpoint.transactions.deployment.pulseAuction = evidence.transaction;
      });
    }
    const auctionAddress = await auction.getAddress();

    if (isRecorded(checkpoint, "SET_ADAPTER_AUCTION")) {
      if (!sameAddress(await adapter.auction(), auctionAddress)) throw new Error("Adapter auction checkpoint mismatch");
    } else {
      if (!sameAddress(await adapter.auction(), ZERO_ADDRESS) || await adapter.wiringFrozen()) {
        throw new Error("UNRECORDED_PARTIAL_STATE: adapter auction changed without a checkpoint");
      }
      const evidence = await waitHash(await adapter.setAuction(auctionAddress));
      await mark("SET_ADAPTER_AUCTION", () => {
        checkpoint.transactions.wiring.adapterSetAuction = evidence;
      });
    }

    if (isRecorded(checkpoint, "FREEZE_ADAPTER_WIRING")) {
      if (!(await adapter.wiringFrozen())) throw new Error("Adapter freeze checkpoint mismatch");
    } else {
      if (await adapter.wiringFrozen()) throw new Error("UNRECORDED_PARTIAL_STATE: adapter froze without a checkpoint");
      const evidence = await waitHash(await adapter.freezeWiring());
      await mark("FREEZE_ADAPTER_WIRING", () => {
        checkpoint.transactions.wiring.adapterFreezeWiring = evidence;
      });
    }

    const minterRole = await nft.MINTER_ROLE();
    if (isRecorded(checkpoint, "GRANT_PUBLIC_MINTER_ROLE_TO_ADAPTER")) {
      if (!(await nft.hasRole(minterRole, adapterAddress))) throw new Error("Adapter MINTER_ROLE checkpoint mismatch");
    } else {
      if (await nft.hasRole(minterRole, adapterAddress)) {
        throw new Error("UNRECORDED_PARTIAL_STATE: adapter MINTER_ROLE granted without a checkpoint");
      }
      const evidence = await waitHash(await nft.grantRole(minterRole, adapterAddress));
      await mark("GRANT_PUBLIC_MINTER_ROLE_TO_ADAPTER", () => {
        checkpoint.transactions.wiring.nftGrantMinterRole = evidence;
      });
    }

    if (isRecorded(checkpoint, "FREEZE_PUBLIC_MINTER_TO_ADAPTER")) {
      if (!(await nft.publicMinterFrozen()) || !sameAddress(await nft.publicMinter(), adapterAddress)) {
        throw new Error("Public minter checkpoint mismatch");
      }
    } else {
      if (await nft.publicMinterFrozen() || !sameAddress(await nft.publicMinter(), ZERO_ADDRESS)) {
        throw new Error("UNRECORDED_PARTIAL_STATE: public minter changed without a checkpoint");
      }
      const evidence = await waitHash(await nft.freezePublicMinter(adapterAddress));
      await mark("FREEZE_PUBLIC_MINTER_TO_ADAPTER", () => {
        checkpoint.transactions.wiring.nftFreezePublicMinter = evidence;
      });
    }

    const reservedRole = await nft.RESERVED_ROLE();
    if (isRecorded(checkpoint, "GRANT_RESERVED_ROLE_TO_SPARK_ISSUER")) {
      if (!(await nft.hasRole(reservedRole, params.finalAuthority.sparkIssuer))) {
        throw new Error("Spark issuer checkpoint mismatch");
      }
    } else {
      if (await nft.hasRole(reservedRole, params.finalAuthority.sparkIssuer)) {
        throw new Error("UNRECORDED_PARTIAL_STATE: Spark issuer role granted without a checkpoint");
      }
      const evidence = await waitHash(await nft.grantRole(reservedRole, params.finalAuthority.sparkIssuer));
      await mark("GRANT_RESERVED_ROLE_TO_SPARK_ISSUER", () => {
        checkpoint.transactions.authority.nftGrantReservedRole = evidence;
      });
    }

    if (isRecorded(checkpoint, "GRANT_DEFAULT_ADMIN_TO_FINAL_ADMIN")) {
      if (!(await nft.hasRole(defaultAdminRole, params.finalAuthority.admin))) {
        throw new Error("Final admin grant checkpoint mismatch");
      }
    } else {
      if (await nft.hasRole(defaultAdminRole, params.finalAuthority.admin)) {
        throw new Error("UNRECORDED_PARTIAL_STATE: final admin granted without a checkpoint");
      }
      const evidence = await waitHash(await nft.grantRole(defaultAdminRole, params.finalAuthority.admin));
      await mark("GRANT_DEFAULT_ADMIN_TO_FINAL_ADMIN", () => {
        checkpoint.transactions.authority.nftGrantDefaultAdmin = evidence;
      });
    }

    if (isRecorded(checkpoint, "TRANSFER_ADAPTER_OWNERSHIP_TO_FINAL_ADMIN")) {
      if (!sameAddress(await adapter.owner(), params.finalAuthority.admin)) {
        throw new Error("Adapter ownership checkpoint mismatch");
      }
    } else {
      if (!sameAddress(await adapter.owner(), deployer.address)) {
        throw new Error("UNRECORDED_PARTIAL_STATE: adapter ownership changed without a checkpoint");
      }
      const evidence = await waitHash(await adapter.transferOwnership(params.finalAuthority.admin));
      await mark("TRANSFER_ADAPTER_OWNERSHIP_TO_FINAL_ADMIN", () => {
        checkpoint.transactions.authority.adapterTransferOwnership = evidence;
      });
    }

    if (isRecorded(checkpoint, "RENOUNCE_DEPLOYER_DEFAULT_ADMIN")) {
      if (await nft.hasRole(defaultAdminRole, deployer.address)) {
        throw new Error("Deployer admin renounce checkpoint mismatch");
      }
    } else {
      if (!(await nft.hasRole(defaultAdminRole, deployer.address))) {
        throw new Error("UNRECORDED_PARTIAL_STATE: deployer admin removed without a checkpoint");
      }
      const evidence = await waitHash(await nft.renounceRole(defaultAdminRole, deployer.address));
      await mark("RENOUNCE_DEPLOYER_DEFAULT_ADMIN", () => {
        checkpoint.transactions.authority.nftRenounceDeployerDefaultAdmin = evidence;
      });
    }

    if (checkpoint.completedActions.length !== PHASE_B_CHECKPOINT_ACTIONS.length) {
      throw new Error("Phase B actions did not reach the final checkpoint");
    }
    let completionBlock;
    if (checkpoint.completedAtBlock) {
      completionBlock = await ethers.provider.getBlock(Number(checkpoint.completedAtBlock));
    } else {
      completionBlock = await ethers.provider.getBlock("latest");
      if (!completionBlock) throw new Error("Latest completion block unavailable");
      checkpoint.completedAtBlock = completionBlock.number.toString();
      await writeJsonAtomic(checkpointFile, checkpoint);
    }
    if (!completionBlock) throw new Error("Recorded completion block unavailable");
    const openTime = BigInt(params.openTimeAuthorization.authorizedOpenTime);
    if (BigInt(completionBlock.timestamp) >= openTime) {
      throw new Error("UNQUALIFIED_CAMPAIGN: finalization completed at or after openTime");
    }
    const finalObservationBlock = await ethers.provider.getBlock("latest");
    if (!finalObservationBlock || BigInt(finalObservationBlock.timestamp) >= openTime) {
      throw new Error("UNQUALIFIED_CAMPAIGN: final receipt cannot be emitted at or after openTime");
    }

    const movementStates = {};
    for (const [label, expectedMinter, expectedQuota] of [
      ["THOUGHT", thoughtNft, 1n],
      ["WILL", params.remainingMovements.WILL.minter, 10n],
      ["AWA", params.remainingMovements.AWA.minter, 1n]
    ]) {
      const movement = await nft[`MOVEMENT_${label}`]();
      const minter = await nft.getAuthorizedMinter(movement);
      const quota = await nft.getMovementQuota(movement);
      const frozen = await nft.isMovementFrozen(movement);
      if (!sameAddress(minter, expectedMinter) || quota !== expectedQuota || !frozen) {
        throw new Error(`UNQUALIFIED_CAMPAIGN: ${label} final movement mismatch`);
      }
      movementStates[label] = { minter, quota: quota.toString(), frozen };
    }
    if (!(await adapter.wiringFrozen())
      || !sameAddress(await adapter.pathNft(), phaseAReceipt.pathNft.address)
      || !sameAddress(await adapter.auction(), auctionAddress)
      || !sameAddress(await auction.mintAdapter(), adapterAddress)
      || !sameAddress(await auction.treasury(), params.treasury)
      || BigInt(await auction.openTime()) !== openTime
      || !(await nft.publicMinterFrozen())
      || !sameAddress(await nft.publicMinter(), adapterAddress)
      || !(await nft.hasRole(defaultAdminRole, params.finalAuthority.admin))
      || await nft.hasRole(defaultAdminRole, deployer.address)
      || !(await nft.hasRole(reservedRole, params.finalAuthority.sparkIssuer))
      || !sameAddress(await adapter.owner(), params.finalAuthority.admin)) {
      throw new Error("UNQUALIFIED_CAMPAIGN: combined final state mismatch");
    }

    const finalReceipt = {
      receiptVersion: "1",
      kind: PATH_PHASE_B_KIND,
      status: "complete",
      campaignId: params.campaignId,
      environment: params.environment,
      chainId: network.chainId.toString(),
      sourceBundleDigest,
      releaseMatrix: params.releaseMatrix,
      linkedReceipts: {
        ...checkpoint.linkedReceipts,
        pathPhaseAProtocolPayloadSha256: params.pathPhaseA.receipt.protocol_payload.sha256,
        thoughtProtocolPayloadSha256: params.thoughtDeployment.receipt.protocol_payload.sha256
      },
      deployer: deployer.address,
      contracts: {
        pathNft: phaseAReceipt.pathNft,
        thoughtNft: thoughtNftEvidence,
        pathPulseAdapter: checkpoint.contracts.pathPulseAdapter,
        pulseAuction: checkpoint.contracts.pulseAuction
      },
      movementStates,
      auction: {
        openTime: openTime.toString(),
        openTimeAuthorizationDigest: params.openTimeAuthorization.authorizationDigest,
        paymentToken: await auction.paymentToken(),
        treasury: await auction.treasury(),
        mintAdapter: await auction.mintAdapter()
      },
      finalAuthority: {
        admin: params.finalAuthority.admin,
        adminSignerRef: params.finalAuthority.adminSignerRef,
        sparkIssuer: params.finalAuthority.sparkIssuer,
        sparkIssuerSignerRef: params.finalAuthority.sparkIssuerSignerRef,
        treasury: params.finalAuthority.treasury,
        treasurySignerRef: params.finalAuthority.treasurySignerRef,
        adapterOwner: await adapter.owner(),
        deployerRetainsDefaultAdmin: await nft.hasRole(defaultAdminRole, deployer.address)
      },
      transactions: checkpoint.transactions,
      actionOrder: [...PHASE_B_ACTION_ORDER],
      acceptance: {
        phaseAReceiptLinked: true,
        thoughtReceiptLinked: true,
        thoughtPathBindingVerified: true,
        allMovementsConfiguredAndFrozen: true,
        adapterAndAuctionWiringFrozen: true,
        openTimeAuthorizedAndFuture: true,
        publicMinterFrozen: true,
        finalAuthorityVerified: true,
        deployerAuthorityRemoved: true,
        noPrematurePublicExposure: true
      },
      observedAtBlock: finalObservationBlock.number.toString()
    };
    assertFinalReceiptComplete(finalReceipt, {
      campaignId: params.campaignId,
      chainId: network.chainId
    });
    await writeJsonAtomic(resolvedOutFile, finalReceipt);
    console.log(`[path-campaign-phase-b] receipt=${resolvedOutFile}`);
    console.log(`[path-campaign-phase-b] pathNft=${phaseAReceipt.pathNft.address}`);
    console.log(`[path-campaign-phase-b] pathPulseAdapter=${adapterAddress}`);
    console.log(`[path-campaign-phase-b] pulseAuction=${auctionAddress}`);
  } finally {
    await conn.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
