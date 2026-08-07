import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import hre from "hardhat";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const outputFile = path.resolve(
  process.env.PATH_PREVIEW_OUT ?? path.join(here, "../preview/tokens.generated.js")
);

const QUOTAS = Object.freeze({ thought: 1n, will: 10n, awa: 1n });
const PROFILES = Object.freeze([
  { label: "Fresh", thought: 0n, will: 0n, awa: 0n },
  { label: "THOUGHT complete", thought: 1n, will: 0n, awa: 0n },
  { label: "WILL 1/10", thought: 1n, will: 1n, awa: 0n },
  { label: "WILL 3/10", thought: 1n, will: 3n, awa: 0n },
  { label: "WILL 5/10", thought: 1n, will: 5n, awa: 0n },
  { label: "WILL 8/10", thought: 1n, will: 8n, awa: 0n },
  { label: "WILL complete", thought: 1n, will: 10n, awa: 0n },
  { label: "PATH complete", thought: 1n, will: 10n, awa: 1n }
]);

const sha256 = (value) => createHash("sha256").update(value).digest("hex");

function decodeDataUri(value, prefix) {
  if (!value.startsWith(prefix)) {
    throw new Error(`Unexpected data URI: ${value.slice(0, 48)}`);
  }
  return Buffer.from(value.slice(prefix.length), "base64");
}

function decodeMetadata(tokenUri) {
  return JSON.parse(
    decodeDataUri(tokenUri, "data:application/json;base64,").toString("utf8")
  );
}

function attribute(svg, name) {
  return svg.match(new RegExp(`${name}='([^']+)'`))?.[1] ?? null;
}

function clipWidth(svg, id) {
  const match = svg.match(new RegExp(`id='${id}-progress'[^>]*width='([0-9]+)'`));
  return match ? Number(match[1]) : null;
}

function askAt(now, k, anchor, floorPrice) {
  if (now <= anchor) return floorPrice + k;
  return floorPrice + k / (now - anchor);
}

async function signConsumeAuthorization(ethers, nft, signer, chainId, tokenId, movement, deadline) {
  const typeHash = ethers.id(
    "ConsumeAuthorization(address pathNft,uint256 chainId,uint256 pathId,bytes32 movement,address claimer,address executor,uint256 permissionEpoch,uint256 nonce,uint256 deadline)"
  );
  const permissionEpoch = await nft.getPermissionEpoch(tokenId);
  const nonce = await nft.getConsumeNonce(signer.address);
  const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
    [
      "bytes32",
      "address",
      "uint256",
      "uint256",
      "bytes32",
      "address",
      "address",
      "uint256",
      "uint256",
      "uint256"
    ],
    [
      typeHash,
      await nft.getAddress(),
      chainId,
      tokenId,
      movement,
      signer.address,
      signer.address,
      permissionEpoch,
      nonce,
      deadline
    ]
  );
  return signer.signMessage(ethers.getBytes(ethers.keccak256(encoded)));
}

async function consume(ethers, nft, signer, chainId, tokenId, movement, count) {
  for (let i = 0n; i < count; i += 1n) {
    const latest = await signer.provider.getBlock("latest");
    const deadline = BigInt(latest.timestamp) + 3_600n;
    const signature = await signConsumeAuthorization(
      ethers,
      nft,
      signer,
      chainId,
      tokenId,
      movement,
      deadline
    );
    await (
      await nft.consumeUnit(tokenId, movement, signer.address, deadline, signature)
    ).wait();
  }
}

async function mintViaAuction(ethers, provider, auction, buyer) {
  const epochBefore = BigInt(await auction.getEpochIndex());
  const tokenId = epochBefore + 1n;
  const openTime = BigInt(await auction.openTime());
  const latest = await provider.getBlock("latest");
  const plannedTime = openTime > BigInt(latest.timestamp) + 1n
    ? openTime
    : BigInt(latest.timestamp) + 1n;
  const state = await auction.getState();
  const ask = await auction.curveActive()
    ? askAt(plannedTime, BigInt(await auction.curveK()), BigInt(state[2]), BigInt(state[3]))
    : BigInt(await auction.genesisPrice());

  await provider.send("evm_setNextBlockTimestamp", [Number(plannedTime)]);
  await (await auction.connect(buyer).bid(ask, { value: ask })).wait();
  return tokenId;
}

async function deployPreviewProtocol(ethers) {
  const [admin, treasury] = await ethers.getSigners();
  const latest = await ethers.provider.getBlock("latest");

  const PathNFT = await ethers.getContractFactory("PathNFT", admin);
  const nft = await PathNFT.deploy(
    admin.address,
    "PATH",
    "PATH",
    "",
    99n,
    604_800n
  );
  await nft.waitForDeployment();

  const PathPulseAdapter = await ethers.getContractFactory("PathPulseAdapter", admin);
  const adapter = await PathPulseAdapter.deploy(
    admin.address,
    ethers.ZeroAddress,
    await nft.getAddress(),
    1n,
    1n
  );
  await adapter.waitForDeployment();

  const PulseAuction = await ethers.getContractFactory("PulseAuction", admin);
  const auction = await PulseAuction.deploy(
    BigInt(latest.timestamp) + 60n,
    600n,
    1_000n,
    900n,
    1n,
    ethers.ZeroAddress,
    treasury.address,
    await adapter.getAddress()
  );
  await auction.waitForDeployment();

  await (await adapter.setAuction(await auction.getAddress())).wait();
  await (await adapter.freezeWiring()).wait();
  await (await nft.grantRole(await nft.MINTER_ROLE(), await adapter.getAddress())).wait();
  await (await nft.freezePublicMinter(await adapter.getAddress())).wait();

  const movements = {
    thought: ethers.encodeBytes32String("THOUGHT"),
    will: ethers.encodeBytes32String("WILL"),
    awa: ethers.encodeBytes32String("AWA")
  };
  await (await nft.setMovementConfig(movements.thought, admin.address, QUOTAS.thought)).wait();
  await (await nft.setMovementConfig(movements.will, admin.address, QUOTAS.will)).wait();
  await (await nft.setMovementConfig(movements.awa, admin.address, QUOTAS.awa)).wait();

  return { admin, nft, adapter, auction, movements };
}

async function main() {
  const conn = await hre.network.connect();
  try {
    const { ethers } = conn;
    const provider = ethers.provider;
    const { admin, nft, adapter, auction, movements } = await deployPreviewProtocol(ethers);
    const chainId = (await provider.getNetwork()).chainId;
    const examples = [];

    for (const profile of PROFILES) {
      const tokenId = await mintViaAuction(ethers, provider, auction, admin);
      await consume(ethers, nft, admin, chainId, tokenId, movements.thought, profile.thought);
      await consume(ethers, nft, admin, chainId, tokenId, movements.will, profile.will);
      await consume(ethers, nft, admin, chainId, tokenId, movements.awa, profile.awa);

      const tokenUri = await nft.tokenURI(tokenId);
      const metadata = decodeMetadata(tokenUri);
      const svgBytes = decodeDataUri(metadata.image, "data:image/svg+xml;base64,");
      const svg = svgBytes.toString("utf8");

      examples.push({
        tokenId: tokenId.toString(),
        label: profile.label,
        stage: metadata.stage,
        progress: {
          thought: Number(profile.thought),
          will: Number(profile.will),
          awa: Number(profile.awa)
        },
        attributes: metadata.attributes,
        image: metadata.image,
        tokenUriBytes: Buffer.byteLength(tokenUri),
        tokenUriSha256: sha256(tokenUri),
        svgBytes: svgBytes.length,
        svgSha256: sha256(svgBytes),
        pathDefinitions: (svg.match(/<path id='g-/g) ?? []).length,
        glyphUses: (svg.match(/<use href='#g-/g) ?? []).length,
        clipWidths: {
          thought: clipWidth(svg, "thought"),
          will: clipWidth(svg, "will"),
          awa: clipWidth(svg, "awa")
        }
      });
    }

    const runtimeCode = await provider.getCode(await nft.getAddress());
    const firstSvg = decodeDataUri(examples[0].image, "data:image/svg+xml;base64,").toString("utf8");
    const gitCommit = execFileSync("git", ["rev-parse", "HEAD"], {
      cwd: root,
      encoding: "utf8"
    }).trim();
    const artifactPath = path.join(here, "../artifacts/src/PathNFT.sol/PathNFT.json");
    const sourcePaths = [
      "evm/src/PathNFT.sol",
      "evm/src/PathSvgRenderer.sol",
      "evm/src/InshellMono76PathGlyphs.sol",
      "evm/glyphs/inshell-mono-76-path-400.json"
    ];

    const snapshot = {
      schema: "path.artifact-preview.v1",
      generatedAt: new Date().toISOString(),
      source: {
        repoCommit: gitCommit,
        artifactSha256: sha256(await fs.readFile(artifactPath)),
        files: Object.fromEntries(
          await Promise.all(sourcePaths.map(async (file) => [file, sha256(await fs.readFile(path.join(root, file)))]))
        )
      },
      localChain: {
        chainId: Number(chainId),
        blockNumber: await provider.getBlockNumber(),
        pathNft: await nft.getAddress(),
        pathPulseAdapter: await adapter.getAddress(),
        pulseAuction: await auction.getAddress(),
        runtimeCodeBytes: (runtimeCode.length - 2) / 2,
        runtimeCodeHash: ethers.keccak256(runtimeCode)
      },
      renderer: {
        rendering: attribute(firstSvg, "data-rendering"),
        progressModel: attribute(firstSvg, "data-progress-model"),
        family: attribute(firstSvg, "data-family"),
        face: attribute(firstSvg, "data-face"),
        weight: Number(attribute(firstSvg, "data-weight")),
        releaseCommit: attribute(firstSvg, "data-release-commit"),
        manifestSha256: attribute(firstSvg, "data-manifest-sha256"),
        glyphJsonSha256: attribute(firstSvg, "data-glyph-json-sha256"),
        glyphSliceSha256: attribute(firstSvg, "data-glyph-slice-sha256"),
        consumedColor: "#00ff35",
        remainingColor: "#ffffff"
      },
      quotas: {
        thought: Number(QUOTAS.thought),
        will: Number(QUOTAS.will),
        awa: Number(QUOTAS.awa)
      },
      examples
    };

    await fs.mkdir(path.dirname(outputFile), { recursive: true });
    await fs.writeFile(
      outputFile,
      `window.PATH_ARTIFACT_PREVIEW = Object.freeze(${JSON.stringify(snapshot, null, 2)});\n`,
      "utf8"
    );

    console.log(`[artifact-preview] wrote ${outputFile}`);
    console.log(`[artifact-preview] runtime ${snapshot.localChain.runtimeCodeHash}`);
    console.log(`[artifact-preview] tokens ${examples.length}`);
  } finally {
    await conn.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
