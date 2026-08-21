import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  canonicalJson,
  createProtocolReceiptEnvelope,
  parseJsonStrict,
  sha256Bytes,
  validatePhaseBParams,
  validateProtocolReceiptEnvelope
} from "../../evm/scripts/lib/path-campaign.mjs";
import {
  buildSyntheticInteropChain
} from "./synthetic_path_campaign_receipts.mjs";

const pathHarness = path.resolve("ops/tests/synthetic_path_campaign_receipts.mjs");

test("synthetic PATH A -> THOUGHT -> PATH B chain uses exact production helpers", () => {
  const chain = buildSyntheticInteropChain();
  const aHash = sha256Bytes(Buffer.from(chain.phaseARaw));
  const thoughtHash = sha256Bytes(Buffer.from(chain.thoughtRaw));
  assert.equal(chain.thoughtEnvelope.input_receipt_sha256, aHash);
  assert.equal(chain.thoughtEnvelope.protocol_payload.payload.consumedPathPhaseA.payloadSha256,
    chain.phaseAEnvelope.protocol_payload.sha256);
  assert.equal(chain.phaseBEnvelope.input_receipt_sha256, thoughtHash);
  assert.equal(chain.phaseBEnvelope.protocol_payload.payload.linkedReceipts.thoughtProtocolPayloadSha256,
    chain.thoughtEnvelope.protocol_payload.sha256);
  validatePhaseBParams(chain.phaseBParams);
});

test("staged PATH-B consumes the exact THOUGHT harness envelope bytes", () => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "path-thought-staged-"));
  const pathADir = path.join(temporary, "path-a");
  const pathBDir = path.join(temporary, "path-b");
  const pathAResult = spawnSync(process.execPath, [
    pathHarness, "emit-path-a", "--out-dir", pathADir
  ], { encoding: "utf8", env: { ...process.env, PATH_CAMPAIGN_TEST_ONLY: "1" } });
  assert.equal(pathAResult.status, 0, pathAResult.stderr);
  const pathAFile = path.join(pathADir, "path-a-envelope.json");
  const thoughtPayloadFile = path.join(temporary, "thought-payload.json");
  const thoughtEnvelopeFile = path.join(temporary, "thought-envelope.json");
  const phaseARaw = fs.readFileSync(pathAFile, "utf8");
  const phaseAEnvelope = JSON.parse(phaseARaw);
  const phaseAPayload = phaseAEnvelope.protocol_payload.payload;

  const thoughtPayload = JSON.parse(fs.readFileSync(
    "/Users/bigu/Projects/THOUGHT/ops/integrated-campaign/examples/thought-deployment-receipt.example.json",
    "utf8"
  ));
  const pathAHash = sha256Bytes(Buffer.from(phaseARaw));
  Object.assign(thoughtPayload, {
    campaignId: phaseAEnvelope.campaign_id,
    environment: phaseAEnvelope.environment,
    chainId: phaseAEnvelope.chain_id,
    consumedPathPhaseAReceiptSha256: pathAHash,
    consumedPathPhaseA: {
      envelopeSha256: pathAHash,
      payloadSha256: phaseAEnvelope.protocol_payload.sha256
    },
    pathNft: phaseAPayload.pathNft.address
  });
  thoughtPayload.compatibility.pathNftImmutable = phaseAPayload.pathNft.address;
  fs.writeFileSync(thoughtPayloadFile, `${JSON.stringify(thoughtPayload, null, 2)}\n`);

  const result = spawnSync(process.execPath, [
    "/Users/bigu/Projects/THOUGHT/scripts/synthetic-thought-campaign-harness.mjs",
    "--path-envelope", pathAFile,
    "--thought-payload", thoughtPayloadFile,
    "--out", thoughtEnvelopeFile,
    "--campaign-id", phaseAEnvelope.campaign_id,
    "--environment", phaseAEnvelope.environment,
    "--chain-id", String(phaseAEnvelope.chain_id),
    "--path-bundle-digest", phaseAPayload.sourceBundleDigest,
    "--path-retained-authority", phaseAPayload.retainedAuthority.holder,
    "--path-nft", phaseAPayload.pathNft.address,
    "--thought-bundle-digest", thoughtPayload.bundleDigest,
    "--registry-owner", thoughtPayload.authorities.registryOwner,
    "--attestation-authority", thoughtPayload.authorities.attestationAuthority
  ], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);

  const exactThoughtRaw = fs.readFileSync(thoughtEnvelopeFile, "utf8");
  const pathBResult = spawnSync(process.execPath, [
    pathHarness, "emit-path-b",
    "--path-a-envelope", pathAFile,
    "--thought-envelope", thoughtEnvelopeFile,
    "--out-dir", pathBDir
  ], { encoding: "utf8", env: { ...process.env, PATH_CAMPAIGN_TEST_ONLY: "1" } });
  assert.equal(pathBResult.status, 0, pathBResult.stderr);
  const pathBParams = JSON.parse(fs.readFileSync(path.join(pathBDir, "path-b-params.json")));
  assert.equal(pathBParams.thoughtDeployment.receiptRaw, exactThoughtRaw);
  assert.equal(pathBParams.thoughtDeployment.receiptSha256,
    sha256Bytes(Buffer.from(exactThoughtRaw)));
});

test("JCS integer subset rejects floats, non-finite values, and unsafe integers", () => {
  assert.throws(() => canonicalJson({ value: 1.25 }), /floating-point/);
  assert.throws(() => canonicalJson({ value: Number.NaN }), /non-finite/);
  assert.throws(() => canonicalJson({ value: Number.MAX_SAFE_INTEGER + 1 }), /safe range/);
  assert.equal(canonicalJson({ z: "9007199254740992", a: 1 }),
    '{"a":1,"z":"9007199254740992"}');
  assert.throws(() => parseJsonStrict('{"value":1.25}'), /floating-point/);
  assert.throws(() => parseJsonStrict('{"value":1e2}'), /floating-point/);
  assert.throws(() => parseJsonStrict('{"value":9007199254740992}'), /safe range/);
  assert.throws(() => parseJsonStrict('{"value":1,"value":2}'), /duplicate object key/);
  assert.throws(() => canonicalJson({ value: "\ud800" }), /unpaired Unicode surrogate/);
});

test("payload or prior-receipt tampering fails closed", () => {
  const chain = buildSyntheticInteropChain();
  const payloadTamper = structuredClone(chain.phaseAEnvelope);
  payloadTamper.protocol_payload.payload.observedAtBlock = "999999";
  assert.throws(() => validateProtocolReceiptEnvelope(payloadTamper), /JCS SHA-256 mismatch/);

  const linkTamper = structuredClone(chain.phaseBEnvelope);
  linkTamper.input_receipt_sha256 = "f".repeat(64);
  assert.throws(() => validateProtocolReceiptEnvelope(linkTamper, {
    phaseId: "path-b",
    inputReceiptSha256: sha256Bytes(Buffer.from(chain.thoughtRaw))
  }), /prior receipt link mismatch/);
});

test("production descriptors never reference the synthetic harness", () => {
  for (const phase of ["path-a", "path-b"]) {
    const dir = path.resolve(`ops/campaign/${phase}`);
    const descriptor = JSON.parse(fs.readFileSync(path.join(dir, "CAMPAIGN-PHASE.json"), "utf8"));
    const paths = [
      ...Object.values(descriptor.entrypoints),
      ...descriptor.resume_checkpoints.flatMap((item) => [item.verifier, item.entrypoint])
    ];
    assert.equal(paths.some((entry) => entry.includes("synthetic")), false);
  }
});

test("test-only harness emits locally and requires an explicit guard", () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "path-campaign-interop-"));
  const chain = buildSyntheticInteropChain();
  fs.writeFileSync(path.join(temp, "path-a.json"), chain.phaseARaw);
  assert.equal(JSON.parse(fs.readFileSync(path.join(temp, "path-a.json"))).phase_id, "path-a");
  const refused = spawnSync(process.execPath, [
    pathHarness, "emit-path-a", "--out-dir", path.join(temp, "unguarded")
  ], { encoding: "utf8", env: { ...process.env, PATH_CAMPAIGN_TEST_ONLY: "" } });
  assert.notEqual(refused.status, 0);
  assert.match(refused.stderr, /PATH_CAMPAIGN_TEST_ONLY=1/);
});
