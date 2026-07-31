import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const TEXT = "THOUGHT WILL AWA";
const SLICE_URL = new URL("../glyphs/inshell-mono-76-path-400.json", import.meta.url);
const SOLIDITY_URL = new URL("../src/InshellMono76PathGlyphs.sol", import.meta.url);

const EXPECTED = Object.freeze({
  packageName: "@inshell/mono-76",
  packageVersion: "0.1.0",
  releaseTag: "v0.1.0",
  releaseCommit: "6fefbfaf762dce0148fe275baafb8e7dd2077beb",
  manifestSha256: "14d734495a8bdc99a98fecbc4f9d76d315c9e2b9fc9b032d5a1fda567258ce11",
  glyphJsonSha256: "2cf76834f82050853bdcc9d25bc4f040bd7cc2a6a310206e166f6d162e4f0c2e",
  packed400Sha256: "be74b2e518490c37498f726f3d82ca346241cd9f0df9697b0b15d0578fb5aab6",
});

const args = process.argv.slice(2);
const checkOnly = args.includes("--check");
const importIndex = args.indexOf("--import-from");
const importRoot = importIndex === -1 ? null : args[importIndex + 1];

if (importIndex !== -1 && !importRoot) {
  throw new Error("--import-from requires an @inshell/mono-76 package directory");
}
if (checkOnly && importRoot) {
  throw new Error("--check and --import-from cannot be combined");
}

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const assertEqual = (actual, expected, label) => {
  if (actual !== expected) {
    throw new Error(`${label} mismatch: expected ${expected}, received ${actual}`);
  }
};

async function readJson(url) {
  return JSON.parse(await readFile(url, "utf8"));
}

function uniqueCharacters(text) {
  return [...new Set([...text].filter((character) => character !== " "))];
}

async function importGlyphSlice(packageRoot) {
  const root = pathToFileURL(`${resolve(packageRoot)}/`);
  const packageJsonUrl = new URL("package.json", root);
  const manifestUrl = new URL("manifest.json", root);
  const glyphJsonUrl = new URL("fonts/400/glyphs.json", root);
  const [packageJson, manifest, manifestBytes, glyphData, glyphBytes] = await Promise.all([
    readJson(packageJsonUrl),
    readJson(manifestUrl),
    readFile(manifestUrl),
    readJson(glyphJsonUrl),
    readFile(glyphJsonUrl),
  ]);

  assertEqual(packageJson.name, EXPECTED.packageName, "package name");
  assertEqual(packageJson.version, EXPECTED.packageVersion, "package version");
  assertEqual(manifest.version, EXPECTED.packageVersion, "manifest version");
  assertEqual(sha256(manifestBytes), EXPECTED.manifestSha256, "manifest SHA-256");
  assertEqual(sha256(glyphBytes), EXPECTED.glyphJsonSha256, "glyph JSON SHA-256");

  const weight = manifest.weights?.find((entry) => entry.weight === 400);
  assertEqual(weight?.fileSha256, EXPECTED.glyphJsonSha256, "manifest glyph SHA-256");
  assertEqual(weight?.packedSha256, EXPECTED.packed400Sha256, "packed glyph SHA-256");
  assertEqual(glyphData.metrics?.unitsPerEm, 1000, "units per em");
  assertEqual(glyphData.metrics?.fixedAdvanceWidth, 600, "fixed advance width");

  const byCharacter = new Map(glyphData.glyphs.map((glyph) => [glyph.character, glyph]));
  const glyphs = uniqueCharacters(TEXT).map((character) => {
    const glyph = byCharacter.get(character);
    if (!glyph?.d) {
      throw new Error(`Missing glyph path for ${character}`);
    }
    return {
      character,
      advanceWidth: glyph.advanceWidth,
      pathSha256: glyph.pathSha256,
      d: glyph.d,
    };
  });

  const slice = {
    schema: "path.inshell-mono-76.glyph-slice.v1",
    text: TEXT,
    source: {
      packageName: EXPECTED.packageName,
      packageVersion: EXPECTED.packageVersion,
      releaseTag: EXPECTED.releaseTag,
      releaseCommit: EXPECTED.releaseCommit,
      manifestSha256: EXPECTED.manifestSha256,
      glyphJsonSha256: EXPECTED.glyphJsonSha256,
      packed400Sha256: EXPECTED.packed400Sha256,
      upstreamRepository: manifest.upstream.repository,
      upstreamReleaseCommit: manifest.upstream.releaseCommit,
      upstreamPackageVersion: manifest.upstream.packageVersion,
      upstreamTtfSha256: weight.source.fileSha256,
    },
    metrics: {
      unitsPerEm: glyphData.metrics.unitsPerEm,
      baseline: glyphData.metrics.baseline,
      fixedAdvanceWidth: glyphData.metrics.fixedAdvanceWidth,
      fillRule: glyphData.metrics.fillRule,
      lineBox: glyphData.metrics.lineBox,
    },
    glyphs,
  };

  await writeFile(SLICE_URL, `${JSON.stringify(slice, null, 2)}\n`, "utf8");
  console.log(`Imported ${glyphs.length} PATH glyphs into ${fileURLToPath(SLICE_URL)}`);
}

function validateSlice(slice) {
  assertEqual(slice.schema, "path.inshell-mono-76.glyph-slice.v1", "slice schema");
  assertEqual(slice.text, TEXT, "supported text");
  for (const [key, expected] of Object.entries(EXPECTED)) {
    assertEqual(slice.source?.[key], expected, `source ${key}`);
  }
  assertEqual(slice.metrics?.unitsPerEm, 1000, "slice units per em");
  assertEqual(slice.metrics?.fixedAdvanceWidth, 600, "slice fixed advance width");
  assertEqual(slice.metrics?.fillRule, "nonzero", "slice fill rule");

  const expectedCharacters = uniqueCharacters(TEXT);
  const actualCharacters = slice.glyphs?.map((glyph) => glyph.character) ?? [];
  assertEqual(JSON.stringify(actualCharacters), JSON.stringify(expectedCharacters), "glyph order");

  for (const glyph of slice.glyphs) {
    assertEqual(glyph.advanceWidth, 600, `${glyph.character} advance width`);
    assertEqual(sha256(glyph.d), glyph.pathSha256, `${glyph.character} path SHA-256`);
  }
}

function soliditySource(slice, sliceSha256) {
  const defs = slice.glyphs
    .map((glyph) => `            "<path id='g-${glyph.character}' d='${glyph.d}'/>"`)
    .join(",\n");

  return `// SPDX-License-Identifier: MIT AND OFL-1.1
pragma solidity ^0.8.24;

/// @notice The nine Inshell Mono 76 Regular 400 glyphs required by PATH.
/// @dev Generated by scripts/generate-path-glyphs.mjs. Do not edit paths by hand.
/// Glyph geometry is OFL-1.1; integration code is MIT. See docs/licenses/inshell-mono-76/.
library InshellMono76PathGlyphs {
    function releaseCommit() internal pure returns (string memory) {
        return "${slice.source.releaseCommit}";
    }

    function manifestSha256() internal pure returns (string memory) {
        return "${slice.source.manifestSha256}";
    }

    function glyphJsonSha256() internal pure returns (string memory) {
        return "${slice.source.glyphJsonSha256}";
    }

    function glyphSliceSha256() internal pure returns (string memory) {
        return "${sliceSha256}";
    }

    function defs() internal pure returns (string memory) {
        return string.concat(
${defs}
        );
    }
}
`;
}

if (importRoot) {
  await importGlyphSlice(importRoot);
}

const sliceBytes = await readFile(SLICE_URL);
const slice = JSON.parse(sliceBytes.toString("utf8"));
validateSlice(slice);
const generated = soliditySource(slice, sha256(sliceBytes));

if (checkOnly) {
  const existing = await readFile(SOLIDITY_URL, "utf8");
  if (existing !== generated) {
    throw new Error(
      `${fileURLToPath(SOLIDITY_URL)} is stale; run npm run glyphs:generate in evm/`,
    );
  }
  console.log(`Verified ${slice.glyphs.length} generated PATH glyphs`);
} else {
  await writeFile(SOLIDITY_URL, generated, "utf8");
  console.log(`Generated ${fileURLToPath(SOLIDITY_URL)} from ${fileURLToPath(SLICE_URL)}`);
}
