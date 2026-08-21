#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import {
  PHASE_B_ACTION_ORDER,
  PHASE_B_CHECKPOINT_ACTIONS,
  assertFinalReceiptComplete,
  canonicalJson,
  createProtocolReceiptEnvelope,
  parseJsonStrict,
  sha256Bytes,
  sha256Json,
  validatePhaseACheckpoint,
  validatePhaseAParams,
  validatePhaseAReceipt,
  validatePhaseBCheckpoint,
  validatePhaseBParams,
  validateProtocolReceiptEnvelope,
  validateThoughtReceipt
} from "../../evm/scripts/lib/path-campaign.mjs";

function usage() {
  console.error(`Usage:
  node ops/tools/path_campaign.mjs verify-phase-a --receipt <file>
  node ops/tools/path_campaign.mjs verify-phase-a-params --params <file>
  node ops/tools/path_campaign.mjs verify-phase-a-checkpoint --checkpoint <file> [--params <file>] [--source-bundle-digest <sha256>]
  node ops/tools/path_campaign.mjs verify-thought --receipt <file>
  node ops/tools/path_campaign.mjs verify-envelope --receipt <file> [--phase <path-a|thought|path-b>]
  node ops/tools/path_campaign.mjs wrap-owner-payload --phase <path-a|path-b> --payload <file> --out <file> [--input <file>]
  node ops/tools/path_campaign.mjs prepare-phase-b --config <file> --phase-a <file> --thought <file> --out <file>
  node ops/tools/path_campaign.mjs verify-phase-b-input --params <file> [--latest-block-timestamp <unix>]
  node ops/tools/path_campaign.mjs verify-phase-b-checkpoint --checkpoint <file> [--params <file>] [--source-bundle-digest <sha256>]
  node ops/tools/path_campaign.mjs verify-final --receipt <file>
  node ops/tools/path_campaign.mjs digest-open-time-authorization --input <file>
  node ops/tools/path_campaign.mjs show-action-order`);
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const item = argv[index];
    if (!item.startsWith("--")) continue;
    const key = item.slice(2);
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) throw new Error(`Missing value for --${key}`);
    args[key] = value;
    index += 1;
  }
  return args;
}

async function readJson(file, label) {
  if (!file) throw new Error(`Missing ${label}`);
  return parseJsonStrict(await fs.readFile(path.resolve(file), "utf8"), label);
}

async function readJsonWithRaw(file, label) {
  if (!file) throw new Error(`Missing ${label}`);
  const raw = await fs.readFile(path.resolve(file), "utf8");
  return { raw, value: parseJsonStrict(raw, label) };
}

async function writeJson(file, value) {
  const resolved = path.resolve(file);
  await fs.mkdir(path.dirname(resolved), { recursive: true });
  await fs.writeFile(resolved, `${JSON.stringify(value, null, 2)}\n`, "utf8");
  return resolved;
}

function openTimeAuthorizationPayload(campaignId, open) {
  return {
    campaignId,
    environment: open.environment,
    authorizedOpenTime: String(open.authorizedOpenTime),
    minimumLeadTimeSec: String(open.minimumLeadTimeSec),
    authorizedAt: String(open.authorizedAt),
    expiresAt: String(open.expiresAt),
    authorizerRef: open.authorizerRef,
    authorizationId: open.authorizationId
  };
}

async function main() {
  const [command, ...rest] = process.argv.slice(2);
  const args = parseArgs(rest);
  if (!command) {
    usage();
    process.exitCode = 2;
    return;
  }

  if (command === "verify-phase-a") {
    const receipt = await readJson(args.receipt, "--receipt");
    validatePhaseAReceipt(receipt);
    console.log(`phase_a_receipt_sha256=${sha256Json(receipt)}`);
    console.log("status=pass");
    return;
  }

  if (command === "verify-phase-a-params") {
    const params = await readJson(args.params, "--params");
    validatePhaseAParams(params);
    console.log(`phase_a_params_sha256=${sha256Json(params)}`);
    console.log("status=pass");
    return;
  }

  if (command === "verify-phase-a-checkpoint") {
    const checkpoint = await readJson(args.checkpoint, "--checkpoint");
    const expected = {};
    if (args.params) {
      const params = await readJson(args.params, "--params");
      validatePhaseAParams(params);
      Object.assign(expected, {
        campaignId: params.campaignId,
        environment: params.environment,
        chainId: params.expectedChainId,
        paramsSha256: sha256Json(params)
      });
    }
    if (args["source-bundle-digest"]) {
      expected.sourceBundleDigest = args["source-bundle-digest"];
    }
    validatePhaseACheckpoint(checkpoint, expected);
    console.log(`phase_a_checkpoint_sha256=${sha256Json(checkpoint)}`);
    console.log("next_action=EMIT_PHASE_A_RECEIPT");
    console.log("status=pass");
    return;
  }

  if (command === "verify-thought") {
    const receipt = await readJson(args.receipt, "--receipt");
    validateThoughtReceipt(receipt);
    console.log(`thought_receipt_sha256=${sha256Json(receipt)}`);
    console.log("status=pass");
    return;
  }

  if (command === "verify-envelope") {
    const { raw, value } = await readJsonWithRaw(args.receipt, "--receipt");
    validateProtocolReceiptEnvelope(value, args.phase ? { phaseId: args.phase } : {});
    console.log(`receipt_file_sha256=${sha256Bytes(Buffer.from(raw, "utf8"))}`);
    console.log(`protocol_payload_sha256=${value.protocol_payload.sha256}`);
    console.log("status=pass");
    return;
  }

  if (command === "wrap-owner-payload") {
    if (!args.phase || !["path-a", "path-b"].includes(args.phase)) {
      throw new Error("--phase must be path-a or path-b");
    }
    if (!args.out) throw new Error("Missing --out");
    const payload = await readJson(args.payload, "--payload");
    let inputReceiptSha256 = "";
    if (args.phase === "path-b") {
      const input = await readJsonWithRaw(args.input, "--input");
      validateProtocolReceiptEnvelope(input.value, { phaseId: "thought" });
      inputReceiptSha256 = sha256Bytes(Buffer.from(input.raw, "utf8"));
    }
    const envelope = createProtocolReceiptEnvelope({
      phaseId: args.phase,
      campaignId: payload.campaignId,
      environment: payload.environment,
      chainId: payload.chainId,
      inputReceiptSha256,
      payload
    });
    const resolved = await writeJson(args.out, envelope);
    console.log(`protocol_receipt=${resolved}`);
    console.log(`protocol_payload_sha256=${envelope.protocol_payload.sha256}`);
    return;
  }

  if (command === "prepare-phase-b") {
    const config = await readJson(args.config, "--config");
    const phaseA = await readJsonWithRaw(args["phase-a"], "--phase-a");
    const thought = await readJsonWithRaw(args.thought, "--thought");
    if (!args.out) throw new Error("Missing --out");
    validateProtocolReceiptEnvelope(phaseA.value, { phaseId: "path-a" });
    validateProtocolReceiptEnvelope(thought.value, {
      phaseId: "thought",
      inputReceiptSha256: sha256Bytes(Buffer.from(phaseA.raw, "utf8"))
    });
    const params = {
      ...config,
      pathPhaseA: {
        receiptSha256: sha256Bytes(Buffer.from(phaseA.raw, "utf8")),
        receiptRaw: phaseA.raw,
        receipt: phaseA.value
      },
      thoughtDeployment: {
        receiptSha256: sha256Bytes(Buffer.from(thought.raw, "utf8")),
        receiptRaw: thought.raw,
        receipt: thought.value
      }
    };
    validatePhaseBParams(params);
    const resolved = await writeJson(args.out, params);
    console.log(`phase_b_params=${resolved}`);
    console.log(`phase_a_receipt_sha256=${params.pathPhaseA.receiptSha256}`);
    console.log(`thought_receipt_sha256=${params.thoughtDeployment.receiptSha256}`);
    return;
  }

  if (command === "verify-phase-b-input") {
    const params = await readJson(args.params, "--params");
    const options = args["latest-block-timestamp"] === undefined
      ? {}
      : { latestBlockTimestamp: args["latest-block-timestamp"] };
    validatePhaseBParams(params, options);
    console.log(`phase_b_params_sha256=${sha256Json(params)}`);
    console.log("status=pass");
    return;
  }

  if (command === "verify-phase-b-checkpoint") {
    const checkpoint = await readJson(args.checkpoint, "--checkpoint");
    const expected = {};
    if (args.params) {
      const params = await readJson(args.params, "--params");
      validatePhaseBParams(params);
      Object.assign(expected, {
        campaignId: params.campaignId,
        environment: params.environment,
        chainId: params.expectedChainId,
        paramsSha256: sha256Json(params),
        pathPhaseAReceiptSha256: params.pathPhaseA.receiptSha256,
        thoughtDeploymentReceiptSha256: params.thoughtDeployment.receiptSha256
      });
    }
    if (args["source-bundle-digest"]) {
      expected.sourceBundleDigest = args["source-bundle-digest"];
    }
    validatePhaseBCheckpoint(checkpoint, expected);
    const nextAction = PHASE_B_CHECKPOINT_ACTIONS[checkpoint.completedActions.length] ?? "FINAL_RECEIPT";
    console.log(`phase_b_checkpoint_sha256=${sha256Json(checkpoint)}`);
    console.log(`completed_actions=${checkpoint.completedActions.length}`);
    console.log(`next_action=${nextAction}`);
    console.log("status=pass");
    return;
  }

  if (command === "verify-final") {
    const receipt = await readJson(args.receipt, "--receipt");
    assertFinalReceiptComplete(receipt);
    console.log(`final_receipt_sha256=${sha256Json(receipt)}`);
    console.log("status=pass");
    return;
  }

  if (command === "digest-open-time-authorization") {
    const input = await readJson(args.input, "--input");
    const payload = openTimeAuthorizationPayload(input.campaignId, input.openTimeAuthorization);
    console.log(`authorization_digest=${sha256Json(payload)}`);
    console.log(`canonical_payload=${canonicalJson(payload)}`);
    return;
  }

  if (command === "show-action-order") {
    PHASE_B_ACTION_ORDER.forEach((action, index) => console.log(`${index + 1}. ${action}`));
    return;
  }

  usage();
  process.exitCode = 2;
}

main().catch((error) => {
  console.error(error.message ?? error);
  process.exitCode = 1;
});
