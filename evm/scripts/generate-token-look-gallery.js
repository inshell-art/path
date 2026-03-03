import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import hre from "hardhat";

const here = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_DEPLOY_FILE = path.resolve(here, "../deployments/localhost-eth.json");
const DEFAULT_OUT_FILE = path.resolve(here, "../deployments/reports/localhost-token-look-gallery.html");

const TARGET_THOUGHT_QUOTA = 1n;
const TARGET_WILL_QUOTA = 4n;
const TARGET_AWA_QUOTA = 1n;

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function decodeMetadata(tokenUri) {
  const base64Prefix = "data:application/json;base64,";
  const utf8Prefix = "data:application/json;utf8,";

  if (tokenUri.startsWith(base64Prefix)) {
    const encoded = tokenUri.slice(base64Prefix.length);
    return JSON.parse(Buffer.from(encoded, "base64").toString("utf8"));
  }

  if (tokenUri.startsWith(utf8Prefix)) {
    return JSON.parse(tokenUri.slice(utf8Prefix.length));
  }

  throw new Error(`Unsupported tokenURI format: ${tokenUri.slice(0, 40)}`);
}

function normalizeAttributes(raw) {
  if (!Array.isArray(raw)) return [];

  return raw
    .filter((item) => item && typeof item === "object")
    .map((item) => ({
      traitType: String(item.trait_type ?? item.type ?? "Trait"),
      value: String(item.value ?? "n/a")
    }));
}

function buildTraitSummary(cards) {
  const groups = new Map();

  for (const card of cards) {
    for (const attribute of card.attributes) {
      const type = attribute.traitType;
      const value = attribute.value;
      if (!groups.has(type)) {
        groups.set(type, new Map());
      }

      const values = groups.get(type);
      values.set(value, (values.get(value) ?? 0) + 1);
    }
  }

  const priority = ["Stage", "THOUGHT", "WILL", "AWA"];
  const rank = (type) => {
    const i = priority.indexOf(type);
    return i === -1 ? priority.length + 1 : i;
  };

  return [...groups.entries()]
    .map(([traitType, values]) => ({
      traitType,
      valueCount: values.size,
      values: [...values.entries()]
        .map(([value, count]) => ({ value, count }))
        .sort((a, b) => {
          if (b.count !== a.count) return b.count - a.count;
          return a.value.localeCompare(b.value);
        })
    }))
    .sort((a, b) => {
      const ra = rank(a.traitType);
      const rb = rank(b.traitType);
      if (ra !== rb) return ra - rb;
      return a.traitType.localeCompare(b.traitType);
    });
}

async function ensureMovementConfig(ethers, nft, movement, minter, quota) {
  const currentMinter = await nft.getAuthorizedMinter(movement);
  const currentQuota = await nft.getMovementQuota(movement);

  if (currentMinter !== ethers.ZeroAddress) {
    return { minter: currentMinter, quota: currentQuota, updated: false };
  }

  await (await nft.setMovementConfig(movement, minter, quota)).wait();
  return { minter, quota, updated: true };
}

function makeProfiles(thoughtQuota, willQuota, awaQuota) {
  const seen = new Set();
  const profiles = [];

  const add = (label, thought, will, awa) => {
    const key = `${thought}-${will}-${awa}`;
    if (seen.has(key)) return;
    seen.add(key);
    profiles.push({ label, thought, will, awa });
  };

  add("Fresh", 0n, 0n, 0n);
  add("Thought Started", thoughtQuota > 0n ? 1n : 0n, 0n, 0n);
  add("Will Started", thoughtQuota, willQuota > 0n ? 1n : 0n, 0n);
  add("Will Mid", thoughtQuota, willQuota > 1n ? willQuota / 2n : willQuota, 0n);
  add("Will Complete", thoughtQuota, willQuota, 0n);
  add("Complete", thoughtQuota, willQuota, awaQuota);

  return profiles;
}

async function signConsumeAuthorization(nft, chainId, claimerSigner, executor, tokenId, movement, deadline) {
  const pathNft = await nft.getAddress();
  const typeHash = hre.ethers.id(
    "ConsumeAuthorization(address pathNft,uint256 chainId,uint256 pathId,bytes32 movement,address claimer,address executor,uint256 nonce,uint256 deadline)"
  );
  const nonce = await nft.getConsumeNonce(claimerSigner.address);
  const encoded = hre.ethers.AbiCoder.defaultAbiCoder().encode(
    ["bytes32", "address", "uint256", "uint256", "bytes32", "address", "address", "uint256", "uint256"],
    [typeHash, pathNft, chainId, tokenId, movement, claimerSigner.address, executor, nonce, deadline]
  );
  const structHash = hre.ethers.keccak256(encoded);
  const signature = await claimerSigner.signMessage(hre.ethers.getBytes(structHash));
  return { signature, deadline };
}

async function consumeUnits(nft, signer, chainId, tokenId, movement, count) {
  for (let i = 0n; i < count; i += 1n) {
    const now = BigInt((await signer.provider.getBlock("latest")).timestamp);
    const deadline = now + 3_600n;
    const auth = await signConsumeAuthorization(nft, chainId, signer, signer.address, tokenId, movement, deadline);
    await (
      await nft
        .connect(signer)
        .consumeUnit(tokenId, movement, signer.address, auth.deadline, auth.signature)
    ).wait();
  }
}

async function main() {
  const deployFile = process.env.DEPLOY_FILE ?? DEFAULT_DEPLOY_FILE;
  const outputFile = process.env.OUT_FILE ?? DEFAULT_OUT_FILE;
  const bootstrapMovements = process.env.BOOTSTRAP_MOVEMENTS !== "0";

  const deployment = JSON.parse(await fs.readFile(deployFile, "utf8"));
  const conn = await hre.network.connect();
  const { ethers } = conn;
  const signers = await ethers.getSigners();
  const admin = signers[0];

  const signerByAddress = new Map(signers.map((s) => [s.address.toLowerCase(), s]));
  const nft = await ethers.getContractAt("PathNFT", deployment.contracts.pathNft, admin);
  const minter = await ethers.getContractAt("PathMinter", deployment.contracts.pathMinter, admin);
  const chainId = (await ethers.provider.getNetwork()).chainId;

  const MOVEMENT_THOUGHT = ethers.encodeBytes32String("THOUGHT");
  const MOVEMENT_WILL = ethers.encodeBytes32String("WILL");
  const MOVEMENT_AWA = ethers.encodeBytes32String("AWA");
  const SALES_ROLE = ethers.id("SALES_ROLE");

  let thoughtConfig;
  let willConfig;
  let awaConfig;
  let thoughtSigner;
  let willSigner;
  let awaSigner;
  let ownerSigner;

  if (bootstrapMovements) {
    thoughtConfig = await ensureMovementConfig(ethers, nft, MOVEMENT_THOUGHT, admin.address, TARGET_THOUGHT_QUOTA);
    willConfig = await ensureMovementConfig(ethers, nft, MOVEMENT_WILL, admin.address, TARGET_WILL_QUOTA);
    awaConfig = await ensureMovementConfig(ethers, nft, MOVEMENT_AWA, admin.address, TARGET_AWA_QUOTA);

    thoughtSigner = signerByAddress.get(thoughtConfig.minter.toLowerCase());
    willSigner = signerByAddress.get(willConfig.minter.toLowerCase());
    awaSigner = signerByAddress.get(awaConfig.minter.toLowerCase());

    if (!thoughtSigner || !willSigner || !awaSigner) {
      throw new Error("Movement minter must be one of local hardhat signers to generate sample progression.");
    }

    ownerSigner = thoughtSigner;
    for (const movementSigner of [thoughtSigner, willSigner, awaSigner]) {
      if (movementSigner.address.toLowerCase() === ownerSigner.address.toLowerCase()) continue;
      const isApproved = await nft.isApprovedForAll(ownerSigner.address, movementSigner.address);
      if (!isApproved) {
        await (await nft.connect(ownerSigner).setApprovalForAll(movementSigner.address, true)).wait();
      }
    }
  } else {
    thoughtConfig = {
      minter: await nft.getAuthorizedMinter(MOVEMENT_THOUGHT),
      quota: await nft.getMovementQuota(MOVEMENT_THOUGHT)
    };
    willConfig = {
      minter: await nft.getAuthorizedMinter(MOVEMENT_WILL),
      quota: await nft.getMovementQuota(MOVEMENT_WILL)
    };
    awaConfig = {
      minter: await nft.getAuthorizedMinter(MOVEMENT_AWA),
      quota: await nft.getMovementQuota(MOVEMENT_AWA)
    };
    ownerSigner = admin;
  }

  let mintSigner = admin;
  const salesFrozen = await minter.salesCallerFrozen();
  if (salesFrozen) {
    const salesCaller = await minter.salesCaller();
    const callerSigner = signerByAddress.get(salesCaller.toLowerCase());
    if (!callerSigner) {
      throw new Error("Sales caller is frozen to an unknown address. Redeploy local stack to generate gallery.");
    }
    mintSigner = callerSigner;
  } else {
    await (await minter.grantRole(SALES_ROLE, admin.address)).wait();
    await (await minter.freezeSalesCaller(admin.address)).wait();
    mintSigner = admin;
  }

  const profiles = bootstrapMovements
    ? makeProfiles(thoughtConfig.quota, willConfig.quota, awaConfig.quota)
    : [{ label: "Unconfigured", thought: 0n, will: 0n, awa: 0n }];
  const cards = [];

  for (const profile of profiles) {
    const tokenId = await minter.nextId();
    await (await minter.connect(mintSigner).mintPublic(ownerSigner.address, "0x")).wait();

    if (bootstrapMovements) {
      await consumeUnits(nft, thoughtSigner, chainId, tokenId, MOVEMENT_THOUGHT, profile.thought);
      await consumeUnits(nft, willSigner, chainId, tokenId, MOVEMENT_WILL, profile.will);
      await consumeUnits(nft, awaSigner, chainId, tokenId, MOVEMENT_AWA, profile.awa);
    }

    const tokenUri = await nft.tokenURI(tokenId);
    const metadata = decodeMetadata(tokenUri);

    cards.push({
      tokenId: tokenId.toString(),
      label: profile.label,
      stage: metadata.stage ?? "UNKNOWN",
      attributes: normalizeAttributes(metadata.attributes),
      image: metadata.image ?? "",
      description: metadata.description ?? ""
    });
  }

  const traitSummary = buildTraitSummary(cards);
  const traitRows = traitSummary.map((trait) => {
    const valueRows = trait.values.map((valueEntry) => `
                  <button
                    type="button"
                    class="trait-value-btn"
                    data-trait-type="${escapeHtml(trait.traitType)}"
                    data-trait-value="${escapeHtml(valueEntry.value)}"
                  >
                    <span>${escapeHtml(valueEntry.value)}</span>
                    <span>${escapeHtml(valueEntry.count)}</span>
                  </button>
    `).join("\n");

    return `
              <details class="trait-group" open>
                <summary class="trait-group-head">
                  <span>${escapeHtml(trait.traitType)}</span>
                  <span>${escapeHtml(trait.valueCount)}</span>
                </summary>
                <div class="trait-value-list">
${valueRows}
                </div>
              </details>
    `;
  }).join("\n");

  const htmlCards = cards.map((card) => {
    const attrsByType = new Map(card.attributes.map((a) => [a.traitType, a.value]));
    const attrsData = escapeHtml(JSON.stringify(card.attributes));
    return `
          <article class="asset-card" data-attrs="${attrsData}">
            <div class="asset-image-wrap">
              <img src="${escapeHtml(card.image)}" alt="PATH #${escapeHtml(card.tokenId)}" />
            </div>
            <div class="asset-meta">
              <p class="asset-title">PATH #${escapeHtml(card.tokenId)}</p>
              <p class="asset-label">${escapeHtml(card.label)}</p>
              <div class="asset-lines">
                <span>STAGE</span><span>${escapeHtml(attrsByType.get("Stage") ?? card.stage)}</span>
              </div>
              <div class="asset-lines">
                <span>THOUGHT</span><span>${escapeHtml(attrsByType.get("THOUGHT") ?? "n/a")}</span>
              </div>
              <div class="asset-lines">
                <span>WILL</span><span>${escapeHtml(attrsByType.get("WILL") ?? "n/a")}</span>
              </div>
              <div class="asset-lines">
                <span>AWA</span><span>${escapeHtml(attrsByType.get("AWA") ?? "n/a")}</span>
              </div>
            </div>
          </article>
    `;
  }).join("\n");

  const html = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>PATH Traits | Local Preview</title>
    <style>
      :root {
        --bg: #0a0f1a;
        --panel: #111827;
        --panel-2: #0f172a;
        --line: #253248;
        --text: #edf3ff;
        --muted: #94a3b8;
        --accent: #3b82f6;
        --accent-soft: #1e293b;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        font-family: "IBM Plex Sans", "Helvetica Neue", Helvetica, Arial, sans-serif;
        background: var(--bg);
        color: var(--text);
      }
      .app-shell {
        min-height: 100vh;
        display: grid;
        grid-template-columns: 56px 1fr;
      }
      .rail {
        border-right: 1px solid var(--line);
        background: #090e18;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 12px;
        padding: 12px 8px;
      }
      .rail-logo {
        width: 28px;
        height: 28px;
        border-radius: 50%;
        background: linear-gradient(130deg, #7c3aed, #2563eb);
      }
      .rail-btn {
        width: 32px;
        height: 32px;
        border-radius: 10px;
        border: 1px solid var(--line);
        display: grid;
        place-items: center;
        color: #9ca3af;
        font-size: 12px;
      }
      .main {
        min-width: 0;
      }
      .topbar {
        height: 64px;
        border-bottom: 1px solid var(--line);
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 0 18px;
        background: rgba(9, 14, 24, 0.82);
      }
      .search {
        width: min(520px, 50vw);
        border: 1px solid var(--line);
        border-radius: 10px;
        padding: 10px 14px;
        color: var(--muted);
        background: #0d1424;
      }
      .wallet-btn {
        border: 1px solid var(--line);
        border-radius: 10px;
        padding: 9px 12px;
        background: #0d1424;
        color: var(--text);
        font-weight: 600;
        font-size: 14px;
      }
      .hero {
        height: 184px;
        border-bottom: 1px solid var(--line);
        background:
          linear-gradient(100deg, rgba(217, 70, 239, 0.4), rgba(37, 99, 235, 0.35)),
          repeating-linear-gradient(
            78deg,
            rgba(255, 80, 80, 0.45) 0 86px,
            rgba(50, 220, 110, 0.25) 86px 172px,
            rgba(80, 110, 255, 0.35) 172px 258px
          );
      }
      .container {
        max-width: 1320px;
        margin: 0 auto;
        padding: 0 18px 28px;
      }
      .collection-head {
        margin-top: -38px;
        display: grid;
        grid-template-columns: 1fr auto;
        gap: 16px;
        align-items: end;
      }
      .title-wrap {
        display: flex;
        align-items: center;
        gap: 14px;
      }
      .avatar {
        width: 66px;
        height: 66px;
        border-radius: 14px;
        border: 2px solid #1f2f4a;
        background: #000;
      }
      h1 {
        margin: 0;
        font-size: 46px;
        line-height: 1.02;
        letter-spacing: -0.03em;
      }
      .meta-line {
        margin-top: 8px;
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }
      .meta-pill {
        border: 1px solid var(--line);
        border-radius: 8px;
        background: rgba(15, 23, 42, 0.9);
        color: #cbd5e1;
        padding: 4px 8px;
        font-size: 12px;
      }
      .stats {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: 10px;
        min-width: 560px;
      }
      .stat {
        text-align: right;
      }
      .stat-label {
        color: var(--muted);
        font-size: 11px;
        letter-spacing: 0.08em;
      }
      .stat-value {
        margin-top: 4px;
        font-size: 28px;
        font-weight: 700;
        letter-spacing: -0.02em;
      }
      .tabs {
        margin-top: 16px;
        border-bottom: 1px solid var(--line);
        display: flex;
        gap: 24px;
      }
      .tab {
        color: #9fb0cb;
        text-decoration: none;
        padding: 12px 0;
        border-bottom: 2px solid transparent;
        font-size: 14px;
      }
      .tab.active {
        color: #eef4ff;
        border-bottom-color: #eef4ff;
        font-weight: 600;
      }
      .layout {
        margin-top: 14px;
        display: grid;
        grid-template-columns: 300px 1fr;
        gap: 14px;
      }
      .sidebar {
        background: var(--panel-2);
        border: 1px solid var(--line);
        border-radius: 12px;
        overflow: hidden;
        align-self: start;
        position: sticky;
        top: 78px;
      }
      .sidebar-head {
        padding: 14px;
        border-bottom: 1px solid var(--line);
      }
      .sidebar h2 {
        margin: 0;
        font-size: 22px;
        letter-spacing: -0.02em;
      }
      .sidebar-search {
        margin-top: 10px;
        border: 1px solid var(--line);
        border-radius: 9px;
        background: #0d1424;
        padding: 10px 11px;
        color: #7f92b2;
        font-size: 14px;
      }
      .filter-section {
        padding: 12px 14px;
      }
      .filter-section + .filter-section {
        border-top: 1px solid var(--line);
      }
      .filter-title {
        margin: 0 0 10px;
        color: #e4ebf8;
        font-size: 24px;
        letter-spacing: -0.03em;
      }
      .status-row {
        display: flex;
        gap: 8px;
      }
      .status-chip {
        border: 1px solid var(--line);
        border-radius: 9px;
        background: #0d1424;
        color: #b8c7dd;
        padding: 7px 10px;
        font-size: 14px;
        font-weight: 600;
      }
      .status-chip.active {
        color: #eff6ff;
        border-color: #4f5f7a;
      }
      .trait-list {
        padding: 6px 0 10px;
      }
      .trait-group + .trait-group {
        border-top: 1px solid rgba(37, 50, 72, 0.55);
      }
      .trait-group-head {
        list-style: none;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
        padding: 10px 14px;
        color: #c2d0e6;
        cursor: pointer;
        user-select: none;
      }
      .trait-group-head::-webkit-details-marker {
        display: none;
      }
      .trait-group-head::after {
        content: "▾";
        color: #93a7c4;
        font-size: 11px;
        margin-left: auto;
        transition: transform 140ms ease;
      }
      .trait-group:not([open]) .trait-group-head::after {
        transform: rotate(-90deg);
      }
      .trait-group-head span:first-child {
        font-size: 16px;
      }
      .trait-group-head span:nth-child(2) {
        color: #8ca0bc;
        font-size: 14px;
      }
      .trait-value-list {
        display: grid;
        gap: 6px;
        padding: 0 10px 10px;
      }
      .trait-value-btn {
        border: 1px solid var(--line);
        border-radius: 9px;
        background: #0d1424;
        color: #cad7ea;
        padding: 8px 10px;
        display: flex;
        justify-content: space-between;
        gap: 10px;
        cursor: pointer;
        font-size: 14px;
      }
      .trait-value-btn.active {
        border-color: #4f78c6;
        background: #132342;
        color: #eff4ff;
      }
      .results-top {
        display: flex;
        justify-content: space-between;
        gap: 12px;
        margin-bottom: 12px;
      }
      .results-tools {
        display: flex;
        gap: 8px;
        flex: 1;
      }
      .results-search {
        flex: 1;
        border: 1px solid var(--line);
        border-radius: 10px;
        background: #0d1424;
        padding: 11px 12px;
        color: #8da0bc;
      }
      .results-clear {
        border: 1px solid var(--line);
        border-radius: 10px;
        background: #0d1424;
        color: #d6e2f5;
        min-width: 94px;
        padding: 10px 12px;
        font-weight: 600;
        cursor: pointer;
      }
      .results-clear:disabled {
        opacity: 0.45;
        cursor: not-allowed;
      }
      .results-sort {
        border: 1px solid var(--line);
        border-radius: 10px;
        background: #0d1424;
        padding: 10px 12px;
        color: #d6e2f5;
        min-width: 160px;
      }
      .active-filters {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        min-height: 34px;
        margin-bottom: 6px;
      }
      .active-chip {
        border: 1px solid #456ab1;
        border-radius: 10px;
        background: #142544;
        color: #e8f1ff;
        padding: 7px 10px;
        font-size: 13px;
        cursor: pointer;
      }
      .items-count {
        margin: 0 0 12px;
        color: #9bb0cf;
        font-size: 13px;
        letter-spacing: 0.08em;
      }
      .grid {
        margin: 0;
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(230px, 1fr));
        gap: 12px;
      }
      .asset-card {
        background: var(--panel);
        border: 1px solid var(--line);
        border-radius: 12px;
        overflow: hidden;
      }
      .asset-image-wrap {
        padding: 8px;
        border-bottom: 1px solid var(--line);
        background: #0b1220;
      }
      .asset-image-wrap img {
        display: block;
        width: 100%;
        aspect-ratio: 1 / 1;
      }
      .asset-meta {
        padding: 10px 12px 12px;
      }
      .asset-title {
        margin: 0;
        color: #dbe7f8;
        font-weight: 600;
      }
      .asset-label {
        margin: 5px 0 0;
        color: #7ea9ff;
        font-size: 13px;
      }
      .asset-lines {
        margin-top: 7px;
        display: flex;
        justify-content: space-between;
        gap: 10px;
        font-size: 13px;
      }
      .asset-lines span:first-child {
        color: var(--muted);
      }
      .asset-lines span:last-child {
        color: #e2ebf9;
      }
      code {
        font-family: "IBM Plex Mono", Menlo, Consolas, monospace;
      }
      @media (max-width: 1180px) {
        .stats {
          min-width: 0;
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
        .stat { text-align: left; }
      }
      @media (max-width: 980px) {
        .app-shell { grid-template-columns: 1fr; }
        .rail { display: none; }
        h1 { font-size: 36px; }
        .collection-head {
          margin-top: -22px;
          grid-template-columns: 1fr;
        }
        .search { width: min(420px, 60vw); }
        .layout { grid-template-columns: 1fr; }
        .sidebar {
          position: static;
          order: 2;
        }
        .results-top {
          flex-direction: column;
        }
      }
      @media (max-width: 640px) {
        .topbar {
          height: auto;
          padding: 10px;
          flex-direction: column;
          align-items: stretch;
          gap: 8px;
        }
        .search { width: 100%; }
        h1 { font-size: 30px; }
        .results-tools {
          flex-direction: column;
        }
      }
    </style>
  </head>
  <body>
    <div class="app-shell">
      <aside class="rail">
        <div class="rail-logo"></div>
        <div class="rail-btn">Q</div>
        <div class="rail-btn">E</div>
        <div class="rail-btn">T</div>
        <div class="rail-btn">S</div>
        <div class="rail-btn">P</div>
      </aside>
      <div class="main">
        <header class="topbar">
          <div class="search">Search OpenSea</div>
          <button class="wallet-btn" type="button">Connect Wallet</button>
        </header>
        <section class="hero"></section>
        <main class="container">
          <section class="collection-head">
            <div>
              <div class="title-wrap">
                <div class="avatar"></div>
                <div>
                  <h1>PATH</h1>
                </div>
              </div>
              <div class="meta-line">
                <span class="meta-pill">LOCAL DEVNET</span>
                <span class="meta-pill">${escapeHtml(cards.length)} TOKENS</span>
                <span class="meta-pill">BOOTSTRAP ${bootstrapMovements ? "ON" : "OFF"}</span>
              </div>
              <div class="meta-line">
                <span class="meta-pill">deploy <code>${escapeHtml(path.relative(path.dirname(outputFile), deployFile))}</code></span>
              </div>
            </div>
            <div class="stats">
              <div class="stat">
                <div class="stat-label">FLOOR PRICE</div>
                <div class="stat-value">N/A</div>
              </div>
              <div class="stat">
                <div class="stat-label">TOP OFFER</div>
                <div class="stat-value">N/A</div>
              </div>
              <div class="stat">
                <div class="stat-label">TOTAL SUPPLY</div>
                <div class="stat-value">${escapeHtml(cards.length)}</div>
              </div>
              <div class="stat">
                <div class="stat-label">TRAIT GROUPS</div>
                <div class="stat-value">${escapeHtml(traitSummary.length)}</div>
              </div>
            </div>
          </section>
          <nav class="tabs">
            <a class="tab" href="#">Explore</a>
            <a class="tab active" href="#">Items</a>
            <a class="tab" href="#">Offers</a>
            <a class="tab" href="#">Holders</a>
            <a class="tab" href="#traits-panel">Traits</a>
            <a class="tab" href="#">Activity</a>
          </nav>
          <section class="layout">
            <aside class="sidebar" id="traits-panel">
              <div class="sidebar-head">
                <h2>Traits</h2>
                <div class="sidebar-search">Search by item or trait</div>
              </div>
              <div class="filter-section">
                <h3 class="filter-title">Status</h3>
                <div class="status-row">
                  <button class="status-chip active" type="button">All</button>
                  <button class="status-chip" type="button">Listed</button>
                  <button class="status-chip" type="button">Not Listed</button>
                </div>
              </div>
              <div class="filter-section">
                <h3 class="filter-title">Traits</h3>
                <div class="trait-list">
${traitRows}
                </div>
              </div>
            </aside>
            <section>
              <div class="results-top">
                <div class="results-tools">
                  <div class="results-search">Search by item or trait</div>
                  <button id="clear-filters" class="results-clear" type="button" disabled>Clear</button>
                </div>
                <div class="results-sort">Highest floor</div>
              </div>
              <div class="active-filters" id="active-filters"></div>
              <p class="items-count"><span id="items-count">${escapeHtml(cards.length)}</span> ITEMS</p>
              <section class="grid" id="items-grid">
${htmlCards}
              </section>
            </section>
          </section>
        </main>
      </div>
    </div>
    <script>
      (() => {
        const cards = [...document.querySelectorAll(".asset-card")];
        const traitButtons = [...document.querySelectorAll(".trait-value-btn")];
        const clearFiltersButton = document.getElementById("clear-filters");
        const activeFilters = document.getElementById("active-filters");
        const itemsCount = document.getElementById("items-count");
        const filterByTrait = new Map();

        const parsedAttrs = new Map(cards.map((card) => {
          try {
            const attrs = JSON.parse(card.dataset.attrs || "[]");
            const attrMap = new Map();
            for (const attr of attrs) {
              if (!attr || typeof attr !== "object") continue;
              const traitType = String(attr.traitType ?? attr.trait_type ?? "");
              const value = String(attr.value ?? "");
              if (!traitType || !value) continue;
              attrMap.set(traitType, value);
            }
            return [card, attrMap];
          } catch {
            return [card, new Map()];
          }
        }));

        function refreshChips() {
          activeFilters.textContent = "";

          for (const [traitType, values] of filterByTrait.entries()) {
            for (const value of values) {
              const chip = document.createElement("button");
              chip.type = "button";
              chip.className = "active-chip";
              chip.dataset.traitType = traitType;
              chip.dataset.traitValue = value;
              chip.textContent = traitType + ": " + value + " ×";
              activeFilters.appendChild(chip);
            }
          }
        }

        function refreshView() {
          let visible = 0;

          for (const card of cards) {
            const attrs = parsedAttrs.get(card);
            let matched = true;

            for (const [traitType, values] of filterByTrait.entries()) {
              const cardValue = attrs.get(traitType);
              if (!cardValue || !values.has(cardValue)) {
                matched = false;
                break;
              }
            }

            card.style.display = matched ? "" : "none";
            if (matched) visible += 1;
          }

          for (const button of traitButtons) {
            const traitType = button.dataset.traitType;
            const traitValue = button.dataset.traitValue;
            const selected = filterByTrait.get(traitType)?.has(traitValue) ?? false;
            button.classList.toggle("active", selected);
          }

          clearFiltersButton.disabled = filterByTrait.size === 0;
          itemsCount.textContent = String(visible);
          refreshChips();
        }

        function toggleFilter(traitType, traitValue) {
          const values = filterByTrait.get(traitType) ?? new Set();

          if (values.has(traitValue)) {
            values.delete(traitValue);
            if (values.size === 0) {
              filterByTrait.delete(traitType);
            } else {
              filterByTrait.set(traitType, values);
            }
          } else {
            values.add(traitValue);
            filterByTrait.set(traitType, values);
          }

          refreshView();
        }

        for (const button of traitButtons) {
          button.addEventListener("click", () => {
            toggleFilter(button.dataset.traitType, button.dataset.traitValue);
          });
        }

        activeFilters.addEventListener("click", (event) => {
          const target = event.target.closest(".active-chip");
          if (!target) return;
          toggleFilter(target.dataset.traitType, target.dataset.traitValue);
        });

        clearFiltersButton.addEventListener("click", () => {
          filterByTrait.clear();
          refreshView();
        });

        refreshView();
      })();
    </script>
  </body>
</html>
`;

  await fs.mkdir(path.dirname(outputFile), { recursive: true });
  await fs.writeFile(outputFile, html, "utf8");

  console.log("[token-look-gallery] generated");
  console.log(`page: ${outputFile}`);
  console.log("tokens:", cards.map((c) => `#${c.tokenId}:${c.stage}`).join(", "));

  await conn.close();
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
