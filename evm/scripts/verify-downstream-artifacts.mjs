#!/usr/bin/env node
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { keccak256 } from "ethers";

const here = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(here, "../..");

function option(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

const tag = option("--tag");
if (!tag || !/^v\d+\.\d+\.\d+$/.test(tag)) {
  throw new Error("Usage: verify-downstream-artifacts.mjs --tag vX.Y.Z");
}

const releaseDir = path.join(rootDir, "releases", tag);
const manifest = JSON.parse(await readFile(path.join(releaseDir, "manifest.json"), "utf8"));
const checksums = JSON.parse(await readFile(path.join(releaseDir, "checksums.json"), "utf8"));
const sumLines = (await readFile(path.join(releaseDir, "SHA256SUMS.txt"), "utf8")).trim().split("\n");

assert.equal(manifest.schema, "path.downstream-artifacts.v1");
assert.equal(manifest.releaseTag, tag);
assert.deepEqual(manifest.canonicalContracts, ["PathNFT", "PathPulseAdapter", "PulseAuction"]);
assert.equal(manifest.compatibility.networkAddressesIncluded, false);
assert.equal(manifest.compatibility.legacyMintContractsIncluded, false);
assert.equal(sumLines.length, Object.keys(checksums).length);

for (const [relative, expected] of Object.entries(checksums)) {
  const actual = sha256(await readFile(path.join(releaseDir, relative)));
  assert.equal(actual, expected, `checksum mismatch: ${relative}`);
  assert.ok(sumLines.includes(`${expected}  ${relative}`), `SHA256SUMS missing: ${relative}`);
}

for (const name of manifest.canonicalContracts) {
  const contract = manifest.contracts[name];
  const abi = JSON.parse(await readFile(path.join(releaseDir, contract.abi), "utf8"));
  const artifact = JSON.parse(await readFile(path.join(releaseDir, contract.hardhatArtifact), "utf8"));
  assert.equal(artifact.contractName, name);
  assert.deepEqual(abi, artifact.abi, `${name} ABI does not match its Hardhat artifact`);
  assert.equal(sha256(await readFile(path.join(releaseDir, contract.hardhatArtifact))), contract.hardhatArtifactSha256);
  assert.equal(keccak256(artifact.bytecode), contract.creationBytecodeKeccak256);
  assert.equal(keccak256(artifact.deployedBytecode), contract.runtimeBytecodeKeccak256);
  assert.equal((artifact.deployedBytecode.length - 2) / 2, contract.runtimeBytecodeBytes);
}

assert.equal(manifest.contracts.PathNFT.hardhatArtifactSha256, manifest.renderer.previewArtifactSha256);
assert.equal(manifest.contracts.PathNFT.runtimeBytecodeBytes, manifest.renderer.previewDeployedRuntimeCodeBytes);

console.log(
  `[downstream-artifacts] verified ${tag} (${Object.keys(checksums).length} checksums, ${manifest.canonicalContracts.length} contracts)`
);
