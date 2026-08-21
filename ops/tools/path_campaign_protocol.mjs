#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  assertFinalReceiptComplete,
  createProtocolReceiptEnvelope,
  parseJsonStrict,
  phaseAProtocolPayload,
  sha256Bytes,
  sha256Json,
  validatePhaseACheckpoint,
  validatePhaseAParams,
  validatePhaseBCheckpoint,
  validatePhaseBParams,
  validateProtocolReceiptEnvelope
} from "../../evm/scripts/lib/path-campaign.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

function fail(message) {
  throw new Error(`PATH_PROTOCOL_ENTRYPOINT_INVALID: ${message}`);
}

function env(name, { allowEmpty = false } = {}) {
  const value = process.env[name];
  if (value === undefined || (!allowEmpty && value === "")) fail(`missing ${name}`);
  return value;
}

function readJsonWithRaw(file, label) {
  const raw = fs.readFileSync(path.resolve(file), "utf8");
  try {
    return { raw, value: parseJsonStrict(raw, label) };
  } catch (error) {
    fail(error.message);
  }
}

function writeJsonAtomic(file, value) {
  const resolved = path.resolve(file);
  fs.mkdirSync(path.dirname(resolved), { recursive: true });
  const temporary = `${resolved}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, "utf8");
  fs.renameSync(temporary, resolved);
}

function context(phaseId) {
  const phase = env("SIGNING_OS_CAMPAIGN_PHASE_ID");
  if (phase !== phaseId) fail(`phase mismatch: expected ${phaseId}, got ${phase}`);
  const campaignId = env("SIGNING_OS_CAMPAIGN_ID");
  const environment = env("SIGNING_OS_CAMPAIGN_ENVIRONMENT");
  const chainIdText = env("SIGNING_OS_CAMPAIGN_CHAIN_ID");
  if (!/^[1-9][0-9]*$/.test(chainIdText)) fail("campaign chain id must be a positive integer");
  const chainId = Number(chainIdText);
  if (!Number.isSafeInteger(chainId)) fail("campaign chain id is outside the safe integer range");
  return {
    phaseId,
    campaignId,
    environment,
    chainId,
    sourceBundleDigest: env("SIGNING_OS_CAMPAIGN_BUNDLE_SHA256"),
    runDir: path.resolve(env("SIGNING_OS_CAMPAIGN_RUN_DIR")),
    inputReceipt: env("SIGNING_OS_CAMPAIGN_INPUT_RECEIPT", { allowEmpty: phaseId === "path-a" }),
    outputReceipt: path.resolve(env("SIGNING_OS_CAMPAIGN_OUTPUT_RECEIPT")),
    paramsFile: path.resolve(env("PATH_CAMPAIGN_PARAMS_FILE"))
  };
}

function phaseBParams(ctx) {
  const params = readJsonWithRaw(ctx.paramsFile, "PATH Phase B params").value;
  const input = readJsonWithRaw(ctx.inputReceipt, "THOUGHT input envelope");
  validateProtocolReceiptEnvelope(input.value, {
    phaseId: "thought",
    campaignId: ctx.campaignId,
    environment: ctx.environment,
    chainId: ctx.chainId
  });
  const exactThought = {
    receiptSha256: sha256Bytes(Buffer.from(input.raw, "utf8")),
    receiptRaw: input.raw,
    receipt: input.value
  };
  if (params.thoughtDeployment) {
    if (params.thoughtDeployment.receiptSha256 !== exactThought.receiptSha256
        || params.thoughtDeployment.receiptRaw !== exactThought.receiptRaw
        || sha256Json(params.thoughtDeployment.receipt) !== sha256Json(exactThought.receipt)) {
      fail("Phase B params contain a THOUGHT receipt different from the Signing OS input receipt");
    }
  } else {
    params.thoughtDeployment = exactThought;
  }
  validatePhaseBParams(params);
  return params;
}

function preflight(phaseId) {
  const ctx = context(phaseId);
  if (phaseId === "path-a") {
    if (ctx.inputReceipt !== "") fail("PATH Phase A must not receive an input receipt");
    const params = validatePhaseAParams(readJsonWithRaw(ctx.paramsFile, "PATH Phase A params").value);
    if (params.campaignId !== ctx.campaignId || params.environment !== ctx.environment
        || BigInt(params.expectedChainId) !== BigInt(ctx.chainId)) {
      fail("PATH Phase A params do not match Signing OS campaign identity");
    }
  } else {
    const params = phaseBParams(ctx);
    if (params.campaignId !== ctx.campaignId || params.environment !== ctx.environment
        || BigInt(params.expectedChainId) !== BigInt(ctx.chainId)) {
      fail("PATH Phase B params do not match Signing OS campaign identity");
    }
  }
  console.log(`PATH ${phaseId} protocol preflight passed`);
}

function hardhatNetwork(environment) {
  return environment === "mainnet" ? "mainnet" : "sepolia";
}

function execute(phaseId, { resume = false } = {}) {
  const ctx = context(phaseId);
  preflight(phaseId);
  fs.mkdirSync(ctx.runDir, { recursive: true });
  const ownerPayloadFile = path.join(ctx.runDir, `${phaseId}-owner-payload.json`);
  const checkpointFile = path.join(ctx.runDir, `${phaseId}-checkpoint.json`);
  let deployParamsFile = ctx.paramsFile;
  if (phaseId === "path-b") {
    deployParamsFile = path.join(ctx.runDir, "path-b-exact-params.json");
    writeJsonAtomic(deployParamsFile, phaseBParams(ctx));
  }
  if (resume && !fs.existsSync(checkpointFile)) fail(`resume requested without ${checkpointFile}`);

  const script = phaseId === "path-a"
    ? path.join(root, "evm/scripts/deploy-campaign-phase-a.js")
    : path.join(root, "evm/scripts/deploy-campaign-phase-b.js");
  const result = spawnSync(
    "npm",
    ["--prefix", path.join(root, "evm"), "exec", "--", "hardhat", "run", script,
      "--network", hardhatNetwork(ctx.environment)],
    {
      cwd: root,
      env: {
        ...process.env,
        DEPLOY_PARAMS_FILE: deployParamsFile,
        DEPLOY_OUT_FILE: ownerPayloadFile,
        PATH_CAMPAIGN_CHECKPOINT_FILE: checkpointFile,
        PATH_CAMPAIGN_SOURCE_BUNDLE_DIGEST: ctx.sourceBundleDigest
      },
      encoding: "utf8"
    }
  );
  process.stdout.write(result.stdout ?? "");
  process.stderr.write(result.stderr ?? "");
  if (result.status !== 0) fail(`owner deployment entrypoint exited ${result.status}`);

  const payload = readJsonWithRaw(ownerPayloadFile, "owner payload").value;
  let inputReceiptSha256 = "";
  if (phaseId === "path-b") {
    const input = readJsonWithRaw(ctx.inputReceipt, "THOUGHT input envelope");
    inputReceiptSha256 = sha256Bytes(Buffer.from(input.raw, "utf8"));
  }
  const envelope = createProtocolReceiptEnvelope({
    phaseId,
    campaignId: ctx.campaignId,
    environment: ctx.environment,
    chainId: ctx.chainId,
    inputReceiptSha256,
    payload
  });
  writeJsonAtomic(ctx.outputReceipt, envelope);
  console.log(`PATH ${phaseId} protocol receipt=${ctx.outputReceipt}`);
}

function postconditions(phaseId) {
  const ctx = context(phaseId);
  const output = readJsonWithRaw(ctx.outputReceipt, "PATH output envelope");
  const expected = {
    phaseId,
    campaignId: ctx.campaignId,
    environment: ctx.environment,
    chainId: ctx.chainId
  };
  if (phaseId === "path-b") {
    const input = readJsonWithRaw(ctx.inputReceipt, "THOUGHT input envelope");
    expected.inputReceiptSha256 = sha256Bytes(Buffer.from(input.raw, "utf8"));
  }
  validateProtocolReceiptEnvelope(output.value, expected);
  if (phaseId === "path-b") {
    const params = phaseBParams(ctx);
    const payload = output.value.protocol_payload.payload;
    assertFinalReceiptComplete(payload, { campaignId: ctx.campaignId, chainId: ctx.chainId });
    if (payload.linkedReceipts.pathPhaseAReceiptSha256 !== params.pathPhaseA.receiptSha256
        || payload.linkedReceipts.thoughtDeploymentReceiptSha256
          !== params.thoughtDeployment.receiptSha256
        || payload.linkedReceipts.pathPhaseAProtocolPayloadSha256
          !== params.pathPhaseA.receipt.protocol_payload.sha256
        || payload.linkedReceipts.thoughtProtocolPayloadSha256
          !== params.thoughtDeployment.receipt.protocol_payload.sha256) {
      fail("PATH Phase B final payload does not preserve exact envelope and payload links");
    }
  }
  console.log(`PATH ${phaseId} protocol postconditions passed`);
}

function verifyCheckpoint(phaseId) {
  const ctx = context(phaseId);
  const checkpointFile = path.join(ctx.runDir, `${phaseId}-checkpoint.json`);
  const checkpoint = readJsonWithRaw(checkpointFile, `${phaseId} checkpoint`).value;
  if (phaseId === "path-a") {
    const params = validatePhaseAParams(readJsonWithRaw(ctx.paramsFile, "PATH Phase A params").value);
    validatePhaseACheckpoint(checkpoint, {
      campaignId: ctx.campaignId,
      environment: ctx.environment,
      chainId: ctx.chainId,
      paramsSha256: sha256Json(params),
      sourceBundleDigest: ctx.sourceBundleDigest
    });
  } else {
    const params = phaseBParams(ctx);
    validatePhaseBCheckpoint(checkpoint, {
      campaignId: ctx.campaignId,
      environment: ctx.environment,
      chainId: ctx.chainId,
      paramsSha256: sha256Json(params),
      sourceBundleDigest: ctx.sourceBundleDigest,
      pathPhaseAReceiptSha256: params.pathPhaseA.receiptSha256,
      thoughtDeploymentReceiptSha256: params.thoughtDeployment.receiptSha256
    });
  }
  console.log(`PATH ${phaseId} checkpoint verified`);
}

const [command, phaseId] = process.argv.slice(2);
if (!["path-a", "path-b"].includes(phaseId)) fail("phase must be path-a or path-b");
if (command === "preflight") preflight(phaseId);
else if (command === "execute") execute(phaseId);
else if (command === "postconditions") postconditions(phaseId);
else if (command === "verify-checkpoint") verifyCheckpoint(phaseId);
else if (command === "resume") {
  verifyCheckpoint(phaseId);
  execute(phaseId, { resume: true });
} else fail("command must be preflight, execute, postconditions, verify-checkpoint, or resume");
