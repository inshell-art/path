import { createHash } from "node:crypto";

export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
export const PATH_PHASE_A_KIND = "path_campaign_phase_a_receipt";
export const THOUGHT_RECEIPT_KIND = "inshell.thought.deployment.receipt.v1";
export const PATH_PHASE_B_KIND = "path_campaign_phase_b_final_receipt";

export const PROTOCOL_RECEIPT_ENVELOPE_SCHEMA =
  "inshell.deployment.protocol-receipt-envelope.v1";
export const PROTOCOL_CANONICALIZATION = "rfc8785-jcs";
export const PROTOCOL_PHASE_IDENTITIES = Object.freeze({
  "path-a": Object.freeze({
    receiptType: "inshell.path.phase-a.receipt.v1",
    owner: "path",
    schemaId: "inshell.path.deployment.phase-a.receipt.v1"
  }),
  thought: Object.freeze({
    receiptType: "inshell.thought.deployment.receipt.v1",
    owner: "thought",
    schemaId: "inshell.thought.deployment.receipt.v1"
  }),
  "path-b": Object.freeze({
    receiptType: "inshell.path.phase-b.final-receipt.v1",
    owner: "path",
    schemaId: "inshell.path.deployment.phase-b.final-receipt.v1"
  })
});

export const PHASE_A_PERMITTED_ACTIONS = Object.freeze([
  "SET_THOUGHT_MOVEMENT",
  "FREEZE_THOUGHT_MOVEMENT",
  "SET_WILL_MOVEMENT",
  "FREEZE_WILL_MOVEMENT",
  "SET_AWA_MOVEMENT",
  "FREEZE_AWA_MOVEMENT",
  "DEPLOY_AND_WIRE_PUBLIC_SALE",
  "FREEZE_PUBLIC_MINTER",
  "GRANT_FINAL_ROLES",
  "RENOUNCE_DEPLOYER_ADMIN"
]);

export const PHASE_B_ACTION_ORDER = Object.freeze([
  "VERIFY_PHASE_A_RECEIPT_AND_ONCHAIN_CHECKPOINT",
  "VERIFY_THOUGHT_RECEIPT_AND_PATH_BINDING",
  "SET_THOUGHT_MOVEMENT",
  "VERIFY_THOUGHT_MOVEMENT",
  "FREEZE_THOUGHT_MOVEMENT",
  "VERIFY_THOUGHT_MOVEMENT_FROZEN",
  "SET_WILL_MOVEMENT",
  "VERIFY_WILL_MOVEMENT",
  "FREEZE_WILL_MOVEMENT",
  "VERIFY_WILL_MOVEMENT_FROZEN",
  "SET_AWA_MOVEMENT",
  "VERIFY_AWA_MOVEMENT",
  "FREEZE_AWA_MOVEMENT",
  "VERIFY_AWA_MOVEMENT_FROZEN",
  "DEPLOY_PATH_PULSE_ADAPTER",
  "DEPLOY_PULSE_AUCTION_WITH_AUTHORIZED_OPEN_TIME",
  "SET_ADAPTER_AUCTION",
  "FREEZE_ADAPTER_WIRING",
  "GRANT_PUBLIC_MINTER_ROLE_TO_ADAPTER",
  "FREEZE_PUBLIC_MINTER_TO_ADAPTER",
  "GRANT_RESERVED_ROLE_TO_SPARK_ISSUER",
  "GRANT_DEFAULT_ADMIN_TO_FINAL_ADMIN",
  "TRANSFER_ADAPTER_OWNERSHIP_TO_FINAL_ADMIN",
  "RENOUNCE_DEPLOYER_DEFAULT_ADMIN",
  "VERIFY_COMBINED_POSTCONDITIONS"
]);

export const PHASE_B_CHECKPOINT_ACTIONS = Object.freeze([
  "SET_THOUGHT_MOVEMENT",
  "FREEZE_THOUGHT_MOVEMENT",
  "SET_WILL_MOVEMENT",
  "FREEZE_WILL_MOVEMENT",
  "SET_AWA_MOVEMENT",
  "FREEZE_AWA_MOVEMENT",
  "DEPLOY_PATH_PULSE_ADAPTER",
  "DEPLOY_PULSE_AUCTION_WITH_AUTHORIZED_OPEN_TIME",
  "SET_ADAPTER_AUCTION",
  "FREEZE_ADAPTER_WIRING",
  "GRANT_PUBLIC_MINTER_ROLE_TO_ADAPTER",
  "FREEZE_PUBLIC_MINTER_TO_ADAPTER",
  "GRANT_RESERVED_ROLE_TO_SPARK_ISSUER",
  "GRANT_DEFAULT_ADMIN_TO_FINAL_ADMIN",
  "TRANSFER_ADAPTER_OWNERSHIP_TO_FINAL_ADMIN",
  "RENOUNCE_DEPLOYER_DEFAULT_ADMIN"
]);

const ADDRESS_RE = /^0x[0-9a-fA-F]{40}$/;
const EVM_HASH_RE = /^0x[0-9a-fA-F]{64}$/;
const SHA256_RE = /^[0-9a-f]{64}$/;
const COMMIT_RE = /^[0-9a-f]{40}$/;
const PLACEHOLDER_RE = /(0xYour|<TODO>|REPLACE_ME|placeholder|deadbeef)/i;
const ENVIRONMENTS = new Set(["internal-sepolia", "public-beta-sepolia", "mainnet", "devnet"]);
const ENVELOPE_ENVIRONMENTS = new Set(["internal-sepolia", "public-beta-sepolia", "mainnet"]);
const SAFE_JSON_INTEGER = Number.MAX_SAFE_INTEGER;

function fail(message) {
  throw new Error(`PATH_CAMPAIGN_INVALID: ${message}`);
}

function assertWellFormedUnicode(value, label) {
  for (let index = 0; index < value.length; index += 1) {
    const unit = value.charCodeAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const next = value.charCodeAt(index + 1);
      if (!(next >= 0xdc00 && next <= 0xdfff)) fail(`${label} contains an unpaired Unicode surrogate`);
      index += 1;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      fail(`${label} contains an unpaired Unicode surrogate`);
    }
  }
}

function assertJcsJsonValue(value, label = "protocol payload") {
  if (value === null || typeof value === "boolean") return;
  if (typeof value === "string") {
    assertWellFormedUnicode(value, label);
    return;
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value) || !Number.isInteger(value)) {
      fail(`${label} contains a floating-point or non-finite JSON number`);
    }
    if (!Number.isSafeInteger(value) || Math.abs(value) > SAFE_JSON_INTEGER) {
      fail(`${label} contains an integer outside the IEEE-754 safe range; encode it as a decimal string`);
    }
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((entry, index) => assertJcsJsonValue(entry, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
    for (const key of Object.keys(value)) {
      assertWellFormedUnicode(key, `${label} object key`);
      assertJcsJsonValue(value[key], `${label}.${key}`);
    }
    return;
  }
  fail(`${label} contains a value that is not a JSON type`);
}

function jcsSerialize(value) {
  if (value === null || typeof value === "boolean" || typeof value === "number") {
    return JSON.stringify(value);
  }
  if (typeof value === "string") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(jcsSerialize).join(",")}]`;
  return `{${Object.keys(value).sort().map((key) => (
    `${JSON.stringify(key)}:${jcsSerialize(value[key])}`
  )).join(",")}}`;
}

/** RFC 8785 JCS restricted to integer JSON numbers in the IEEE-754 safe range. */
export function canonicalJson(value) {
  assertJcsJsonValue(value);
  return jcsSerialize(value);
}

export function sha256Json(value) {
  return createHash("sha256").update(canonicalJson(value)).digest("hex");
}

export function sha256Bytes(value) {
  return createHash("sha256").update(value).digest("hex");
}

/** Parse JSON without duplicate keys and enforce the interop integer subset. */
export function parseJsonStrict(source, label = "JSON") {
  if (typeof source !== "string") fail(`${label} source must be a string`);
  let index = 0;
  const parseFail = (message) => fail(`${label} ${message} at byte ${index}`);
  const whitespace = () => {
    while (/[\t\n\r ]/.test(source[index] ?? "")) index += 1;
  };
  const parseString = () => {
    if (source[index] !== '"') parseFail("expected string");
    const start = index;
    index += 1;
    while (index < source.length) {
      const character = source[index];
      if (character === '"') {
        index += 1;
        let value;
        try {
          value = JSON.parse(source.slice(start, index));
        } catch {
          parseFail("contains an invalid string");
        }
        assertWellFormedUnicode(value, label);
        return value;
      }
      if (character === "\\") {
        index += 1;
        if (source[index] === "u") {
          if (!/^[0-9a-fA-F]{4}$/.test(source.slice(index + 1, index + 5))) {
            parseFail("contains a malformed Unicode escape");
          }
          index += 5;
        } else if ('"\\/bfnrt'.includes(source[index] ?? "")) {
          index += 1;
        } else {
          parseFail("contains a malformed escape");
        }
      } else {
        if (character.charCodeAt(0) < 0x20) parseFail("contains an unescaped control character");
        index += 1;
      }
    }
    parseFail("contains an unterminated string");
  };
  const parseValue = () => {
    whitespace();
    const character = source[index];
    if (character === '"') return parseString();
    if (character === "{") {
      index += 1;
      const keys = new Set();
      const entries = [];
      whitespace();
      if (source[index] === "}") { index += 1; return {}; }
      while (true) {
        whitespace();
        const key = parseString();
        if (keys.has(key)) parseFail(`contains duplicate object key ${JSON.stringify(key)}`);
        keys.add(key);
        whitespace();
        if (source[index] !== ":") parseFail("expected colon");
        index += 1;
        entries.push([key, parseValue()]);
        whitespace();
        if (source[index] === "}") { index += 1; return Object.fromEntries(entries); }
        if (source[index] !== ",") parseFail("expected comma or closing brace");
        index += 1;
      }
    }
    if (character === "[") {
      index += 1;
      const array = [];
      whitespace();
      if (source[index] === "]") { index += 1; return array; }
      while (true) {
        array.push(parseValue());
        whitespace();
        if (source[index] === "]") { index += 1; return array; }
        if (source[index] !== ",") parseFail("expected comma or closing bracket");
        index += 1;
      }
    }
    for (const [token, value] of [["true", true], ["false", false], ["null", null]]) {
      if (source.startsWith(token, index)) { index += token.length; return value; }
    }
    const match = source.slice(index).match(/^-?(?:0|[1-9][0-9]*)/);
    if (match) {
      index += match[0].length;
      if (source[index] === "." || source[index] === "e" || source[index] === "E") {
        parseFail("contains a floating-point number");
      }
      const value = Number(match[0]);
      if (!Number.isSafeInteger(value)) parseFail("contains an integer outside the IEEE-754 safe range");
      return value;
    }
    parseFail("contains an unexpected token");
  };
  const value = parseValue();
  whitespace();
  if (index !== source.length) parseFail("contains trailing content");
  return value;
}

export function createProtocolReceiptEnvelope({
  phaseId,
  campaignId,
  environment,
  chainId,
  inputReceiptSha256 = "",
  payload
}) {
  const identity = PROTOCOL_PHASE_IDENTITIES[phaseId];
  if (!identity) fail(`unsupported protocol phase: ${phaseId}`);
  const envelope = {
    schema_version: 1,
    receipt_type: identity.receiptType,
    campaign_id: campaignId,
    phase_id: phaseId,
    environment,
    chain_id: Number(chainId),
    input_receipt_sha256: inputReceiptSha256,
    protocol_payload: {
      owner: identity.owner,
      schema_id: identity.schemaId,
      canonicalization: PROTOCOL_CANONICALIZATION,
      sha256: sha256Json(payload),
      payload
    }
  };
  return validateProtocolReceiptEnvelope(envelope, { phaseId, campaignId, environment, chainId });
}

export function validateProtocolReceiptEnvelope(envelope, expected = {}) {
  if (!envelope || typeof envelope !== "object" || Array.isArray(envelope)) {
    fail("protocol receipt envelope must be an object");
  }
  const allowed = new Set([
    "schema_version", "receipt_type", "campaign_id", "phase_id", "environment",
    "chain_id", "input_receipt_sha256", "protocol_payload"
  ]);
  const unknown = Object.keys(envelope).filter((key) => !allowed.has(key));
  if (unknown.length > 0) fail(`protocol receipt envelope has unknown fields: ${unknown.join(", ")}`);
  if (envelope.schema_version !== 1) fail("protocol receipt envelope schema_version must be 1");
  const identity = PROTOCOL_PHASE_IDENTITIES[envelope.phase_id];
  if (!identity || envelope.receipt_type !== identity.receiptType) {
    fail("protocol receipt envelope phase/receipt identity mismatch");
  }
  assertString(envelope.campaign_id, "envelope.campaign_id");
  if (!/^[a-z0-9][a-z0-9._-]{0,127}$/.test(envelope.campaign_id)) {
    fail("envelope.campaign_id is not a generic campaign id");
  }
  if (!ENVELOPE_ENVIRONMENTS.has(envelope.environment)) {
    fail(`unsupported envelope environment: ${envelope.environment}`);
  }
  if (!Number.isSafeInteger(envelope.chain_id) || envelope.chain_id < 1) {
    fail("envelope.chain_id must be a positive safe integer");
  }
  if (envelope.phase_id === "path-a") {
    if (envelope.input_receipt_sha256 !== "") fail("PATH Phase A envelope must not link an input receipt");
  } else {
    assertSha256(envelope.input_receipt_sha256, "envelope.input_receipt_sha256");
  }
  const wrapped = envelope.protocol_payload;
  if (!wrapped || typeof wrapped !== "object" || Array.isArray(wrapped)) {
    fail("envelope.protocol_payload must be an object");
  }
  const wrappedAllowed = new Set(["owner", "schema_id", "canonicalization", "sha256", "payload"]);
  const wrappedUnknown = Object.keys(wrapped).filter((key) => !wrappedAllowed.has(key));
  if (wrappedUnknown.length > 0) fail(`protocol_payload has unknown fields: ${wrappedUnknown.join(", ")}`);
  if (wrapped.owner !== identity.owner || wrapped.schema_id !== identity.schemaId
      || wrapped.canonicalization !== PROTOCOL_CANONICALIZATION) {
    fail("protocol payload owner/schema/canonicalization identity mismatch");
  }
  assertSha256(wrapped.sha256, "protocol_payload.sha256");
  if (!wrapped.payload || typeof wrapped.payload !== "object" || Array.isArray(wrapped.payload)) {
    fail("protocol_payload.payload must be an object");
  }
  if (sha256Json(wrapped.payload) !== wrapped.sha256) fail("protocol payload JCS SHA-256 mismatch");

  if (expected.phaseId && envelope.phase_id !== expected.phaseId) fail("protocol envelope phase mismatch");
  if (expected.receiptType && envelope.receipt_type !== expected.receiptType) fail("protocol envelope receipt type mismatch");
  if (expected.campaignId && envelope.campaign_id !== expected.campaignId) fail("protocol envelope campaign mismatch");
  if (expected.environment && envelope.environment !== expected.environment) fail("protocol envelope environment mismatch");
  if (expected.chainId !== undefined && BigInt(envelope.chain_id) !== BigInt(expected.chainId)) {
    fail("protocol envelope chain mismatch");
  }
  if (expected.inputReceiptSha256 !== undefined
      && envelope.input_receipt_sha256 !== expected.inputReceiptSha256) {
    fail("protocol envelope prior receipt link mismatch");
  }

  if (envelope.phase_id === "path-a") {
    validatePhaseAReceipt(wrapped.payload, {
      campaignId: envelope.campaign_id,
      environment: envelope.environment,
      chainId: envelope.chain_id
    });
  } else if (envelope.phase_id === "thought") {
    validateThoughtReceipt(wrapped.payload, {
      campaignId: envelope.campaign_id,
      environment: envelope.environment,
      chainId: envelope.chain_id
    });
  } else {
    assertFinalReceiptComplete(wrapped.payload, {
      campaignId: envelope.campaign_id,
      chainId: envelope.chain_id
    });
    if (wrapped.payload.environment !== envelope.environment) fail("Phase B payload environment mismatch");
  }
  return envelope;
}

export function normalizeAddress(value) {
  return String(value ?? "").toLowerCase();
}

export function sameAddress(left, right) {
  return normalizeAddress(left) === normalizeAddress(right);
}

export function parseUint(value, label, { positive = false, max = null } = {}) {
  let parsed;
  try {
    parsed = BigInt(value);
  } catch {
    fail(`${label} must be an unsigned integer`);
  }
  if (parsed < 0n || (positive && parsed === 0n)) {
    fail(`${label} must be ${positive ? "> 0" : ">= 0"}`);
  }
  if (max !== null && parsed > BigInt(max)) fail(`${label} exceeds ${max}`);
  return parsed;
}

export function assertAddress(value, label, { allowZero = false } = {}) {
  if (typeof value !== "string" || !ADDRESS_RE.test(value)) fail(`${label} is not an EVM address`);
  if (!allowZero && sameAddress(value, ZERO_ADDRESS)) fail(`${label} must not be zero`);
  if (PLACEHOLDER_RE.test(value)) fail(`${label} contains a placeholder`);
  return value;
}

export function assertEvmHash(value, label) {
  if (typeof value !== "string" || !EVM_HASH_RE.test(value)) fail(`${label} is not a bytes32 hash`);
  if (/^0x0{64}$/i.test(value)) fail(`${label} must not be zero`);
  return value;
}

export function assertSha256(value, label) {
  if (typeof value !== "string" || !SHA256_RE.test(value)) fail(`${label} is not a lowercase SHA-256`);
  if (/^0{64}$/.test(value)) fail(`${label} must not be zero`);
  return value;
}

function assertString(value, label) {
  if (typeof value !== "string" || value.trim() === "") fail(`${label} must be a non-empty string`);
  if (PLACEHOLDER_RE.test(value)) fail(`${label} contains a placeholder`);
  return value;
}

function assertEnvironment(value) {
  if (!ENVIRONMENTS.has(value)) fail(`unsupported environment: ${value}`);
}

function assertRelease(release, label) {
  if (!release || typeof release !== "object" || Array.isArray(release)) fail(`${label} must be an object`);
  assertString(release.repository, `${label}.repository`);
  assertString(release.releaseTag, `${label}.releaseTag`);
  if (typeof release.gitCommit !== "string" || !COMMIT_RE.test(release.gitCommit)) {
    fail(`${label}.gitCommit must be a lowercase 40-character commit`);
  }
  assertSha256(release.artifactManifestSha256, `${label}.artifactManifestSha256`);
}

function assertThoughtRelease(release, label) {
  if (!release || typeof release !== "object" || Array.isArray(release)) fail(`${label} must be an object`);
  for (const key of ["artifactId", "manifestSha256", "publicationCommit", "sourceTag"]) {
    assertString(release[key], `${label}.${key}`);
  }
  assertSha256(release.manifestSha256, `${label}.manifestSha256`);
  if (!COMMIT_RE.test(release.publicationCommit)) {
    fail(`${label}.publicationCommit must be a lowercase 40-character commit`);
  }
}

function normalizeSha256(value, label) {
  if (typeof value !== "string" || !/^(0x)?[0-9a-f]{64}$/.test(value)) {
    fail(`${label} is not a lowercase SHA-256`);
  }
  return value.replace(/^0x/, "");
}

export function protocolPayload(envelope, expected = {}) {
  return validateProtocolReceiptEnvelope(envelope, expected).protocol_payload.payload;
}

export function validateEmbeddedProtocolReceipt(embedded, expected = {}) {
  if (!embedded || typeof embedded !== "object" || Array.isArray(embedded)) {
    fail("embedded protocol receipt must be an object");
  }
  assertSha256(embedded.receiptSha256, "embedded protocol receipt SHA-256");
  if (typeof embedded.receiptRaw !== "string" || embedded.receiptRaw.length === 0) {
    fail("embedded protocol receipt must preserve exact receiptRaw bytes");
  }
  if (sha256Bytes(Buffer.from(embedded.receiptRaw, "utf8")) !== embedded.receiptSha256) {
    fail("embedded protocol receipt raw byte SHA-256 mismatch");
  }
  let parsed;
  try {
    parsed = parseJsonStrict(embedded.receiptRaw, "embedded protocol receiptRaw");
  } catch {
    fail("embedded protocol receiptRaw is not JSON");
  }
  if (canonicalJson(parsed) !== canonicalJson(embedded.receipt)) {
    fail("embedded protocol receipt object differs from exact receiptRaw bytes");
  }
  validateProtocolReceiptEnvelope(embedded.receipt, expected);
  return embedded.receipt;
}

export function phaseAProtocolPayload(params) {
  return params.pathPhaseA.receipt.protocol_payload.payload;
}

export function thoughtProtocolPayload(params) {
  return params.thoughtDeployment.receipt.protocol_payload.payload;
}

export function thoughtNftContractEvidence(params) {
  const payload = thoughtProtocolPayload(params);
  const deployment = payload.deployments.find((entry) => entry.name === "thoughtNft");
  if (!deployment) fail("THOUGHT ThoughtNFT deployment evidence is missing");
  return {
    address: payload.contracts.thoughtNft,
    deploymentTx: deployment.transaction,
    blockNumber: String(deployment.block),
    runtimeBytecodeHash: deployment.runtimeBytecodeHash
  };
}

function assertContractEvidence(contract, label) {
  if (!contract || typeof contract !== "object" || Array.isArray(contract)) fail(`${label} must be an object`);
  assertAddress(contract.address, `${label}.address`);
  assertEvmHash(contract.deploymentTx, `${label}.deploymentTx`);
  parseUint(contract.blockNumber, `${label}.blockNumber`, { positive: true });
  assertEvmHash(contract.runtimeBytecodeHash, `${label}.runtimeBytecodeHash`);
}

function assertTransactionEvidence(transaction, label) {
  if (!transaction || typeof transaction !== "object" || Array.isArray(transaction)) {
    fail(`${label} must be an object`);
  }
  assertEvmHash(transaction.hash, `${label}.hash`);
  parseUint(transaction.blockNumber, `${label}.blockNumber`, { positive: true });
}

function nestedValue(value, keys) {
  return keys.reduce((current, key) => current?.[key], value);
}

const PHASE_B_ACTION_EVIDENCE_PATHS = Object.freeze({
  SET_THOUGHT_MOVEMENT: ["transactions", "movement", "THOUGHT", "set"],
  FREEZE_THOUGHT_MOVEMENT: ["transactions", "movement", "THOUGHT", "freeze"],
  SET_WILL_MOVEMENT: ["transactions", "movement", "WILL", "set"],
  FREEZE_WILL_MOVEMENT: ["transactions", "movement", "WILL", "freeze"],
  SET_AWA_MOVEMENT: ["transactions", "movement", "AWA", "set"],
  FREEZE_AWA_MOVEMENT: ["transactions", "movement", "AWA", "freeze"],
  DEPLOY_PATH_PULSE_ADAPTER: ["transactions", "deployment", "pathPulseAdapter"],
  DEPLOY_PULSE_AUCTION_WITH_AUTHORIZED_OPEN_TIME: ["transactions", "deployment", "pulseAuction"],
  SET_ADAPTER_AUCTION: ["transactions", "wiring", "adapterSetAuction"],
  FREEZE_ADAPTER_WIRING: ["transactions", "wiring", "adapterFreezeWiring"],
  GRANT_PUBLIC_MINTER_ROLE_TO_ADAPTER: ["transactions", "wiring", "nftGrantMinterRole"],
  FREEZE_PUBLIC_MINTER_TO_ADAPTER: ["transactions", "wiring", "nftFreezePublicMinter"],
  GRANT_RESERVED_ROLE_TO_SPARK_ISSUER: ["transactions", "authority", "nftGrantReservedRole"],
  GRANT_DEFAULT_ADMIN_TO_FINAL_ADMIN: ["transactions", "authority", "nftGrantDefaultAdmin"],
  TRANSFER_ADAPTER_OWNERSHIP_TO_FINAL_ADMIN: ["transactions", "authority", "adapterTransferOwnership"],
  RENOUNCE_DEPLOYER_DEFAULT_ADMIN: ["transactions", "authority", "nftRenounceDeployerDefaultAdmin"]
});

function assertMovementState(state, label, { unset = false } = {}) {
  if (!state || typeof state !== "object" || Array.isArray(state)) fail(`${label} must be an object`);
  assertAddress(state.minter, `${label}.minter`, { allowZero: unset });
  const quota = parseUint(state.quota, `${label}.quota`);
  if (unset && (!sameAddress(state.minter, ZERO_ADDRESS) || quota !== 0n || state.frozen !== false)) {
    fail(`${label} must be zero-minter, zero-quota, and unfrozen`);
  }
  if (!unset && state.frozen !== true) fail(`${label} must be frozen`);
}

function assertReleaseEqual(actual, expected, label) {
  if (canonicalJson(actual) !== canonicalJson(expected)) fail(`${label} release identity mismatch`);
}

export function validatePhaseAParams(params) {
  if (!params || typeof params !== "object" || Array.isArray(params)) fail("Phase A params must be an object");
  assertString(params.campaignId, "campaignId");
  assertEnvironment(params.environment);
  parseUint(params.expectedChainId, "expectedChainId", { positive: true });
  assertRelease(params.pathRelease, "pathRelease");
  assertString(params.name, "name");
  assertString(params.symbol, "symbol");
  if (typeof params.baseUri !== "string") fail("baseUri must be a string");
  parseUint(params.reservedCap, "reservedCap");
  parseUint(params.sparkClaimDurationSec, "sparkClaimDurationSec", { positive: true, max: 2n ** 64n - 1n });
  if (!params.retainedAuthority || typeof params.retainedAuthority !== "object") {
    fail("retainedAuthority must be an object");
  }
  assertAddress(params.retainedAuthority.address, "retainedAuthority.address");
  assertString(params.retainedAuthority.signerRef, "retainedAuthority.signerRef");
  for (const forbidden of ["openTime", "startDelaySec", "pulseAuction", "pathPulseAdapter"] ) {
    if (Object.hasOwn(params, forbidden)) fail(`Phase A must not include ${forbidden}`);
  }
  return params;
}

export function validatePhaseAReceipt(receipt, expected = {}) {
  if (!receipt || typeof receipt !== "object" || Array.isArray(receipt)) fail("Phase A receipt must be an object");
  if (receipt.receiptVersion !== "1" || receipt.kind !== PATH_PHASE_A_KIND || receipt.status !== "phase_a_complete") {
    fail("Phase A receipt identity/status mismatch");
  }
  assertString(receipt.campaignId, "phaseA.campaignId");
  assertEnvironment(receipt.environment);
  parseUint(receipt.chainId, "phaseA.chainId", { positive: true });
  assertRelease(receipt.pathRelease, "phaseA.pathRelease");
  assertSha256(receipt.sourceBundleDigest, "phaseA.sourceBundleDigest");
  assertContractEvidence(receipt.pathNft, "phaseA.pathNft");
  if (!receipt.retainedAuthority || typeof receipt.retainedAuthority !== "object") {
    fail("phaseA.retainedAuthority must be an object");
  }
  assertAddress(receipt.retainedAuthority.holder, "phaseA.retainedAuthority.holder");
  if (receipt.retainedAuthority.role !== "DEFAULT_ADMIN_ROLE") fail("Phase A retained role must be DEFAULT_ADMIN_ROLE");
  if (receipt.retainedAuthority.handoffComplete !== false) fail("Phase A authority handoff must be incomplete");
  if (canonicalJson(receipt.retainedAuthority.permittedRemainingActions) !== canonicalJson(PHASE_A_PERMITTED_ACTIONS)) {
    fail("Phase A retained action set is not the bounded canonical set");
  }
  for (const label of ["THOUGHT", "WILL", "AWA"]) {
    assertMovementState(receipt.movementStates?.[label], `phaseA.movementStates.${label}`, { unset: true });
  }
  const exposure = receipt.publicExposure;
  if (!exposure || typeof exposure !== "object") fail("phaseA.publicExposure must be an object");
  if (exposure.pathPulseAdapter !== null || exposure.pulseAuction !== null || exposure.openTime !== null) {
    fail("Phase A must not contain an adapter, auction, or openTime");
  }
  if (!sameAddress(exposure.publicMinter, ZERO_ADDRESS) || exposure.publicMinterFrozen !== false || exposure.publicMintEnabled !== false) {
    fail("Phase A public mint must remain disabled and unfrozen");
  }
  parseUint(receipt.observedAtBlock, "phaseA.observedAtBlock", { positive: true });
  if (BigInt(receipt.pathNft.blockNumber) > BigInt(receipt.observedAtBlock)) {
    fail("Phase A observation block predates PathNFT deployment");
  }

  if (expected.campaignId && receipt.campaignId !== expected.campaignId) fail("Phase A campaignId mismatch");
  if (expected.environment && receipt.environment !== expected.environment) fail("Phase A environment mismatch");
  if (expected.chainId !== undefined && BigInt(receipt.chainId) !== BigInt(expected.chainId)) fail("Phase A chain mismatch");
  if (expected.pathRelease) assertReleaseEqual(receipt.pathRelease, expected.pathRelease, "Phase A");
  return receipt;
}

export function validateThoughtReceipt(receipt, expected = {}) {
  if (!receipt || typeof receipt !== "object" || Array.isArray(receipt)) fail("THOUGHT receipt must be an object");
  const requiredTopLevel = [
    "schema", "campaignId", "phase", "environment", "chainId", "status",
    "consumedPathPhaseAReceiptSha256", "consumedPathPhaseA", "pathNft", "thoughtRelease", "bundleDigest",
    "contracts", "deployments", "registry", "compatibility", "authorities",
    "approvedPathIntegration", "pathMutationPerformed", "pathMutationOwner", "verification"
  ];
  const unknown = Object.keys(receipt).filter((key) => !requiredTopLevel.includes(key));
  if (unknown.length > 0 || requiredTopLevel.some((key) => !Object.hasOwn(receipt, key))) {
    fail("THOUGHT receipt does not match the exact owner payload surface");
  }
  if (receipt.schema !== THOUGHT_RECEIPT_KIND || receipt.phase !== "thought" || receipt.status !== "complete") {
    fail("THOUGHT receipt identity/status mismatch");
  }
  assertString(receipt.campaignId, "thought.campaignId");
  assertEnvironment(receipt.environment);
  parseUint(receipt.chainId, "thought.chainId", { positive: true });
  assertThoughtRelease(receipt.thoughtRelease, "thought.thoughtRelease");
  assertEvmHash(receipt.bundleDigest, "thought.bundleDigest");
  normalizeSha256(receipt.consumedPathPhaseAReceiptSha256, "thought.consumedPathPhaseAReceiptSha256");
  const consumedPath = receipt.consumedPathPhaseA;
  assertSha256(consumedPath?.envelopeSha256, "thought.consumedPathPhaseA.envelopeSha256");
  assertSha256(consumedPath?.payloadSha256, "thought.consumedPathPhaseA.payloadSha256");
  if (consumedPath.envelopeSha256 !== receipt.consumedPathPhaseAReceiptSha256) {
    fail("THOUGHT legacy and generic Phase A envelope links disagree");
  }
  assertAddress(receipt.pathNft, "thought.pathNft");

  const contractNames = [
    "thoughtSpecRegistry", "protocolRegistry", "glyphDataPointer", "thoughtRenderer",
    "creationAttestationVerifier", "thoughtNft"
  ];
  for (const name of contractNames) assertAddress(receipt.contracts?.[name], `thought.contracts.${name}`);
  if (!Array.isArray(receipt.deployments) || receipt.deployments.length !== contractNames.length) {
    fail("THOUGHT deployment evidence is incomplete");
  }
  for (const name of contractNames) {
    const deployment = receipt.deployments.find((entry) => entry?.name === name);
    if (!deployment || !sameAddress(deployment.address, receipt.contracts[name])) {
      fail(`THOUGHT deployment address evidence mismatch: ${name}`);
    }
    assertEvmHash(deployment.transaction, `thought.deployments.${name}.transaction`);
    parseUint(deployment.block, `thought.deployments.${name}.block`, { positive: true });
    assertEvmHash(deployment.creationBytecodeHash, `thought.deployments.${name}.creationBytecodeHash`);
    assertEvmHash(deployment.runtimeBytecodeHash, `thought.deployments.${name}.runtimeBytecodeHash`);
  }

  const registry = receipt.registry;
  for (const key of ["thoughtSpecId", "thoughtSpecHash", "protocolReleaseId", "protocolManifestHash"]) {
    assertEvmHash(registry?.[key], `thought.registry.${key}`);
  }
  if (registry?.exactBytesVerified !== true) fail("THOUGHT registry exact bytes were not verified");

  const compatibility = receipt.compatibility;
  if (!compatibility || typeof compatibility !== "object") fail("thought.compatibility must be an object");
  assertAddress(compatibility.pathNftImmutable, "thought.compatibility.pathNftImmutable");
  if (!sameAddress(receipt.pathNft, compatibility.pathNftImmutable)) {
    fail("THOUGHT PATH immutable readback mismatch");
  }
  for (const key of [
    "rendererIdHash", "metadataProfileIdHash", "workProfileIdHash", "contextProfileIdHash",
    "creationAttestationProfileId"
  ]) assertEvmHash(compatibility[key], `thought.compatibility.${key}`);

  const authorities = receipt.authorities;
  for (const key of [
    "registryOwner", "protocolRegistryOwner", "attestationVerifierOwner", "attestationAuthority"
  ]) assertAddress(authorities?.[key], `thought.authorities.${key}`);
  parseUint(authorities?.attestationAuthorityEpoch, "thought.authorities.attestationAuthorityEpoch", { positive: true });

  const integration = receipt.approvedPathIntegration;
  if (integration?.movement !== "THOUGHT" || BigInt(integration?.quota ?? -1) !== 1n) {
    fail("THOUGHT approved PATH integration movement/quota mismatch");
  }
  assertAddress(integration.thoughtNft, "thought.approvedPathIntegration.thoughtNft");
  if (!sameAddress(integration.thoughtNft, receipt.contracts.thoughtNft)
      || receipt.pathMutationPerformed !== false || receipt.pathMutationOwner !== "PATH_PHASE_B") {
    fail("THOUGHT receipt PATH integration boundary mismatch");
  }
  for (const key of ["overall", "registry", "immutableDependencies", "profiles"]) {
    if (receipt.verification?.[key] !== "PASS") fail(`THOUGHT verification.${key} must be PASS`);
  }

  if (expected.campaignId && receipt.campaignId !== expected.campaignId) fail("THOUGHT campaignId mismatch");
  if (expected.environment && receipt.environment !== expected.environment) fail("THOUGHT environment mismatch");
  if (expected.chainId !== undefined && BigInt(receipt.chainId) !== BigInt(expected.chainId)) fail("THOUGHT chain mismatch");
  if (expected.thoughtRelease) assertReleaseEqual(receipt.thoughtRelease, expected.thoughtRelease, "THOUGHT");
  if (expected.pathPhaseAEnvelopeSha256
      && normalizeSha256(receipt.consumedPathPhaseAReceiptSha256, "thought PATH link")
        !== expected.pathPhaseAEnvelopeSha256) {
    fail("THOUGHT receipt PATH Phase A envelope link mismatch");
  }
  if (expected.pathPhaseAPayloadSha256
      && receipt.consumedPathPhaseA.payloadSha256 !== expected.pathPhaseAPayloadSha256) {
    fail("THOUGHT receipt PATH Phase A payload link mismatch");
  }
  if (expected.pathNft && !sameAddress(receipt.pathNft, expected.pathNft)) fail("THOUGHT PathNFT mismatch");
  return receipt;
}

export function validatePhaseBParams(params, { latestBlockTimestamp = null } = {}) {
  if (!params || typeof params !== "object" || Array.isArray(params)) fail("Phase B params must be an object");
  assertString(params.campaignId, "campaignId");
  assertEnvironment(params.environment);
  const chainId = parseUint(params.expectedChainId, "expectedChainId", { positive: true });
  if (!params.releaseMatrix || typeof params.releaseMatrix !== "object") fail("releaseMatrix must be an object");
  assertRelease(params.releaseMatrix.path, "releaseMatrix.path");
  assertThoughtRelease(params.releaseMatrix.thought, "releaseMatrix.thought");

  const phaseA = params.pathPhaseA;
  if (!phaseA || typeof phaseA !== "object") fail("pathPhaseA must be an object");
  assertSha256(phaseA.receiptSha256, "pathPhaseA.receiptSha256");
  validateEmbeddedProtocolReceipt(phaseA, {
    phaseId: "path-a",
    campaignId: params.campaignId,
    environment: params.environment,
    chainId
  });
  const phaseAPayload = phaseA.receipt.protocol_payload.payload;
  validatePhaseAReceipt(phaseAPayload, { pathRelease: params.releaseMatrix.path });

  const thought = params.thoughtDeployment;
  if (!thought || typeof thought !== "object") fail("thoughtDeployment must be an object");
  assertSha256(thought.receiptSha256, "thoughtDeployment.receiptSha256");
  validateEmbeddedProtocolReceipt(thought, {
    phaseId: "thought",
    campaignId: params.campaignId,
    environment: params.environment,
    chainId,
    inputReceiptSha256: phaseA.receiptSha256
  });
  const thoughtPayload = thought.receipt.protocol_payload.payload;
  validateThoughtReceipt(thoughtPayload, {
    thoughtRelease: params.releaseMatrix.thought,
    pathPhaseAEnvelopeSha256: phaseA.receiptSha256,
    pathPhaseAPayloadSha256: phaseA.receipt.protocol_payload.sha256,
    pathNft: phaseAPayload.pathNft.address
  });
  if (!sameAddress(thoughtPayload.pathNft, phaseAPayload.pathNft.address)) {
    fail("THOUGHT receipt points to a different PathNFT");
  }
  const thoughtDeployment = thoughtPayload.deployments.find((entry) => entry.name === "thoughtNft");
  if (BigInt(thoughtDeployment.block) < BigInt(phaseAPayload.observedAtBlock)) {
    fail("THOUGHT deployment predates the consumed Phase A receipt");
  }

  for (const [label, expectedQuota] of [["WILL", 10n], ["AWA", 1n]]) {
    const config = params.remainingMovements?.[label];
    if (!config || typeof config !== "object") fail(`remainingMovements.${label} must be an object`);
    assertAddress(config.minter, `remainingMovements.${label}.minter`);
    assertEvmHash(config.runtimeBytecodeHash, `remainingMovements.${label}.runtimeBytecodeHash`);
    if (parseUint(config.quota, `remainingMovements.${label}.quota`, { positive: true }) !== expectedQuota) {
      fail(`${label} quota must be ${expectedQuota}`);
    }
  }

  const open = params.openTimeAuthorization;
  if (!open || typeof open !== "object") fail("openTimeAuthorization must be an object");
  if (open.environment !== params.environment) fail("openTime authorization environment mismatch");
  const openTime = parseUint(open.authorizedOpenTime, "authorizedOpenTime", { positive: true, max: 2n ** 64n - 1n });
  const lead = parseUint(open.minimumLeadTimeSec, "minimumLeadTimeSec", { positive: true });
  parseUint(open.authorizedAt, "openTimeAuthorization.authorizedAt", { positive: true });
  const expiresAt = parseUint(open.expiresAt, "openTimeAuthorization.expiresAt", { positive: true });
  if (expiresAt <= openTime) fail("openTime authorization must remain valid through openTime");
  assertString(open.authorizerRef, "openTimeAuthorization.authorizerRef");
  assertString(open.authorizationId, "openTimeAuthorization.authorizationId");
  assertSha256(open.authorizationDigest, "openTimeAuthorization.authorizationDigest");
  const expectedAuthorizationDigest = sha256Json({
    campaignId: params.campaignId,
    environment: open.environment,
    authorizedOpenTime: String(open.authorizedOpenTime),
    minimumLeadTimeSec: String(open.minimumLeadTimeSec),
    authorizedAt: String(open.authorizedAt),
    expiresAt: String(open.expiresAt),
    authorizerRef: open.authorizerRef,
    authorizationId: open.authorizationId
  });
  if (open.authorizationDigest !== expectedAuthorizationDigest) {
    fail("openTime authorization digest mismatch");
  }
  if (latestBlockTimestamp !== null) {
    const latest = BigInt(latestBlockTimestamp);
    if (openTime <= latest + lead) fail("authorized openTime does not preserve the minimum lead time");
    if (latest >= expiresAt) fail("openTime authorization has expired");
  }

  const auction = params.auction;
  if (!auction || typeof auction !== "object") fail("auction must be an object");
  for (const key of ["k", "genesisPrice", "pts", "firstPublicId"]) {
    parseUint(auction[key], `auction.${key}`, { positive: true });
  }
  parseUint(auction.genesisFloor, "auction.genesisFloor");
  parseUint(auction.epochBase, "auction.epochBase");
  assertAddress(auction.paymentToken, "auction.paymentToken", { allowZero: true });

  const authority = params.finalAuthority;
  if (!authority || typeof authority !== "object") fail("finalAuthority must be an object");
  for (const key of ["admin", "treasury", "sparkIssuer"]) {
    assertAddress(authority[key], `finalAuthority.${key}`);
  }
  for (const key of ["adminSignerRef", "treasurySignerRef", "sparkIssuerSignerRef"]) {
    assertString(authority[key], `finalAuthority.${key}`);
  }
  const retainedHolder = phaseAPayload.retainedAuthority.holder;
  if (sameAddress(authority.admin, retainedHolder)) {
    fail("final admin must differ from the retained deployment authority");
  }
  if (sameAddress(authority.sparkIssuer, retainedHolder)) {
    fail("Spark issuer must differ from the retained deployment authority");
  }
  if (!sameAddress(authority.treasury, params.treasury)) fail("top-level treasury and finalAuthority.treasury mismatch");
  assertAddress(params.treasury, "treasury");
  if (params.treasurySignerRef !== authority.treasurySignerRef) fail("treasury signer reference mismatch");
  return params;
}

export function validatePhaseACheckpoint(checkpoint, expected = {}) {
  if (!checkpoint || typeof checkpoint !== "object" || Array.isArray(checkpoint)) {
    fail("Phase A checkpoint must be an object");
  }
  if (checkpoint.checkpointVersion !== "1"
    || checkpoint.kind !== "path_campaign_phase_a_checkpoint"
    || checkpoint.status !== "path_nft_deployed") {
    fail("Phase A checkpoint identity/status mismatch");
  }
  assertString(checkpoint.campaignId, "phaseACheckpoint.campaignId");
  assertEnvironment(checkpoint.environment);
  parseUint(checkpoint.chainId, "phaseACheckpoint.chainId", { positive: true });
  assertSha256(checkpoint.paramsSha256, "phaseACheckpoint.paramsSha256");
  assertSha256(checkpoint.sourceBundleDigest, "phaseACheckpoint.sourceBundleDigest");
  assertContractEvidence(checkpoint.pathNft, "phaseACheckpoint.pathNft");
  const exact = [
    ["campaignId", expected.campaignId],
    ["environment", expected.environment],
    ["paramsSha256", expected.paramsSha256],
    ["sourceBundleDigest", expected.sourceBundleDigest]
  ];
  for (const [key, value] of exact) {
    if (value !== undefined && checkpoint[key] !== value) fail(`Phase A checkpoint ${key} mismatch`);
  }
  if (expected.chainId !== undefined && BigInt(checkpoint.chainId) !== BigInt(expected.chainId)) {
    fail("Phase A checkpoint chain mismatch");
  }
  return checkpoint;
}

export function validatePhaseBCheckpoint(checkpoint, expected = {}) {
  if (!checkpoint || typeof checkpoint !== "object" || Array.isArray(checkpoint)) {
    fail("Phase B checkpoint must be an object");
  }
  if (checkpoint.checkpointVersion !== "1"
    || checkpoint.kind !== "path_campaign_phase_b_checkpoint"
    || checkpoint.status !== "phase_running") {
    fail("Phase B checkpoint identity/status mismatch");
  }
  assertString(checkpoint.campaignId, "checkpoint.campaignId");
  assertEnvironment(checkpoint.environment);
  parseUint(checkpoint.chainId, "checkpoint.chainId", { positive: true });
  assertSha256(checkpoint.paramsSha256, "checkpoint.paramsSha256");
  assertSha256(checkpoint.sourceBundleDigest, "checkpoint.sourceBundleDigest");
  assertSha256(
    checkpoint.linkedReceipts?.pathPhaseAReceiptSha256,
    "checkpoint.linkedReceipts.pathPhaseAReceiptSha256"
  );
  assertSha256(
    checkpoint.linkedReceipts?.thoughtDeploymentReceiptSha256,
    "checkpoint.linkedReceipts.thoughtDeploymentReceiptSha256"
  );
  if (!Array.isArray(checkpoint.completedActions)) {
    fail("checkpoint.completedActions must be an array");
  }
  checkpoint.completedActions.forEach((action, index) => {
    if (action !== PHASE_B_CHECKPOINT_ACTIONS[index]) {
      fail("Phase B checkpoint actions must be the canonical prefix");
    }
    const evidencePath = PHASE_B_ACTION_EVIDENCE_PATHS[action];
    assertTransactionEvidence(
      nestedValue(checkpoint, evidencePath),
      `checkpoint.${evidencePath.join(".")}`
    );
  });
  if (checkpoint.completedActions.length > PHASE_B_CHECKPOINT_ACTIONS.length) {
    fail("Phase B checkpoint contains too many actions");
  }
  if (checkpoint.completedActions.includes("DEPLOY_PATH_PULSE_ADAPTER")) {
    assertContractEvidence(checkpoint.contracts?.pathPulseAdapter, "checkpoint.contracts.pathPulseAdapter");
  }
  if (checkpoint.completedActions.includes("DEPLOY_PULSE_AUCTION_WITH_AUTHORIZED_OPEN_TIME")) {
    assertContractEvidence(checkpoint.contracts?.pulseAuction, "checkpoint.contracts.pulseAuction");
  }
  if (checkpoint.completedAtBlock !== undefined) {
    parseUint(checkpoint.completedAtBlock, "checkpoint.completedAtBlock", { positive: true });
  }
  if (checkpoint.completedActions.length < PHASE_B_CHECKPOINT_ACTIONS.length
    && checkpoint.completedAtBlock !== undefined) {
    fail("incomplete Phase B checkpoint must not have completedAtBlock");
  }

  const exact = [
    ["campaignId", expected.campaignId],
    ["environment", expected.environment],
    ["paramsSha256", expected.paramsSha256],
    ["sourceBundleDigest", expected.sourceBundleDigest]
  ];
  for (const [key, value] of exact) {
    if (value !== undefined && checkpoint[key] !== value) fail(`Phase B checkpoint ${key} mismatch`);
  }
  if (expected.chainId !== undefined && BigInt(checkpoint.chainId) !== BigInt(expected.chainId)) {
    fail("Phase B checkpoint chain mismatch");
  }
  if (expected.pathPhaseAReceiptSha256 !== undefined
    && checkpoint.linkedReceipts.pathPhaseAReceiptSha256 !== expected.pathPhaseAReceiptSha256) {
    fail("Phase B checkpoint Phase A receipt mismatch");
  }
  if (expected.thoughtDeploymentReceiptSha256 !== undefined
    && checkpoint.linkedReceipts.thoughtDeploymentReceiptSha256 !== expected.thoughtDeploymentReceiptSha256) {
    fail("Phase B checkpoint THOUGHT receipt mismatch");
  }
  return checkpoint;
}

export function phaseBCheckpointHas(checkpoint, action) {
  return checkpoint.completedActions.includes(action);
}

export function assertFinalReceiptComplete(receipt, expected = {}) {
  if (!receipt || typeof receipt !== "object" || Array.isArray(receipt)) fail("final receipt must be an object");
  if (receipt.receiptVersion !== "1" || receipt.kind !== PATH_PHASE_B_KIND || receipt.status !== "complete") {
    fail("partial deployment cannot be presented as campaign complete");
  }
  assertString(receipt.campaignId, "final.campaignId");
  assertEnvironment(receipt.environment);
  parseUint(receipt.chainId, "final.chainId", { positive: true });
  assertSha256(receipt.sourceBundleDigest, "final.sourceBundleDigest");
  assertRelease(receipt.releaseMatrix?.path, "final.releaseMatrix.path");
  assertThoughtRelease(receipt.releaseMatrix?.thought, "final.releaseMatrix.thought");
  assertSha256(receipt.linkedReceipts?.pathPhaseAReceiptSha256, "final.linkedReceipts.pathPhaseAReceiptSha256");
  assertSha256(
    receipt.linkedReceipts?.thoughtDeploymentReceiptSha256,
    "final.linkedReceipts.thoughtDeploymentReceiptSha256"
  );
  assertSha256(
    receipt.linkedReceipts?.pathPhaseAProtocolPayloadSha256,
    "final.linkedReceipts.pathPhaseAProtocolPayloadSha256"
  );
  assertSha256(
    receipt.linkedReceipts?.thoughtProtocolPayloadSha256,
    "final.linkedReceipts.thoughtProtocolPayloadSha256"
  );
  assertAddress(receipt.deployer, "final.deployer");
  for (const key of ["pathNft", "thoughtNft", "pathPulseAdapter", "pulseAuction"]) {
    assertContractEvidence(receipt.contracts?.[key], `final.contracts.${key}`);
  }
  for (const [label, expectedQuota] of [["THOUGHT", 1n], ["WILL", 10n], ["AWA", 1n]]) {
    const state = receipt.movementStates?.[label];
    assertMovementState(state, `final.movementStates.${label}`);
    if (parseUint(state.quota, `final.movementStates.${label}.quota`) !== expectedQuota) {
      fail(`final ${label} quota must be ${expectedQuota}`);
    }
  }
  parseUint(receipt.auction?.openTime, "final.auction.openTime", { positive: true });
  assertSha256(receipt.auction?.openTimeAuthorizationDigest, "final.auction.openTimeAuthorizationDigest");
  assertAddress(receipt.auction?.paymentToken, "final.auction.paymentToken", { allowZero: true });
  assertAddress(receipt.auction?.treasury, "final.auction.treasury");
  assertAddress(receipt.auction?.mintAdapter, "final.auction.mintAdapter");
  if (!sameAddress(receipt.auction.mintAdapter, receipt.contracts.pathPulseAdapter.address)) {
    fail("final auction mint adapter mismatch");
  }
  for (const key of ["admin", "sparkIssuer", "treasury", "adapterOwner"]) {
    assertAddress(receipt.finalAuthority?.[key], `final.finalAuthority.${key}`);
  }
  for (const key of ["adminSignerRef", "sparkIssuerSignerRef", "treasurySignerRef"]) {
    assertString(receipt.finalAuthority?.[key], `final.finalAuthority.${key}`);
  }
  if (!sameAddress(receipt.finalAuthority.adapterOwner, receipt.finalAuthority.admin)
    || receipt.finalAuthority.deployerRetainsDefaultAdmin !== false) {
    fail("final authority handoff evidence mismatch");
  }
  for (const action of PHASE_B_CHECKPOINT_ACTIONS) {
    const evidencePath = PHASE_B_ACTION_EVIDENCE_PATHS[action];
    assertTransactionEvidence(
      nestedValue(receipt, evidencePath),
      `final.${evidencePath.join(".")}`
    );
  }
  if (canonicalJson(receipt.actionOrder) !== canonicalJson(PHASE_B_ACTION_ORDER)) {
    fail("final receipt action order mismatch");
  }
  const checks = receipt.acceptance;
  const required = [
    "phaseAReceiptLinked",
    "thoughtReceiptLinked",
    "thoughtPathBindingVerified",
    "allMovementsConfiguredAndFrozen",
    "adapterAndAuctionWiringFrozen",
    "openTimeAuthorizedAndFuture",
    "publicMinterFrozen",
    "finalAuthorityVerified",
    "deployerAuthorityRemoved",
    "noPrematurePublicExposure"
  ];
  for (const key of required) if (checks?.[key] !== true) fail(`final acceptance ${key} must be true`);
  if (expected.campaignId && receipt.campaignId !== expected.campaignId) fail("final campaignId mismatch");
  if (expected.chainId !== undefined && BigInt(receipt.chainId) !== BigInt(expected.chainId)) fail("final chain mismatch");
  if (expected.sourceBundleDigest && receipt.sourceBundleDigest !== expected.sourceBundleDigest) {
    fail("final source bundle digest mismatch");
  }
  parseUint(receipt.observedAtBlock, "final.observedAtBlock", { positive: true });
  return receipt;
}

export async function runtimeCodeHash(ethers, address) {
  const code = await ethers.provider.getCode(address);
  if (code === "0x") fail(`no runtime code at ${address}`);
  return ethers.keccak256(code);
}

async function verifyTransactionOnChain(
  ethers,
  evidence,
  { from, to = null, contract = null, functionName = null, args = null, createdContract = null }
) {
  const tx = await ethers.provider.getTransaction(evidence.hash);
  const receipt = await ethers.provider.getTransactionReceipt(evidence.hash);
  if (!tx || !receipt || receipt.status !== 1) fail(`transaction ${evidence.hash} is not a successful mined transaction`);
  if (BigInt(receipt.blockNumber) !== BigInt(evidence.blockNumber)) {
    fail(`transaction ${evidence.hash} block number mismatch`);
  }
  if (!sameAddress(tx.from, from)) fail(`transaction ${evidence.hash} signer mismatch`);
  if (createdContract) {
    if (tx.to !== null || !sameAddress(receipt.contractAddress, createdContract)) {
      fail(`transaction ${evidence.hash} deployment address mismatch`);
    }
  } else if (!sameAddress(tx.to, to)) {
    fail(`transaction ${evidence.hash} target mismatch`);
  }
  if (functionName) {
    let parsed;
    try {
      parsed = contract.interface.parseTransaction({ data: tx.data, value: tx.value });
    } catch {
      fail(`transaction ${evidence.hash} calldata cannot be decoded`);
    }
    if (!parsed || parsed.name !== functionName) {
      fail(`transaction ${evidence.hash} method mismatch`);
    }
    if (args) {
      if (parsed.args.length !== args.length) fail(`transaction ${evidence.hash} argument count mismatch`);
      for (let index = 0; index < args.length; index += 1) {
        const actual = parsed.args[index];
        const expected = args[index];
        const matches = typeof expected === "bigint"
          ? BigInt(actual) === expected
          : typeof expected === "string" && expected.startsWith("0x")
            ? String(actual).toLowerCase() === expected.toLowerCase()
            : String(actual) === String(expected);
        if (!matches) fail(`transaction ${evidence.hash} argument ${index} mismatch`);
      }
    }
  }
  return { tx, receipt };
}

export async function verifyContractDeploymentEvidenceOnChain(ethers, evidence, expectedDeployer = null) {
  const observedHash = await runtimeCodeHash(ethers, evidence.address);
  if (observedHash.toLowerCase() !== evidence.runtimeBytecodeHash.toLowerCase()) {
    fail(`runtime bytecode mismatch at ${evidence.address}`);
  }
  const txEvidence = { hash: evidence.deploymentTx, blockNumber: evidence.blockNumber };
  const tx = await ethers.provider.getTransaction(evidence.deploymentTx);
  if (!tx) fail(`deployment transaction ${evidence.deploymentTx} is unavailable`);
  await verifyTransactionOnChain(ethers, txEvidence, {
    from: expectedDeployer ?? tx.from,
    createdContract: evidence.address
  });
}

export async function verifyPhaseAOnChain(ethers, receipt, signerAddress) {
  validatePhaseAReceipt(receipt);
  const network = await ethers.provider.getNetwork();
  if (network.chainId !== BigInt(receipt.chainId)) fail("on-chain Phase A chain mismatch");
  const observedHash = await runtimeCodeHash(ethers, receipt.pathNft.address);
  if (observedHash.toLowerCase() !== receipt.pathNft.runtimeBytecodeHash.toLowerCase()) {
    fail("PathNFT runtime bytecode hash mismatch");
  }
  const nft = await ethers.getContractAt("PathNFT", receipt.pathNft.address);
  const adminRole = await nft.DEFAULT_ADMIN_ROLE();
  if (!(await nft.hasRole(adminRole, receipt.retainedAuthority.holder))) fail("retained authority no longer has PATH admin");
  if (signerAddress && !sameAddress(receipt.retainedAuthority.holder, signerAddress)) fail("Phase B signer is not retained authority");
  for (const label of ["THOUGHT", "WILL", "AWA"]) {
    const movement = await nft[`MOVEMENT_${label}`]();
    const state = {
      minter: await nft.getAuthorizedMinter(movement),
      quota: (await nft.getMovementQuota(movement)).toString(),
      frozen: await nft.isMovementFrozen(movement)
    };
    assertMovementState(state, `onchain.${label}`, { unset: true });
  }
  if (!sameAddress(await nft.publicMinter(), ZERO_ADDRESS) || await nft.publicMinterFrozen()) {
    fail("Phase A PathNFT public mint state changed");
  }
  return nft;
}

export async function verifyPhaseAConstructorOnChain(ethers, params, evidence, deployerAddress) {
  await verifyContractDeploymentEvidenceOnChain(ethers, evidence, deployerAddress);
  const tx = await ethers.provider.getTransaction(evidence.deploymentTx);
  const receipt = await ethers.provider.getTransactionReceipt(evidence.deploymentTx);
  if (!tx || !receipt || !sameAddress(receipt.contractAddress, evidence.address)) {
    fail("Phase A deployment transaction does not create the checkpoint PathNFT");
  }
  if (!sameAddress(tx.from, deployerAddress)) fail("Phase A deployment transaction signer mismatch");
  const encodedArgs = ethers.AbiCoder.defaultAbiCoder().encode(
    ["address", "string", "string", "string", "uint64", "uint64"],
    [
      deployerAddress,
      params.name,
      params.symbol,
      params.baseUri,
      params.reservedCap,
      params.sparkClaimDurationSec
    ]
  );
  if (!tx.data.toLowerCase().endsWith(encodedArgs.slice(2).toLowerCase())) {
    fail("Phase A deployment constructor calldata mismatch");
  }
  const nft = await ethers.getContractAt("PathNFT", evidence.address);
  if (await nft.name() !== params.name
    || await nft.symbol() !== params.symbol
    || await nft.getReservedCap() !== BigInt(params.reservedCap)
    || await nft.sparkClaimDuration() !== BigInt(params.sparkClaimDurationSec)) {
    fail("Phase A constructor readback mismatch");
  }
  return nft;
}

export async function verifyPhaseACheckpointOnChain(ethers, params, checkpoint, signerAddress) {
  const observedHash = await runtimeCodeHash(ethers, checkpoint.pathNft.address);
  if (observedHash.toLowerCase() !== checkpoint.pathNft.runtimeBytecodeHash.toLowerCase()) {
    fail("Phase A checkpoint PathNFT bytecode mismatch");
  }
  const nft = await verifyPhaseAConstructorOnChain(
    ethers,
    params,
    checkpoint.pathNft,
    signerAddress
  );
  const defaultAdminRole = await nft.DEFAULT_ADMIN_ROLE();
  if (!(await nft.hasRole(defaultAdminRole, signerAddress))) {
    fail("Phase A checkpoint retained authority no longer has PATH admin");
  }
  for (const label of ["THOUGHT", "WILL", "AWA"]) {
    const movement = await nft[`MOVEMENT_${label}`]();
    const state = {
      minter: await nft.getAuthorizedMinter(movement),
      quota: (await nft.getMovementQuota(movement)).toString(),
      frozen: await nft.isMovementFrozen(movement)
    };
    assertMovementState(state, `phaseACheckpoint.onchain.${label}`, { unset: true });
  }
  if (!sameAddress(await nft.publicMinter(), ZERO_ADDRESS) || await nft.publicMinterFrozen()) {
    fail("Phase A checkpoint PathNFT public mint state changed");
  }
  return nft;
}

export async function verifyThoughtOnChain(ethers, params) {
  const thought = thoughtNftContractEvidence(params);
  await verifyContractDeploymentEvidenceOnChain(ethers, thought);
  const contract = new ethers.Contract(
    thought.address,
    ["function pathNft() view returns (address)"],
    ethers.provider
  );
  let pathReadback;
  try {
    pathReadback = await contract.pathNft();
  } catch {
    fail("ThoughtNFT does not expose the required pathNft() compatibility readback");
  }
  if (!sameAddress(pathReadback, phaseAProtocolPayload(params).pathNft.address)) {
    fail("ThoughtNFT binds a different PathNFT");
  }
  if (!sameAddress(pathReadback, thoughtProtocolPayload(params).compatibility.pathNftImmutable)) {
    fail("ThoughtNFT pathNft() disagrees with the THOUGHT receipt");
  }
  return thought.address;
}

export async function verifyPhaseBCheckpointOnChain(ethers, params, checkpoint, signerAddress) {
  const phaseAPayload = phaseAProtocolPayload(params);
  const pathEvidence = phaseAPayload.pathNft;
  const observedPathHash = await runtimeCodeHash(ethers, pathEvidence.address);
  if (observedPathHash.toLowerCase() !== pathEvidence.runtimeBytecodeHash.toLowerCase()) {
    fail("Phase B checkpoint PathNFT bytecode mismatch");
  }
  const nft = await ethers.getContractAt("PathNFT", pathEvidence.address);
  const defaultAdminRole = await nft.DEFAULT_ADMIN_ROLE();
  const reservedRole = await nft.RESERVED_ROLE();
  const minterRole = await nft.MINTER_ROLE();
  const deployer = phaseAPayload.retainedAuthority.holder;
  if (signerAddress && !sameAddress(deployer, signerAddress)) fail("Phase B checkpoint signer mismatch");

  const thoughtNft = await verifyThoughtOnChain(ethers, params);
  for (const label of ["WILL", "AWA"]) {
    const config = params.remainingMovements[label];
    const observed = await runtimeCodeHash(ethers, config.minter);
    if (observed.toLowerCase() !== config.runtimeBytecodeHash.toLowerCase()) {
      fail(`${label} movement runtime bytecode hash mismatch`);
    }
  }

  const expectedMovements = {
    THOUGHT: [thoughtNft, 1n],
    WILL: [params.remainingMovements.WILL.minter, 10n],
    AWA: [params.remainingMovements.AWA.minter, 1n]
  };
  const movementIds = {};
  for (const [label, [expectedMinter, expectedQuota]] of Object.entries(expectedMovements)) {
    const setRecorded = phaseBCheckpointHas(checkpoint, `SET_${label}_MOVEMENT`);
    const freezeRecorded = phaseBCheckpointHas(checkpoint, `FREEZE_${label}_MOVEMENT`);
    const movement = await nft[`MOVEMENT_${label}`]();
    movementIds[label] = movement;
    const minter = await nft.getAuthorizedMinter(movement);
    const quota = await nft.getMovementQuota(movement);
    const frozen = await nft.isMovementFrozen(movement);
    if (setRecorded) {
      if (!sameAddress(minter, expectedMinter) || quota !== expectedQuota) {
        fail(`${label} state does not match its Phase B checkpoint`);
      }
    } else if (!sameAddress(minter, ZERO_ADDRESS) || quota !== 0n) {
      fail(`${label} changed without a Phase B checkpoint`);
    }
    if (frozen !== freezeRecorded) fail(`${label} frozen state does not match its Phase B checkpoint`);
  }

  let adapter = null;
  let adapterAddress = ZERO_ADDRESS;
  if (phaseBCheckpointHas(checkpoint, "DEPLOY_PATH_PULSE_ADAPTER")) {
    const evidence = checkpoint.contracts.pathPulseAdapter;
    await verifyContractDeploymentEvidenceOnChain(ethers, evidence, deployer);
    adapter = await ethers.getContractAt("PathPulseAdapter", evidence.address);
    adapterAddress = evidence.address;
    if (!sameAddress(await adapter.pathNft(), pathEvidence.address)
      || await adapter.tokenBase() !== BigInt(params.auction.firstPublicId)
      || await adapter.epochBase() !== BigInt(params.auction.epochBase)) {
      fail("PathPulseAdapter constructor state does not match Phase B input");
    }
  }

  let auction = null;
  let auctionAddress = ZERO_ADDRESS;
  if (phaseBCheckpointHas(checkpoint, "DEPLOY_PULSE_AUCTION_WITH_AUTHORIZED_OPEN_TIME")) {
    const evidence = checkpoint.contracts.pulseAuction;
    await verifyContractDeploymentEvidenceOnChain(ethers, evidence, deployer);
    auction = await ethers.getContractAt("PulseAuction", evidence.address);
    auctionAddress = evidence.address;
    if (BigInt(await auction.openTime()) !== BigInt(params.openTimeAuthorization.authorizedOpenTime)
      || await auction.curveK() !== BigInt(params.auction.k)
      || await auction.genesisPrice() !== BigInt(params.auction.genesisPrice)
      || await auction.genesisFloor() !== BigInt(params.auction.genesisFloor)
      || await auction.pts() !== BigInt(params.auction.pts)
      || !sameAddress(await auction.mintAdapter(), adapterAddress)
      || !sameAddress(await auction.treasury(), params.treasury)
      || !sameAddress(await auction.paymentToken(), params.auction.paymentToken)
      || !sameAddress(await auction.deployer(), deployer)) {
      fail("PulseAuction constructor state does not match Phase B input");
    }
  }

  if (adapter) {
    const auctionSet = phaseBCheckpointHas(checkpoint, "SET_ADAPTER_AUCTION");
    const wiringFrozen = phaseBCheckpointHas(checkpoint, "FREEZE_ADAPTER_WIRING");
    if (!sameAddress(await adapter.auction(), auctionSet ? auctionAddress : ZERO_ADDRESS)
      || await adapter.wiringFrozen() !== wiringFrozen) {
      fail("PathPulseAdapter wiring does not match its Phase B checkpoint");
    }
    const expectedOwner = phaseBCheckpointHas(checkpoint, "TRANSFER_ADAPTER_OWNERSHIP_TO_FINAL_ADMIN")
      ? params.finalAuthority.admin
      : deployer;
    if (!sameAddress(await adapter.owner(), expectedOwner)) {
      fail("PathPulseAdapter owner does not match its Phase B checkpoint");
    }
    const minterGranted = phaseBCheckpointHas(checkpoint, "GRANT_PUBLIC_MINTER_ROLE_TO_ADAPTER");
    if (await nft.hasRole(minterRole, adapterAddress) !== minterGranted) {
      fail("PathPulseAdapter MINTER_ROLE does not match its Phase B checkpoint");
    }
  }

  const publicMinterFrozen = phaseBCheckpointHas(checkpoint, "FREEZE_PUBLIC_MINTER_TO_ADAPTER");
  if (await nft.publicMinterFrozen() !== publicMinterFrozen
    || !sameAddress(await nft.publicMinter(), publicMinterFrozen ? adapterAddress : ZERO_ADDRESS)) {
    fail("PathNFT public minter does not match its Phase B checkpoint");
  }
  const reservedGranted = phaseBCheckpointHas(checkpoint, "GRANT_RESERVED_ROLE_TO_SPARK_ISSUER");
  if (await nft.hasRole(reservedRole, params.finalAuthority.sparkIssuer) !== reservedGranted) {
    fail("Spark issuer role does not match its Phase B checkpoint");
  }
  const finalAdminGranted = phaseBCheckpointHas(checkpoint, "GRANT_DEFAULT_ADMIN_TO_FINAL_ADMIN");
  if (await nft.hasRole(defaultAdminRole, params.finalAuthority.admin) !== finalAdminGranted) {
    fail("Final admin role does not match its Phase B checkpoint");
  }
  const deployerRenounced = phaseBCheckpointHas(checkpoint, "RENOUNCE_DEPLOYER_DEFAULT_ADMIN");
  if (await nft.hasRole(defaultAdminRole, deployer) === deployerRenounced) {
    fail("Retained deployment authority does not match its Phase B checkpoint");
  }

  const actionMethods = {
    SET_THOUGHT_MOVEMENT: [nft, "setMovementConfig", [movementIds.THOUGHT, thoughtNft, 1n]],
    FREEZE_THOUGHT_MOVEMENT: [nft, "freezeMovementConfig", [movementIds.THOUGHT]],
    SET_WILL_MOVEMENT: [
      nft,
      "setMovementConfig",
      [movementIds.WILL, params.remainingMovements.WILL.minter, 10n]
    ],
    FREEZE_WILL_MOVEMENT: [nft, "freezeMovementConfig", [movementIds.WILL]],
    SET_AWA_MOVEMENT: [
      nft,
      "setMovementConfig",
      [movementIds.AWA, params.remainingMovements.AWA.minter, 1n]
    ],
    FREEZE_AWA_MOVEMENT: [nft, "freezeMovementConfig", [movementIds.AWA]],
    SET_ADAPTER_AUCTION: [adapter, "setAuction", [auctionAddress]],
    FREEZE_ADAPTER_WIRING: [adapter, "freezeWiring", []],
    GRANT_PUBLIC_MINTER_ROLE_TO_ADAPTER: [nft, "grantRole", [minterRole, adapterAddress]],
    FREEZE_PUBLIC_MINTER_TO_ADAPTER: [nft, "freezePublicMinter", [adapterAddress]],
    GRANT_RESERVED_ROLE_TO_SPARK_ISSUER: [
      nft,
      "grantRole",
      [reservedRole, params.finalAuthority.sparkIssuer]
    ],
    GRANT_DEFAULT_ADMIN_TO_FINAL_ADMIN: [
      nft,
      "grantRole",
      [defaultAdminRole, params.finalAuthority.admin]
    ],
    TRANSFER_ADAPTER_OWNERSHIP_TO_FINAL_ADMIN: [
      adapter,
      "transferOwnership",
      [params.finalAuthority.admin]
    ],
    RENOUNCE_DEPLOYER_DEFAULT_ADMIN: [nft, "renounceRole", [defaultAdminRole, deployer]]
  };
  const thoughtDeploymentReceipt = await ethers.provider.getTransactionReceipt(
    thoughtNftContractEvidence(params).deploymentTx
  );
  if (!thoughtDeploymentReceipt) fail("THOUGHT deployment transaction receipt is unavailable");
  let previousPosition = {
    blockNumber: BigInt(thoughtDeploymentReceipt.blockNumber),
    transactionIndex: Number(thoughtDeploymentReceipt.index ?? thoughtDeploymentReceipt.transactionIndex)
  };
  for (const action of checkpoint.completedActions) {
    const txEvidence = nestedValue(checkpoint, PHASE_B_ACTION_EVIDENCE_PATHS[action]);
    let actionReceipt;
    if (action === "DEPLOY_PATH_PULSE_ADAPTER") {
      const deployment = checkpoint.contracts.pathPulseAdapter;
      if (txEvidence.hash !== deployment.deploymentTx
        || BigInt(txEvidence.blockNumber) !== BigInt(deployment.blockNumber)) {
        fail("PathPulseAdapter deployment transaction evidence mismatch");
      }
      actionReceipt = await ethers.provider.getTransactionReceipt(txEvidence.hash);
    } else if (action === "DEPLOY_PULSE_AUCTION_WITH_AUTHORIZED_OPEN_TIME") {
      const deployment = checkpoint.contracts.pulseAuction;
      if (txEvidence.hash !== deployment.deploymentTx
        || BigInt(txEvidence.blockNumber) !== BigInt(deployment.blockNumber)) {
        fail("PulseAuction deployment transaction evidence mismatch");
      }
      actionReceipt = await ethers.provider.getTransactionReceipt(txEvidence.hash);
    } else {
      const [target, functionName, args] = actionMethods[action] ?? [];
      if (!target) fail(`missing transaction verifier for ${action}`);
      ({ receipt: actionReceipt } = await verifyTransactionOnChain(ethers, txEvidence, {
        from: deployer,
        to: await target.getAddress(),
        contract: target,
        functionName,
        args
      }));
    }
    if (!actionReceipt) fail(`transaction receipt unavailable for ${action}`);
    const position = {
      blockNumber: BigInt(actionReceipt.blockNumber),
      transactionIndex: Number(actionReceipt.index ?? actionReceipt.transactionIndex)
    };
    if (position.blockNumber < previousPosition.blockNumber
      || (position.blockNumber === previousPosition.blockNumber
        && position.transactionIndex <= previousPosition.transactionIndex)) {
      fail(`transaction order mismatch at ${action}`);
    }
    previousPosition = position;
  }

  return { nft, thoughtNft, adapter, auction };
}

export function collectTransactionHashes(value) {
  const hashes = [];
  const walk = (node) => {
    if (typeof node === "string" && EVM_HASH_RE.test(node)) {
      hashes.push(node);
      return;
    }
    if (Array.isArray(node)) {
      node.forEach(walk);
      return;
    }
    if (node && typeof node === "object") Object.values(node).forEach(walk);
  };
  walk(value);
  return [...new Set(hashes)];
}
