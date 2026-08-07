#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { keccak256 } from "ethers";

const here = path.dirname(fileURLToPath(import.meta.url));
const evmDir = path.resolve(here, "..");
const rootDir = path.resolve(evmDir, "..");

function option(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function git(args) {
  return execFileSync("git", args, { cwd: rootDir, encoding: "utf8" }).trim();
}

async function writeJson(file, value) {
  await writeFile(file, `${JSON.stringify(value, null, 2)}\n`);
}

function parsePreview(source) {
  const prefix = "window.PATH_ARTIFACT_PREVIEW = Object.freeze(";
  if (!source.startsWith(prefix) || !source.endsWith(");\n")) {
    throw new Error("Unexpected preview snapshot wrapper");
  }
  return JSON.parse(source.slice(prefix.length, -3));
}

const tag = option("--tag");
if (!tag || !/^v\d+\.\d+\.\d+$/.test(tag)) {
  throw new Error("Usage: build-downstream-artifacts.mjs --tag vX.Y.Z [--force]");
}

const force = process.argv.includes("--force");
const releaseDir = path.join(rootDir, "releases", tag);
const abiDir = path.join(releaseDir, "abi");
const hardhatDir = path.join(releaseDir, "hardhat");

if (force) await rm(releaseDir, { recursive: true, force: true });
await mkdir(path.dirname(releaseDir), { recursive: true });
await mkdir(releaseDir, { recursive: false }).catch((error) => {
  if (error.code === "EEXIST") {
    throw new Error(`Release already exists: ${releaseDir}; pass --force to replace it`);
  }
  throw error;
});
await mkdir(abiDir);
await mkdir(hardhatDir);

const definitions = [
  { name: "PathNFT", artifact: "artifacts/src/PathNFT.sol/PathNFT.json" },
  { name: "PathPulseAdapter", artifact: "artifacts/src/PathPulseAdapter.sol/PathPulseAdapter.json" },
  { name: "PulseAuction", artifact: "artifacts/src/PulseAuction.sol/PulseAuction.json" }
];

const contracts = {};
for (const definition of definitions) {
  const artifactPath = path.join(evmDir, definition.artifact);
  const artifactSource = await readFile(artifactPath);
  const artifact = JSON.parse(artifactSource);
  if (artifact.contractName !== definition.name || !Array.isArray(artifact.abi)) {
    throw new Error(`Invalid Hardhat artifact: ${artifactPath}`);
  }

  await writeJson(path.join(abiDir, `${definition.name}.json`), artifact.abi);
  await writeFile(path.join(hardhatDir, `${definition.name}.json`), artifactSource);

  contracts[definition.name] = {
    sourceName: artifact.sourceName,
    abi: `abi/${definition.name}.json`,
    hardhatArtifact: `hardhat/${definition.name}.json`,
    hardhatArtifactSha256: sha256(artifactSource),
    abiEntries: artifact.abi.length,
    creationBytecodeBytes: (artifact.bytecode.length - 2) / 2,
    runtimeBytecodeBytes: (artifact.deployedBytecode.length - 2) / 2,
    creationBytecodeKeccak256: keccak256(artifact.bytecode),
    runtimeBytecodeKeccak256: keccak256(artifact.deployedBytecode)
  };
}

const previewSource = await readFile(path.join(evmDir, "preview/tokens.generated.js"), "utf8");
const preview = parsePreview(previewSource);
const contractSourceCommit = git([
  "log",
  "-1",
  "--format=%H",
  "--",
  "evm/src",
  "evm/glyphs",
  "evm/hardhat.config.js"
]);

if (contracts.PathNFT.hardhatArtifactSha256 !== preview.source.artifactSha256) {
  throw new Error("PathNFT artifact does not match the artifact used by the exact-token preview");
}

const manifest = {
  schema: "path.downstream-artifacts.v1",
  releaseTag: tag,
  contractSourceCommit,
  compiler: {
    solidity: "0.8.24",
    optimizer: { enabled: true, runs: 1 },
    viaIR: true
  },
  canonicalContracts: ["PathNFT", "PathPulseAdapter", "PulseAuction"],
  contracts,
  renderer: {
    previewPath: "evm/preview/index.html",
    snapshotSchema: preview.schema,
    previewArtifactSha256: preview.source.artifactSha256,
    previewDeployedRuntimeCodeHash: preview.localChain.runtimeCodeHash,
    previewDeployedRuntimeCodeBytes: preview.localChain.runtimeCodeBytes,
    rendering: preview.renderer.rendering,
    glyphSliceSha256: preview.renderer.glyphSliceSha256,
    fontFamily: preview.renderer.family,
    fontWeight: preview.renderer.weight
  },
  compatibility: {
    breakingFrom: "v0.4.2",
    pathNftRedeploymentRequired: true,
    consumeAuthorizationSchema: "permission-epoch-v1",
    sparkInvitationSchema: "reserved-name-hash-v1",
    sparkTransferPolicy: "erc5192-locked",
    pathErrorSchema: "custom-errors-v1",
    movementDeploymentPolicy: "configured-frozen-1-10-1",
    erc5192MintEvents: true,
    networkAddressesIncluded: false,
    legacyMintContractsIncluded: false
  }
};
await writeJson(path.join(releaseDir, "manifest.json"), manifest);

const handoff = `# PATH ${tag} Downstream Handoff

## Pin

Consume the repository at tag \`${tag}\`. The canonical integration artifacts are:

- \`releases/${tag}/abi/PathNFT.json\`
- \`releases/${tag}/abi/PathPulseAdapter.json\`
- \`releases/${tag}/abi/PulseAuction.json\`
- \`releases/${tag}/hardhat/*.json\` for ABI plus bytecode
- \`releases/${tag}/manifest.json\` and \`SHA256SUMS.txt\` for verification

This bundle contains no network addresses. Import addresses only from a separately
verified deployment release for the target chain.

## Compatibility

This release changes the \`PathNFT\` ABI, bytecode, and consume-authorization
payload relative to \`v0.4.2\`. A new \`PathNFT\` deployment is required; do not
point this ABI or signing code at an older deployment. Import all addresses from
the separately verified deployment release for the target chain.

The Solidity arguments to \`consumeUnit\` are unchanged. Its signed EIP-191
struct now includes \`permissionEpoch\` between \`executor\` and \`nonce\`.
Old signing code fails with the \`BadConsumeAuthorization()\` custom error. PATH-specific
reverts are typed custom errors in this release; decode them from the release ABI.

The manifest distinguishes the Hardhat runtime template hash from the preview's
deployed-instance runtime hash. \`PathNFT\` has constructor immutables, so deployed
runtime hashes vary with constructor values even when the source artifact matches.

The public issuance path remains:

\`PulseAuction -> PathPulseAdapter -> PathNFT.safeMint\`

Do not use legacy \`PathMinter\` or \`PathMinterAdapter\` for new integrations.

## PATH NFT Integration

- Collection name and symbol are both \`PATH\`.
- Read \`tokenURI(tokenId)\`, decode its JSON data URL, and render the embedded
  \`image\` SVG data URL directly. Do not rebuild the token image in the frontend.
- Stable traits are \`Stage\`, \`THOUGHT\`, \`WILL\`, and \`AWA\`.
- Movement order is fixed: THOUGHT, WILL, AWA.
- Regular PATH remains ERC-721 transferable. Spark PATH is a permanently locked
  ERC-5192 award. Progress and remaining quota stay attached to the token ID.
- Only the current \`ownerOf(pathId)\` may sign movement authorization. ERC-721
  token approvals and operators have transfer rights only.
- Read \`getPermissionEpoch(pathId)\` before signing. Every successful non-mint
  regular PATH transfer increments the epoch and emits \`PermissionEpochAdvanced\`,
  invalidating older signatures even if the PATH later returns to the same owner.
- Movement tokens minted before a PATH transfer remain with their existing owners.
- The canonical deploy flow configures and freezes quotas \`1 / 10 / 1\` before
  auction wiring. Still read deployed movement quotas from
  \`getMovementQuota(bytes32)\` rather than hard-coding them in clients.
- Classify Spark tokens with \`isSparker(tokenId)\`. Spark is intentionally not a
  metadata trait and consumers should not infer it from an unpinned raw threshold.
- Read ERC-5192 \`locked(tokenId)\` for transferability. Spark returns \`true\`;
  regular PATH returns \`false\`. Mint logs emit \`Locked\` for Spark and
  \`Unlocked\` for regular PATH.
- \`RESERVED_ROLE\` creates an invitation with \`allowSparker(recipient, name)\`.
  It reserves one slot immediately. Read it with \`getSparkInvitation(recipient)\`.
- The recipient confirms the returned name, hashes its exact UTF-8 bytes, and calls
  \`mintSparker(expectedNameHash, data)\` before expiry. Read the minted immutable
  value with \`sparkName(tokenId)\`. The top-level metadata name is
  \`PATH Spark #<serial>: <name>\`, where the unpadded decimal
  \`serial = tokenId - SPARK_BASE + 1\`; the ERC-721 token ID remains unchanged.
- Spark metadata uses the permanent acknowledgment and invitation-to-create
  description; regular PATH retains the permission-token description.
- \`getReservedRemaining()\` is available capacity and \`getReservedPending()\`
  is invitation-held capacity. \`revokeSparker\` or permissionless
  \`releaseExpiredSparker\` returns a pending slot; a successful claim consumes it.
- Spark names are 1-31 printable ASCII bytes, excluding quote and backslash, with
  no leading or trailing spaces. No \`Spark\` or \`Name\` metadata trait is added.

Frontend implementers must follow
\`docs/evm/PATH_REMAINING_ENTITLEMENT_FE_HANDOFF.md\`, including the exact signed
field order and the pre-purchase \`Remaining entitlement\` display.

## Renderer

The PATH image is self-contained native SVG. It embeds only the nine Inshell Mono
76 glyph paths required for \`THOUGHT WILL AWA\`; no font installation, webfont,
off-chain renderer, or frontend text substitution is required.

Open \`evm/preview/index.html\` from this tag to inspect eight exact \`tokenURI\`
states. Regenerate it after contract renderer changes with:

\`npm run evm:preview:generate\`

## Verification

From the repository root:

\`npm run evm:artifacts:verify -- --tag ${tag}\`

The verifier checks every bundle checksum, ABI-to-artifact equality, bytecode
hashes, and the PathNFT artifact hash used to generate the exact preview snapshot.
`;
await writeFile(path.join(releaseDir, "DOWNSTREAM_HANDOFF.md"), handoff);

const releaseFiles = [
  "DOWNSTREAM_HANDOFF.md",
  "manifest.json",
  ...definitions.flatMap(({ name }) => [`abi/${name}.json`, `hardhat/${name}.json`])
];
const checksums = {};
for (const relative of releaseFiles.sort()) {
  checksums[relative] = sha256(await readFile(path.join(releaseDir, relative)));
}
await writeJson(path.join(releaseDir, "checksums.json"), checksums);
await writeFile(
  path.join(releaseDir, "SHA256SUMS.txt"),
  `${Object.entries(checksums).map(([file, hash]) => `${hash}  ${file}`).join("\n")}\n`
);

console.log(`[downstream-artifacts] release ${tag}`);
console.log(`[downstream-artifacts] source ${contractSourceCommit}`);
console.log(`[downstream-artifacts] PathNFT runtime ${contracts.PathNFT.runtimeBytecodeKeccak256}`);
console.log(`[downstream-artifacts] wrote ${releaseDir}`);
