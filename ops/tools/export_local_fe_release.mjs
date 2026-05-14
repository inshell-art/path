#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { ethers } from "../../evm/node_modules/ethers/lib.esm/index.js";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "../..");

function flag(name) {
  const idx = process.argv.indexOf(name);
  return idx >= 0 ? process.argv[idx + 1] : undefined;
}

function usage() {
  console.error(
    "Usage: node ops/tools/export_local_fe_release.mjs [--rpc-url <url>] [--deployment-file <file>] [--out-dir <dir>] [--force]"
  );
  process.exit(1);
}

if (process.argv.includes("-h") || process.argv.includes("--help")) usage();

const rpcUrl = flag("--rpc-url") ?? "http://127.0.0.1:8546";
const deploymentFile = resolve(
  root,
  flag("--deployment-file") ?? "evm/deployments/localhost-eth.json"
);
const outDir = resolve(
  root,
  flag("--out-dir") ?? "artifacts/devnet/current/fe-release"
);
const force = process.argv.includes("--force");

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function writeJson(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

function assertAddress(label, value) {
  if (typeof value !== "string" || !/^0x[a-fA-F0-9]{40}$/.test(value)) {
    throw new Error(`Invalid address for ${label}: ${value}`);
  }
}

function abiCopy(src, dst) {
  const artifact = readJson(src);
  if (!Array.isArray(artifact.abi)) {
    throw new Error(`Missing ABI in artifact: ${src}`);
  }
  writeJson(dst, artifact.abi);
}

async function receiptBlock(provider, label, txHash, expectedAddress) {
  const receipt = await provider.getTransactionReceipt(txHash);
  if (!receipt) throw new Error(`Missing receipt for ${label}: ${txHash}`);
  if (receipt.status !== 1) {
    throw new Error(`Receipt status failed for ${label}: ${txHash}`);
  }
  if (receipt.contractAddress) {
    const actual = receipt.contractAddress.toLowerCase();
    const expected = expectedAddress.toLowerCase();
    if (actual !== expected) {
      throw new Error(
        `Receipt contract address mismatch for ${label}: ${receipt.contractAddress} != ${expectedAddress}`
      );
    }
  }
  return receipt.blockNumber;
}

function sha256(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

async function main() {
  if (!force && readFileSyncSafe(resolve(outDir, "protocol-release.devnet.json"))) {
    throw new Error(`Refusing to overwrite existing FE release without --force: ${outDir}`);
  }

  const deploy = readJson(deploymentFile);
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const network = await provider.getNetwork();
  const chainId = Number(network.chainId);

  const contracts = {
    path_nft: deploy.contracts.pathNft,
    path_pulse_adapter: deploy.contracts.pathPulseAdapter,
    pulse_auction: deploy.contracts.pulseAuction,
  };
  const addresses = {
    ...contracts,
    treasury: deploy.treasury,
    payment_token: deploy.paymentToken,
  };
  for (const [key, value] of Object.entries(addresses)) assertAddress(key, value);

  for (const [key, address] of Object.entries(contracts)) {
    const code = await provider.getCode(address);
    if (!code || code === "0x") throw new Error(`No on-chain code for ${key}: ${address}`);
  }

  const deployBlocks = {
    path_nft: await receiptBlock(provider, "path_nft", deploy.deployTxs.pathNft, contracts.path_nft),
    path_pulse_adapter: await receiptBlock(
      provider,
      "path_pulse_adapter",
      deploy.deployTxs.pathPulseAdapter,
      contracts.path_pulse_adapter
    ),
    pulse_auction: await receiptBlock(
      provider,
      "pulse_auction",
      deploy.deployTxs.pulseAuction,
      contracts.pulse_auction
    ),
  };

  const gitCommit = execFileSync("git", ["rev-parse", "HEAD"], {
    cwd: root,
    encoding: "utf8",
  }).trim();
  const runId = `devnet-local-${new Date().toISOString().replace(/[-:.]/g, "").replace("T", "T").slice(0, 15)}Z`;

  mkdirSync(resolve(outDir, "abi"), { recursive: true });
  abiCopy(resolve(root, "evm/artifacts/src/PathNFT.sol/PathNFT.json"), resolve(outDir, "abi/PathNFT.json"));
  abiCopy(
    resolve(root, "evm/artifacts/src/PathPulseAdapter.sol/PathPulseAdapter.json"),
    resolve(outDir, "abi/PathPulseAdapter.json")
  );
  abiCopy(resolve(root, "evm/artifacts/src/PulseAuction.sol/PulseAuction.json"), resolve(outDir, "abi/PulseAuction.json"));

  const manifest = {
    schema_version: 2,
    protocol: "path",
    network: "devnet",
    chain_id: chainId,
    repo_commit: gitCommit,
    deploy_run_id: runId,
    release_tier: "temporary",
    deployer: deploy.deployer,
    admin: deploy.admin ?? deploy.authority?.admin ?? deploy.deployer,
    treasury: deploy.treasury,
    payment_token: deploy.paymentToken,
    contracts,
    deploy_txs: {
      path_nft: deploy.deployTxs.pathNft,
      path_pulse_adapter: deploy.deployTxs.pathPulseAdapter,
      pulse_auction: deploy.deployTxs.pulseAuction,
    },
    deploy_blocks: deployBlocks,
    code_hashes: {
      path_nft: deploy.codeHashes.pathNft,
      path_pulse_adapter: deploy.codeHashes.pathPulseAdapter,
      pulse_auction: deploy.codeHashes.pulseAuction,
    },
    config: {
      name: deploy.config.name,
      symbol: deploy.config.symbol,
      base_uri: deploy.config.baseUri ?? "",
      open_time: Number(deploy.config.openTime),
      open_time_iso: deploy.config.openTimeIso,
      start_delay_sec: Number(deploy.config.startDelaySec ?? 0),
      k: String(deploy.config.k),
      genesis_price: String(deploy.config.genesisPrice),
      genesis_floor: String(deploy.config.genesisFloor),
      pts: String(deploy.config.pts),
      token_base: Number(deploy.config.tokenBase),
      epoch_base: Number(deploy.config.epochBase),
    },
    status: {
      postconditions: "pass",
      audit: "none",
      audit_id: null,
      ready_for_fe: true,
      notes: "local devnet rehearsal release",
    },
    source_artifacts: {
      deployment_relpath: "evm/deployments/localhost-eth.json",
      bundle_relpath: "evm/deployments",
    },
    generated_at: new Date().toISOString(),
  };

  writeJson(resolve(outDir, "addresses.devnet.json"), addresses);
  writeJson(resolve(outDir, "protocol-release.devnet.json"), manifest);
  writeFileSync(
    resolve(outDir, "env.devnet.example"),
    [
      "VITE_NETWORK=devnet",
      `VITE_ETH_RPC=${rpcUrl}`,
      `VITE_EXPECTED_CHAIN_ID=0x${chainId.toString(16)}`,
      `VITE_EVM_CHAIN_ID=${chainId}`,
      `VITE_EVM_CHAIN_IDS=${chainId}`,
      `VITE_PULSE_AUCTION_DEPLOY_BLOCK=${deployBlocks.pulse_auction}`,
      "",
    ].join("\n")
  );

  const checksums = {};
  for (const file of [
    "addresses.devnet.json",
    "protocol-release.devnet.json",
    "env.devnet.example",
  ]) {
    checksums[file] = sha256(resolve(outDir, file));
  }
  for (const name of readdirSync(resolve(outDir, "abi"))) {
    if (name.endsWith(".json")) {
      checksums[`abi/${name}`] = sha256(resolve(outDir, "abi", name));
    }
  }
  writeJson(resolve(outDir, "checksums.json"), checksums);

  console.log("local fe-release exported");
  console.log(`network=devnet`);
  console.log(`chain_id=${chainId}`);
  console.log(`out_dir=${outDir}`);
  console.log(`pulse_auction=${contracts.pulse_auction}`);
  console.log(`deploy_block=${deployBlocks.pulse_auction}`);
}

function readFileSyncSafe(path) {
  try {
    return readFileSync(path);
  } catch {
    return null;
  }
}

main().catch((err) => {
  console.error(`[export-local-fe-release] ERROR: ${err?.message ?? err}`);
  process.exit(1);
});
