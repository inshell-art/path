#!/usr/bin/env node

// Test-only fixture harness. Production CAMPAIGN-PHASE descriptors must never reference this file.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  createProtocolReceiptEnvelope,
  parseJsonStrict,
  sha256Bytes,
  sha256Json,
  validatePhaseBParams,
  validateProtocolReceiptEnvelope
} from "../../evm/scripts/lib/path-campaign.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const clone = (value) => structuredClone(value);
const jsonBytes = (value) => `${JSON.stringify(value, null, 2)}\n`;
const read = (file) => parseJsonStrict(
  fs.readFileSync(path.join(root, file), "utf8"),
  file
);
const parseRaw = (raw, label) => {
  try {
    return parseJsonStrict(raw, label);
  } catch (error) {
    throw new Error(error.message);
  }
};

export function buildSyntheticPathA() {
  const campaignId = "synthetic-path-interop-20260821";
  const environment = "internal-sepolia";
  const chainId = 11155111;
  const phaseAPayload = clone(read("ops/campaign/examples/path-phase-a-receipt.example.json"));
  Object.assign(phaseAPayload, { campaignId, environment, chainId: String(chainId) });
  phaseAPayload.pathRelease.artifactManifestSha256 =
    "a81355b459b40faea894cf1dfb7f484765a7ec62672039dd62d58a3a52849921";
  phaseAPayload.retainedAuthority.signerRef = "SYNTHETIC_NO_SIGNER";
  const phaseAEnvelope = createProtocolReceiptEnvelope({
    phaseId: "path-a", campaignId, environment, chainId, payload: phaseAPayload
  });
  const phaseARaw = jsonBytes(phaseAEnvelope);
  const phaseAParams = clone(read("ops/campaign/examples/path-phase-a-params.example.json"));
  Object.assign(phaseAParams, { campaignId, environment, expectedChainId: String(chainId) });
  phaseAParams.pathRelease = phaseAPayload.pathRelease;
  phaseAParams.retainedAuthority.signerRef = "SYNTHETIC_NO_SIGNER";
  return { campaignId, environment, chainId, phaseAPayload, phaseAEnvelope, phaseARaw, phaseAParams };
}

function syntheticThoughtForSelfContainedTests(pathA) {
  const phaseAEnvelopeSha256 = sha256Bytes(Buffer.from(pathA.phaseARaw));
  const thoughtPayload = clone(read(
    "../THOUGHT/ops/integrated-campaign/examples/thought-deployment-receipt.example.json"
  ));
  Object.assign(thoughtPayload, {
    campaignId: pathA.campaignId,
    environment: pathA.environment,
    chainId: pathA.chainId,
    consumedPathPhaseAReceiptSha256: phaseAEnvelopeSha256,
    consumedPathPhaseA: {
      envelopeSha256: phaseAEnvelopeSha256,
      payloadSha256: pathA.phaseAEnvelope.protocol_payload.sha256
    },
    pathNft: pathA.phaseAPayload.pathNft.address
  });
  thoughtPayload.compatibility.pathNftImmutable = pathA.phaseAPayload.pathNft.address;
  const thoughtEnvelope = createProtocolReceiptEnvelope({
    phaseId: "thought",
    campaignId: pathA.campaignId,
    environment: pathA.environment,
    chainId: pathA.chainId,
    inputReceiptSha256: phaseAEnvelopeSha256,
    payload: thoughtPayload
  });
  return { thoughtEnvelope, thoughtRaw: jsonBytes(thoughtEnvelope) };
}

/**
 * Staged PATH-B mode. `thoughtRaw` is accepted exactly as emitted by THOUGHT's
 * harness. This function never constructs, normalizes, or rewrites that envelope.
 */
export function buildSyntheticPathB({ phaseARaw, thoughtRaw }) {
  if (typeof phaseARaw !== "string" || typeof thoughtRaw !== "string") {
    throw new Error("staged PATH-B requires exact PATH-A and THOUGHT raw envelope bytes");
  }
  const phaseAEnvelope = parseRaw(phaseARaw, "PATH-A envelope");
  const thoughtEnvelope = parseRaw(thoughtRaw, "THOUGHT envelope");
  validateProtocolReceiptEnvelope(phaseAEnvelope, { phaseId: "path-a" });
  const phaseAEnvelopeSha256 = sha256Bytes(Buffer.from(phaseARaw));
  validateProtocolReceiptEnvelope(thoughtEnvelope, {
    phaseId: "thought",
    campaignId: phaseAEnvelope.campaign_id,
    environment: phaseAEnvelope.environment,
    chainId: phaseAEnvelope.chain_id,
    inputReceiptSha256: phaseAEnvelopeSha256
  });
  const phaseAPayload = phaseAEnvelope.protocol_payload.payload;
  const thoughtPayload = thoughtEnvelope.protocol_payload.payload;
  if (thoughtPayload.consumedPathPhaseAReceiptSha256 !== phaseAEnvelopeSha256
      || thoughtPayload.consumedPathPhaseA.envelopeSha256 !== phaseAEnvelopeSha256
      || thoughtPayload.consumedPathPhaseA.payloadSha256
        !== phaseAEnvelope.protocol_payload.sha256
      || thoughtPayload.pathNft.toLowerCase() !== phaseAPayload.pathNft.address.toLowerCase()) {
    throw new Error("THOUGHT envelope did not consume the exact supplied PATH-A envelope and payload");
  }
  const thoughtEnvelopeSha256 = sha256Bytes(Buffer.from(thoughtRaw));

  const phaseBPayload = clone(read("ops/campaign/examples/path-phase-b-final-receipt.example.json"));
  Object.assign(phaseBPayload, {
    campaignId: phaseAEnvelope.campaign_id,
    environment: phaseAEnvelope.environment,
    chainId: String(phaseAEnvelope.chain_id)
  });
  phaseBPayload.releaseMatrix = {
    path: phaseAPayload.pathRelease,
    thought: thoughtPayload.thoughtRelease
  };
  phaseBPayload.linkedReceipts = {
    pathPhaseAReceiptSha256: phaseAEnvelopeSha256,
    thoughtDeploymentReceiptSha256: thoughtEnvelopeSha256,
    pathPhaseAProtocolPayloadSha256: phaseAEnvelope.protocol_payload.sha256,
    thoughtProtocolPayloadSha256: thoughtEnvelope.protocol_payload.sha256
  };
  phaseBPayload.contracts.pathNft = phaseAPayload.pathNft;
  const thoughtDeployment = thoughtPayload.deployments.find((entry) => entry.name === "thoughtNft");
  phaseBPayload.contracts.thoughtNft = {
    address: thoughtPayload.contracts.thoughtNft,
    deploymentTx: thoughtDeployment.transaction,
    blockNumber: String(thoughtDeployment.block),
    runtimeBytecodeHash: thoughtDeployment.runtimeBytecodeHash
  };
  phaseBPayload.movementStates.THOUGHT.minter = thoughtPayload.contracts.thoughtNft;
  const phaseBEnvelope = createProtocolReceiptEnvelope({
    phaseId: "path-b",
    campaignId: phaseAEnvelope.campaign_id,
    environment: phaseAEnvelope.environment,
    chainId: phaseAEnvelope.chain_id,
    inputReceiptSha256: thoughtEnvelopeSha256,
    payload: phaseBPayload
  });
  const phaseBRaw = jsonBytes(phaseBEnvelope);

  const phaseBParams = clone(read("ops/campaign/examples/path-phase-b-config.example.json"));
  Object.assign(phaseBParams, {
    campaignId: phaseAEnvelope.campaign_id,
    environment: phaseAEnvelope.environment,
    expectedChainId: String(phaseAEnvelope.chain_id)
  });
  phaseBParams.releaseMatrix = phaseBPayload.releaseMatrix;
  phaseBParams.pathPhaseA = {
    receiptSha256: phaseAEnvelopeSha256,
    receiptRaw: phaseARaw,
    receipt: phaseAEnvelope
  };
  phaseBParams.thoughtDeployment = {
    receiptSha256: thoughtEnvelopeSha256,
    receiptRaw: thoughtRaw,
    receipt: thoughtEnvelope
  };
  phaseBParams.openTimeAuthorization.environment = phaseAEnvelope.environment;
  phaseBParams.openTimeAuthorization.authorizationDigest = sha256Json({
    campaignId: phaseAEnvelope.campaign_id,
    environment: phaseAEnvelope.environment,
    authorizedOpenTime: String(phaseBParams.openTimeAuthorization.authorizedOpenTime),
    minimumLeadTimeSec: String(phaseBParams.openTimeAuthorization.minimumLeadTimeSec),
    authorizedAt: String(phaseBParams.openTimeAuthorization.authorizedAt),
    expiresAt: String(phaseBParams.openTimeAuthorization.expiresAt),
    authorizerRef: phaseBParams.openTimeAuthorization.authorizerRef,
    authorizationId: phaseBParams.openTimeAuthorization.authorizationId
  });

  validatePhaseBParams(phaseBParams);
  validateProtocolReceiptEnvelope(phaseBEnvelope, {
    phaseId: "path-b", inputReceiptSha256: thoughtEnvelopeSha256
  });
  return {
    phaseAEnvelope, phaseARaw, thoughtEnvelope, thoughtRaw,
    phaseBEnvelope, phaseBRaw, phaseBParams
  };
}

export function buildSyntheticInteropChain() {
  const pathA = buildSyntheticPathA();
  const thought = syntheticThoughtForSelfContainedTests(pathA);
  return {
    ...pathA,
    ...thought,
    ...buildSyntheticPathB({ phaseARaw: pathA.phaseARaw, thoughtRaw: thought.thoughtRaw })
  };
}

function requiredArg(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || !process.argv[index + 1]) throw new Error(`Missing ${name}`);
  return process.argv[index + 1];
}

function writePathA(out, pathA) {
  fs.mkdirSync(out, { recursive: true });
  fs.writeFileSync(path.join(out, "path-a-envelope.json"), pathA.phaseARaw, { flag: "wx" });
  fs.writeFileSync(path.join(out, "path-a-params.json"), jsonBytes(pathA.phaseAParams), { flag: "wx" });
}

function writePathB(out, pathB) {
  fs.mkdirSync(out, { recursive: true });
  fs.writeFileSync(path.join(out, "path-b-envelope.json"), pathB.phaseBRaw, { flag: "wx" });
  fs.writeFileSync(path.join(out, "path-b-params.json"), jsonBytes(pathB.phaseBParams), { flag: "wx" });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.env.PATH_CAMPAIGN_TEST_ONLY !== "1") {
    throw new Error("Refusing synthetic receipt generation without PATH_CAMPAIGN_TEST_ONLY=1");
  }
  const command = process.argv[2];
  const out = path.resolve(requiredArg("--out-dir"));
  if (command === "emit-path-a") {
    writePathA(out, buildSyntheticPathA());
  } else if (command === "emit-path-b") {
    const phaseARaw = fs.readFileSync(path.resolve(requiredArg("--path-a-envelope")), "utf8");
    const thoughtRaw = fs.readFileSync(path.resolve(requiredArg("--thought-envelope")), "utf8");
    writePathB(out, buildSyntheticPathB({ phaseARaw, thoughtRaw }));
  } else if (command === "emit-chain") {
    const chain = buildSyntheticInteropChain();
    writePathA(out, chain);
    fs.writeFileSync(path.join(out, "thought-envelope.json"), chain.thoughtRaw, { flag: "wx" });
    writePathB(out, chain);
  } else {
    throw new Error("Command must be emit-path-a, emit-path-b, or emit-chain");
  }
  console.log(out);
}
