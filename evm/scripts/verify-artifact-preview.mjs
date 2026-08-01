import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const previewDir = path.resolve(here, "../preview");
const generated = await fs.readFile(path.join(previewDir, "tokens.generated.js"), "utf8");
const prefix = "window.PATH_ARTIFACT_PREVIEW = Object.freeze(";
assert.ok(generated.startsWith(prefix), "generated preview prefix");
assert.ok(generated.endsWith(");\n"), "generated preview suffix");
const snapshot = JSON.parse(generated.slice(prefix.length, -3));

assert.equal(snapshot.schema, "path.artifact-preview.v1");
assert.deepEqual(snapshot.quotas, { thought: 1, will: 10, awa: 1 });
assert.equal(snapshot.renderer.rendering, "native-svg-paths");
assert.equal(snapshot.renderer.progressModel, "text");
assert.equal(snapshot.renderer.weight, 400);
assert.match(snapshot.renderer.glyphSliceSha256, /^[0-9a-f]{64}$/);
assert.equal(snapshot.examples.length, 8);
assert.equal(snapshot.examples[0].label, "Fresh");
assert.equal(snapshot.examples.at(-1).label, "PATH complete");

for (const example of snapshot.examples) {
  assert.deepEqual(
    example.attributes.map((attribute) => attribute.trait_type),
    ["Stage", "THOUGHT", "WILL", "AWA"]
  );
  assert.ok(example.image.startsWith("data:image/svg+xml;base64,"));
  assert.equal(example.pathDefinitions, 9);
  assert.equal(example.glyphUses, 28);
  assert.match(example.tokenUriSha256, /^[0-9a-f]{64}$/);
  assert.match(example.svgSha256, /^[0-9a-f]{64}$/);

  const svg = Buffer.from(example.image.split(",")[1], "base64").toString("utf8");
  assert.ok(svg.includes("data-rendering='native-svg-paths'"));
  assert.ok(svg.includes(`data-glyph-slice-sha256='${snapshot.renderer.glyphSliceSha256}'`));
  assert.ok(!/<text(?:\s|>)/.test(svg));
}

for (const file of ["index.html", "preview.css", "preview.js", "favicon.svg"]) {
  const contents = await fs.readFile(path.join(previewDir, file), "utf8");
  assert.ok(contents.length > 100, `${file} is populated`);
}

console.log(
  `[artifact-preview] verified ${snapshot.examples.length} exact tokenURI images from runtime ${snapshot.localChain.runtimeCodeHash}`
);
