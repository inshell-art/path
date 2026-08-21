import fs from "node:fs/promises";
import path from "node:path";
import hre from "hardhat";
import {
  PATH_PHASE_B_KIND,
  PHASE_B_CHECKPOINT_ACTIONS,
  assertFinalReceiptComplete,
  canonicalJson,
  parseJsonStrict,
  phaseAProtocolPayload,
  runtimeCodeHash,
  sameAddress,
  sha256Json,
  thoughtNftContractEvidence,
  validatePhaseACheckpoint,
  validatePhaseAParams,
  validatePhaseAReceipt,
  validatePhaseBCheckpoint,
  validatePhaseBParams,
  verifyPhaseAOnChain,
  verifyPhaseACheckpointOnChain,
  verifyPhaseAConstructorOnChain,
  verifyPhaseBCheckpointOnChain,
  verifyThoughtOnChain
} from "./lib/path-campaign.mjs";

async function readJson(file, label) {
  if (!file) throw new Error(`Missing ${label}`);
  return parseJsonStrict(await fs.readFile(path.resolve(file), "utf8"), label);
}

async function fileExists(file) {
  if (!file) return false;
  try {
    await fs.access(path.resolve(file));
    return true;
  } catch {
    return false;
  }
}

async function verifyFinalOnChain(ethers, params, receipt) {
  const phaseAPayload = phaseAProtocolPayload(params);
  const thoughtEvidence = thoughtNftContractEvidence(params);
  assertFinalReceiptComplete(receipt, {
    campaignId: params.campaignId,
    chainId: params.expectedChainId,
    sourceBundleDigest: process.env.PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST || undefined
  });
  if (receipt.environment !== params.environment
    || canonicalJson(receipt.releaseMatrix) !== canonicalJson(params.releaseMatrix)) {
    throw new Error("Final receipt environment/release matrix mismatch");
  }
  if (receipt.linkedReceipts.pathPhaseAReceiptSha256 !== params.pathPhaseA.receiptSha256
    || receipt.linkedReceipts.thoughtDeploymentReceiptSha256 !== params.thoughtDeployment.receiptSha256
    || receipt.linkedReceipts.pathPhaseAProtocolPayloadSha256
      !== params.pathPhaseA.receipt.protocol_payload.sha256
    || receipt.linkedReceipts.thoughtProtocolPayloadSha256
      !== params.thoughtDeployment.receipt.protocol_payload.sha256) {
    throw new Error("Final receipt linkage mismatch");
  }
  const deployer = phaseAPayload.retainedAuthority.holder;
  if (!sameAddress(receipt.deployer, deployer)
    || !sameAddress(receipt.contracts.pathNft.address, phaseAPayload.pathNft.address)
    || !sameAddress(
      receipt.contracts.thoughtNft.address,
      thoughtEvidence.address
    )) {
    throw new Error("Final receipt deployment linkage mismatch");
  }
  const finalCheckpoint = {
    checkpointVersion: "1",
    kind: "path_campaign_phase_b_checkpoint",
    status: "phase_running",
    campaignId: params.campaignId,
    environment: params.environment,
    chainId: String(params.expectedChainId),
    paramsSha256: sha256Json(params),
    sourceBundleDigest: receipt.sourceBundleDigest,
    linkedReceipts: receipt.linkedReceipts,
    completedActions: [...PHASE_B_CHECKPOINT_ACTIONS],
    contracts: {
      pathPulseAdapter: receipt.contracts.pathPulseAdapter,
      pulseAuction: receipt.contracts.pulseAuction
    },
    transactions: receipt.transactions,
    completedAtBlock: receipt.observedAtBlock
  };
  validatePhaseBCheckpoint(finalCheckpoint, {
    campaignId: params.campaignId,
    environment: params.environment,
    chainId: params.expectedChainId,
    paramsSha256: sha256Json(params),
    sourceBundleDigest: receipt.sourceBundleDigest,
    pathPhaseAReceiptSha256: params.pathPhaseA.receiptSha256,
    thoughtDeploymentReceiptSha256: params.thoughtDeployment.receiptSha256
  });
  await verifyPhaseBCheckpointOnChain(ethers, params, finalCheckpoint, deployer);
  const nft = await ethers.getContractAt("PathNFT", receipt.contracts.pathNft.address);
  await verifyPhaseAOnChainAfterFinal(ethers, params, receipt, nft);
  await verifyThoughtOnChain(ethers, params);

  const Adapter = await ethers.getContractFactory("PathPulseAdapter");
  const adapter = Adapter.attach(receipt.contracts.pathPulseAdapter.address);
  const Auction = await ethers.getContractFactory("PulseAuction");
  const auction = Auction.attach(receipt.contracts.pulseAuction.address);
  for (const key of ["pathNft", "pathPulseAdapter", "pulseAuction"]) {
    const observed = await runtimeCodeHash(ethers, receipt.contracts[key].address);
    if (observed.toLowerCase() !== receipt.contracts[key].runtimeBytecodeHash.toLowerCase()) {
      throw new Error(`${key} runtime bytecode hash mismatch`);
    }
  }

  if (!(await adapter.wiringFrozen())
    || !sameAddress(await adapter.pathNft(), receipt.contracts.pathNft.address)
    || !sameAddress(await adapter.auction(), receipt.contracts.pulseAuction.address)
    || await adapter.tokenBase() !== BigInt(params.auction.firstPublicId)
    || await adapter.epochBase() !== BigInt(params.auction.epochBase)) {
    throw new Error("Adapter final wiring mismatch");
  }
  if (!sameAddress(await auction.mintAdapter(), receipt.contracts.pathPulseAdapter.address)
    || !sameAddress(await auction.treasury(), params.treasury)
    || !sameAddress(await auction.paymentToken(), params.auction.paymentToken)
    || BigInt(await auction.openTime()) !== BigInt(params.openTimeAuthorization.authorizedOpenTime)
    || await auction.curveK() !== BigInt(params.auction.k)
    || await auction.genesisPrice() !== BigInt(params.auction.genesisPrice)
    || await auction.genesisFloor() !== BigInt(params.auction.genesisFloor)
    || await auction.pts() !== BigInt(params.auction.pts)) {
    throw new Error("Auction final configuration mismatch");
  }
  if (receipt.auction.openTime !== String(params.openTimeAuthorization.authorizedOpenTime)
    || receipt.auction.openTimeAuthorizationDigest !== params.openTimeAuthorization.authorizationDigest
    || !sameAddress(receipt.auction.paymentToken, params.auction.paymentToken)
    || !sameAddress(receipt.auction.treasury, params.treasury)) {
    throw new Error("Final receipt auction evidence mismatch");
  }

  const defaultAdminRole = await nft.DEFAULT_ADMIN_ROLE();
  const reservedRole = await nft.RESERVED_ROLE();
  const minterRole = await nft.MINTER_ROLE();
  if (!(await nft.hasRole(defaultAdminRole, params.finalAuthority.admin))
    || await nft.hasRole(defaultAdminRole, deployer)
    || !(await nft.hasRole(reservedRole, params.finalAuthority.sparkIssuer))
    || await nft.hasRole(reservedRole, deployer)
    || !(await nft.hasRole(minterRole, receipt.contracts.pathPulseAdapter.address))
    || await nft.hasRole(minterRole, deployer)
    || !sameAddress(await adapter.owner(), params.finalAuthority.admin)
    || !sameAddress(receipt.finalAuthority.admin, params.finalAuthority.admin)
    || !sameAddress(receipt.finalAuthority.sparkIssuer, params.finalAuthority.sparkIssuer)
    || !sameAddress(receipt.finalAuthority.treasury, params.finalAuthority.treasury)) {
    throw new Error("Final role/owner state mismatch");
  }
  const observedBlock = await ethers.provider.getBlock(Number(receipt.observedAtBlock));
  if (!observedBlock || BigInt(observedBlock.timestamp) >= BigInt(params.openTimeAuthorization.authorizedOpenTime)) {
    throw new Error("Campaign finalization was not completed before openTime");
  }
}

async function verifyPhaseAOnChainAfterFinal(ethers, params, receipt, nft) {
  const expected = {
    THOUGHT: [thoughtNftContractEvidence(params).address, 1n],
    WILL: [params.remainingMovements.WILL.minter, 10n],
    AWA: [params.remainingMovements.AWA.minter, 1n]
  };
  for (const [label, [minter, quota]] of Object.entries(expected)) {
    const movement = await nft[`MOVEMENT_${label}`]();
    if (!sameAddress(await nft.getAuthorizedMinter(movement), minter)
      || await nft.getMovementQuota(movement) !== quota
      || !(await nft.isMovementFrozen(movement))) {
      throw new Error(`${label} final movement state mismatch`);
    }
    const receiptState = receipt.movementStates[label];
    if (!sameAddress(receiptState.minter, minter)
      || BigInt(receiptState.quota) !== quota
      || receiptState.frozen !== true) {
      throw new Error(`${label} final receipt movement mismatch`);
    }
  }
  if (!sameAddress(await nft.publicMinter(), receipt.contracts.pathPulseAdapter.address)
    || !(await nft.publicMinterFrozen())) {
    throw new Error("Final public minter state mismatch");
  }
}

async function main() {
  const mode = process.env.PATH_CAMPAIGN_CHECK_MODE ?? "predeploy";
  const kind = process.env.PATH_CAMPAIGN_INPUT_KIND;
  const params = await readJson(process.env.DEPLOY_PARAMS_FILE, "DEPLOY_PARAMS_FILE");
  const outFile = process.env.PATH_CAMPAIGN_CHECKS_OUT;
  if (!outFile) throw new Error("Missing PATH_CAMPAIGN_CHECKS_OUT");

  const conn = await hre.network.connect();
  const { ethers } = conn;
  try {
    const [signer] = await ethers.getSigners();
    const network = await ethers.provider.getNetwork();
    const latest = await ethers.provider.getBlock("latest");
    if (!latest) throw new Error("Latest block unavailable");
    const invariants = {};
    const policySigner = process.env.PATH_CAMPAIGN_POLICY_SIGNER_ADDRESS;
    if (!policySigner || !sameAddress(signer.address, policySigner)) {
      throw new Error("Connected signer does not match the deploy lane policy");
    }
    if (process.env.PATH_CAMPAIGN_RPC_HOST_ALLOWED !== "1") {
      throw new Error("RPC host was not verified against the lane policy");
    }
    invariants.rpc_host_allowlisted = true;
    invariants.policy_signer_verified = true;

    if (kind === "path_campaign_phase_a") {
      validatePhaseAParams(params);
      if (network.chainId !== BigInt(params.expectedChainId)) throw new Error("Phase A chain mismatch");
      if (!sameAddress(signer.address, params.retainedAuthority.address)) throw new Error("Phase A signer mismatch");
      invariants.phase_a_has_no_open_time = !Object.hasOwn(params, "openTime");
      invariants.retained_authority_matches_signer = true;
      if (mode === "postdeploy") {
        const receipt = await readJson(process.env.PATH_CAMPAIGN_RECEIPT_FILE, "PATH_CAMPAIGN_RECEIPT_FILE");
        validatePhaseAReceipt(receipt, {
          campaignId: params.campaignId,
          environment: params.environment,
          chainId: network.chainId,
          pathRelease: params.pathRelease
        });
        await verifyPhaseAConstructorOnChain(ethers, params, receipt.pathNft, signer.address);
        await verifyPhaseAOnChain(ethers, receipt, signer.address);
        invariants.phase_a_onchain_checkpoint_verified = true;
      } else {
        const checkpointFile = process.env.PATH_CAMPAIGN_CHECKPOINT_FILE;
        if (await fileExists(checkpointFile)) {
          const sourceBundleDigest = process.env.PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST;
          if (!sourceBundleDigest) throw new Error("Phase A resume requires PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST");
          const checkpoint = await readJson(checkpointFile, "PATH_CAMPAIGN_CHECKPOINT_FILE");
          validatePhaseACheckpoint(checkpoint, {
            campaignId: params.campaignId,
            environment: params.environment,
            chainId: network.chainId,
            paramsSha256: sha256Json(params),
            sourceBundleDigest
          });
          await verifyPhaseACheckpointOnChain(ethers, params, checkpoint, signer.address);
          invariants.phase_a_resume_checkpoint_verified = true;
        }
      }
    } else if (kind === "path_campaign_phase_b") {
      let checkpoint = null;
      const checkpointFile = process.env.PATH_CAMPAIGN_CHECKPOINT_FILE;
      if (mode === "predeploy" && await fileExists(checkpointFile)) {
        checkpoint = await readJson(checkpointFile, "PATH_CAMPAIGN_CHECKPOINT_FILE");
      }
      const checkpointComplete = checkpoint?.completedActions?.length === PHASE_B_CHECKPOINT_ACTIONS.length;
      validatePhaseBParams(
        params,
        mode === "predeploy" && !checkpointComplete ? { latestBlockTimestamp: latest.timestamp } : {}
      );
      if (network.chainId !== BigInt(params.expectedChainId)) throw new Error("Phase B chain mismatch");
      if (!sameAddress(signer.address, phaseAProtocolPayload(params).retainedAuthority.holder)) {
        throw new Error("Phase B signer mismatch");
      }
      if (mode === "predeploy") {
        if (checkpoint) {
          const sourceBundleDigest = process.env.PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST;
          if (!sourceBundleDigest) throw new Error("Resume preflight requires PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST");
          validatePhaseBCheckpoint(checkpoint, {
            campaignId: params.campaignId,
            environment: params.environment,
            chainId: network.chainId,
            paramsSha256: sha256Json(params),
            sourceBundleDigest,
            pathPhaseAReceiptSha256: params.pathPhaseA.receiptSha256,
            thoughtDeploymentReceiptSha256: params.thoughtDeployment.receiptSha256
          });
          await verifyPhaseBCheckpointOnChain(ethers, params, checkpoint, signer.address);
          if (checkpointComplete
            && BigInt(latest.timestamp) >= BigInt(params.openTimeAuthorization.authorizedOpenTime)) {
            throw new Error("Completed Phase B checkpoint cannot emit a final receipt at or after openTime");
          }
          invariants.phase_b_resume_checkpoint_verified = true;
        } else {
          await verifyPhaseAOnChain(ethers, phaseAProtocolPayload(params), signer.address);
          await verifyThoughtOnChain(ethers, params);
          for (const label of ["WILL", "AWA"]) {
            const config = params.remainingMovements[label];
            const observed = await runtimeCodeHash(ethers, config.minter);
            if (observed.toLowerCase() !== config.runtimeBytecodeHash.toLowerCase()) {
              throw new Error(`${label} runtime bytecode hash mismatch`);
            }
          }
          invariants.phase_a_checkpoint_verified = true;
        }
        invariants.thought_path_binding_verified = true;
        invariants.open_time_authorized_and_safe = true;
      } else {
        const receipt = await readJson(process.env.PATH_CAMPAIGN_RECEIPT_FILE, "PATH_CAMPAIGN_RECEIPT_FILE");
        if (receipt.kind !== PATH_PHASE_B_KIND) throw new Error("Wrong Phase B receipt kind");
        await verifyFinalOnChain(ethers, params, receipt);
        invariants.combined_postconditions_verified = true;
      }
    } else {
      throw new Error(`Unsupported PATH campaign input kind: ${kind}`);
    }

    const payload = {
      checks_version: 2,
      network: process.env.PATH_CAMPAIGN_NETWORK_LABEL ?? conn.networkName,
      lane: process.env.PATH_CAMPAIGN_LANE_LABEL ?? "deploy",
      phase: mode,
      deployment_present: mode === "postdeploy",
      pass: Object.values(invariants).every(Boolean),
      required_checks: {
        chain_id: true,
        rpc_allowlist: true,
        signer_allowlist: true,
        bytecode_hash: true,
        proxy_implementation: true,
        path_invariants: Object.values(invariants).every(Boolean)
      },
      path_invariants: invariants,
      details: {
        inputKind: kind,
        campaignId: params.campaignId,
        chainId: network.chainId.toString(),
        checkedAtBlock: latest.number
      }
    };
    await fs.mkdir(path.dirname(path.resolve(outFile)), { recursive: true });
    await fs.writeFile(path.resolve(outFile), `${JSON.stringify(payload, null, 2)}\n`, "utf8");
    if (!payload.pass) process.exitCode = 1;
  } finally {
    await conn.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
