import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import hre from "hardhat";

const DEFAULTS = {
  name: "PATH NFT",
  symbol: "PATH",
  baseUri: "",
  k: 600n,
  genesisPrice: 1_000n,
  genesisFloor: 900n,
  pts: 1n,
  firstPublicId: 1n,
  epochBase: 1n,
  reservedCap: 3n,
  paymentToken: null
};

const CLI_FLAG_MAP = {
  "params-file": "paramsFile",
  name: "name",
  symbol: "symbol",
  "base-uri": "baseUri",
  "open-time": "openTime",
  "start-delay-sec": "startDelaySec",
  k: "k",
  "genesis-price": "genesisPrice",
  "genesis-floor": "genesisFloor",
  pts: "pts",
  "first-public-id": "firstPublicId",
  "epoch-base": "epochBase",
  "reserved-cap": "reservedCap",
  "payment-token": "paymentToken",
  treasury: "treasury",
  "treasury-signer-ref": "treasurySignerRef"
};

const ENV_KEY_MAP = {
  DEPLOY_PARAMS_FILE: "paramsFile",
  DEPLOY_NAME: "name",
  DEPLOY_SYMBOL: "symbol",
  DEPLOY_BASE_URI: "baseUri",
  DEPLOY_OPEN_TIME: "openTime",
  DEPLOY_START_DELAY_SEC: "startDelaySec",
  DEPLOY_K: "k",
  DEPLOY_GENESIS_PRICE: "genesisPrice",
  DEPLOY_GENESIS_FLOOR: "genesisFloor",
  DEPLOY_PTS: "pts",
  DEPLOY_FIRST_PUBLIC_ID: "firstPublicId",
  DEPLOY_EPOCH_BASE: "epochBase",
  DEPLOY_RESERVED_CAP: "reservedCap",
  DEPLOY_PAYMENT_TOKEN: "paymentToken",
  DEPLOY_TREASURY: "treasury",
  DEPLOY_TREASURY_SIGNER_REF: "treasurySignerRef"
};

const NPM_CONFIG_KEY_MAP = {
  npm_config_deploy_params_file: "paramsFile",
  npm_config_deploy_name: "name",
  npm_config_deploy_symbol: "symbol",
  npm_config_deploy_base_uri: "baseUri",
  npm_config_deploy_open_time: "openTime",
  npm_config_deploy_start_delay_sec: "startDelaySec",
  npm_config_deploy_k: "k",
  npm_config_deploy_genesis_price: "genesisPrice",
  npm_config_deploy_genesis_floor: "genesisFloor",
  npm_config_deploy_pts: "pts",
  npm_config_deploy_first_public_id: "firstPublicId",
  npm_config_deploy_epoch_base: "epochBase",
  npm_config_deploy_reserved_cap: "reservedCap",
  npm_config_deploy_payment_token: "paymentToken",
  npm_config_deploy_treasury: "treasury",
  npm_config_deploy_treasury_signer_ref: "treasurySignerRef"
};

const here = path.dirname(fileURLToPath(import.meta.url));

function parseCliConfig(argv) {
  const config = {};

  for (let i = 0; i < argv.length; i += 1) {
    const item = argv[i];
    if (!item.startsWith("--")) continue;

    const trimmed = item.slice(2);
    const eqIndex = trimmed.indexOf("=");

    let key;
    let value;
    if (eqIndex >= 0) {
      key = trimmed.slice(0, eqIndex);
      value = trimmed.slice(eqIndex + 1);
    } else {
      key = trimmed;
      const next = argv[i + 1];
      if (next && !next.startsWith("--")) {
        value = next;
        i += 1;
      } else {
        value = "true";
      }
    }

    const mapped = CLI_FLAG_MAP[key];
    if (!mapped) continue;
    config[mapped] = value;
  }

  return config;
}

function readEnvConfig(env) {
  const config = {};

  for (const [envKey, mappedKey] of Object.entries(ENV_KEY_MAP)) {
    if (!(envKey in env)) continue;
    config[mappedKey] = env[envKey];
  }

  return config;
}

function readNpmConfig(env) {
  const config = {};

  for (const [envKey, mappedKey] of Object.entries(NPM_CONFIG_KEY_MAP)) {
    if (!(envKey in env)) continue;
    config[mappedKey] = env[envKey];
  }

  return config;
}

function pickValue(source, keys) {
  for (const key of keys) {
    if (Object.hasOwn(source, key) && source[key] !== undefined) {
      return source[key];
    }
  }
  return undefined;
}

function normalizeFileConfig(raw) {
  const base = raw && typeof raw === "object" && !Array.isArray(raw)
    ? raw
    : {};
  const source = base.config && typeof base.config === "object" && !Array.isArray(base.config)
    ? base.config
    : base;

  return {
    name: pickValue(source, ["name"]),
    symbol: pickValue(source, ["symbol"]),
    baseUri: pickValue(source, ["baseUri", "base_uri", "base-uri"]),
    openTime: pickValue(source, ["openTime", "open_time", "open-time"]),
    startDelaySec: pickValue(source, ["startDelaySec", "start_delay_sec", "start-delay-sec"]),
    k: pickValue(source, ["k"]),
    genesisPrice: pickValue(source, ["genesisPrice", "genesis_price", "genesis-price"]),
    genesisFloor: pickValue(source, ["genesisFloor", "genesis_floor", "genesis-floor"]),
    pts: pickValue(source, ["pts"]),
    firstPublicId: pickValue(source, ["firstPublicId", "first_public_id", "first-public-id", "tokenBase", "token_base", "token-base"]),
    epochBase: pickValue(source, ["epochBase", "epoch_base", "epoch-base"]),
    reservedCap: pickValue(source, ["reservedCap", "reserved_cap", "reserved-cap"]),
    paymentToken: pickValue(source, ["paymentToken", "payment_token", "payment-token"]),
    treasury: pickValue(source, ["treasury"]),
    treasurySignerRef: pickValue(source, ["treasurySignerRef", "treasury_signer_ref", "treasury-signer-ref"])
  };
}

async function readParamsFile(paramsFile) {
  if (!paramsFile) return {};
  const absPath = path.resolve(paramsFile);
  const parsed = JSON.parse(await fs.readFile(absPath, "utf8"));
  return {
    ...normalizeFileConfig(parsed),
    paramsFile: absPath
  };
}

function coalesce(...values) {
  for (const value of values) {
    if (value !== undefined && value !== null) return value;
  }
  return undefined;
}

function parseUint(value, keyName) {
  try {
    const parsed = typeof value === "bigint" ? value : BigInt(value);
    if (parsed < 0n) {
      throw new Error(`${keyName} must be >= 0`);
    }
    return parsed;
  } catch (err) {
    throw new Error(`Invalid ${keyName}: ${String(value)} (${err.message})`);
  }
}

function parseAddress(value, keyName, ethers, { allowZero = true } = {}) {
  if (typeof value !== "string") {
    throw new Error(`${keyName} must be a string address`);
  }
  if (!ethers.isAddress(value)) {
    throw new Error(`Invalid ${keyName}: ${value}`);
  }
  if (!allowZero && value.toLowerCase() === ethers.ZeroAddress.toLowerCase()) {
    throw new Error(`${keyName} cannot be zero address`);
  }
  return value;
}

const U64_MAX = (1n << 64n) - 1n;

function isLocalLikeNetwork(networkName, chainId) {
  if (networkName === "localhost" || networkName === "hardhat" || networkName === "anvil") {
    return true;
  }
  return chainId === 31337n || chainId === 1337n;
}

function unixSecondsToIso(unixSeconds) {
  const maxSafeUnix = BigInt(Math.floor(Number.MAX_SAFE_INTEGER / 1000));
  if (unixSeconds > maxSafeUnix) {
    throw new Error(`openTime too large for ISO conversion: ${unixSeconds.toString()}`);
  }
  return new Date(Number(unixSeconds) * 1000).toISOString();
}

function resolveDeployConfig({
  cliConfig,
  npmConfig,
  envConfig,
  fileConfig,
  ethers,
  fallbackTreasury,
  networkName,
  chainId
}) {
  const merged = {
    name: coalesce(cliConfig.name, npmConfig.name, envConfig.name, fileConfig.name, DEFAULTS.name),
    symbol: coalesce(cliConfig.symbol, npmConfig.symbol, envConfig.symbol, fileConfig.symbol, DEFAULTS.symbol),
    baseUri: coalesce(cliConfig.baseUri, npmConfig.baseUri, envConfig.baseUri, fileConfig.baseUri, DEFAULTS.baseUri),
    k: parseUint(coalesce(cliConfig.k, npmConfig.k, envConfig.k, fileConfig.k, DEFAULTS.k), "k"),
    genesisPrice: parseUint(coalesce(cliConfig.genesisPrice, npmConfig.genesisPrice, envConfig.genesisPrice, fileConfig.genesisPrice, DEFAULTS.genesisPrice), "genesisPrice"),
    genesisFloor: parseUint(coalesce(cliConfig.genesisFloor, npmConfig.genesisFloor, envConfig.genesisFloor, fileConfig.genesisFloor, DEFAULTS.genesisFloor), "genesisFloor"),
    pts: parseUint(coalesce(cliConfig.pts, npmConfig.pts, envConfig.pts, fileConfig.pts, DEFAULTS.pts), "pts"),
    firstPublicId: parseUint(coalesce(cliConfig.firstPublicId, npmConfig.firstPublicId, envConfig.firstPublicId, fileConfig.firstPublicId, DEFAULTS.firstPublicId), "firstPublicId"),
    epochBase: parseUint(coalesce(cliConfig.epochBase, npmConfig.epochBase, envConfig.epochBase, fileConfig.epochBase, DEFAULTS.epochBase), "epochBase"),
    reservedCap: parseUint(coalesce(cliConfig.reservedCap, npmConfig.reservedCap, envConfig.reservedCap, fileConfig.reservedCap, DEFAULTS.reservedCap), "reservedCap")
  };

  if (typeof merged.name !== "string" || merged.name.length === 0) {
    throw new Error("name must be a non-empty string");
  }
  if (typeof merged.symbol !== "string" || merged.symbol.length === 0) {
    throw new Error("symbol must be a non-empty string");
  }
  if (typeof merged.baseUri !== "string") {
    throw new Error("baseUri must be a string");
  }

  const paymentTokenInput = coalesce(
    cliConfig.paymentToken,
    npmConfig.paymentToken,
    envConfig.paymentToken,
    fileConfig.paymentToken,
    DEFAULTS.paymentToken,
    ethers.ZeroAddress
  );
  const treasuryInput = coalesce(
    cliConfig.treasury,
    npmConfig.treasury,
    envConfig.treasury,
    fileConfig.treasury,
    fallbackTreasury
  );
  merged.paymentToken = parseAddress(String(paymentTokenInput), "paymentToken", ethers);
  merged.treasury = parseAddress(String(treasuryInput), "treasury", ethers, { allowZero: false });
  const treasurySignerRefInput = coalesce(
    cliConfig.treasurySignerRef,
    npmConfig.treasurySignerRef,
    envConfig.treasurySignerRef,
    fileConfig.treasurySignerRef
  );
  if (treasurySignerRefInput !== undefined && treasurySignerRefInput !== null) {
    if (typeof treasurySignerRefInput !== "string" || treasurySignerRefInput.trim().length === 0) {
      throw new Error("treasurySignerRef must be a non-empty string when provided");
    }
    merged.treasurySignerRef = treasurySignerRefInput.trim();
  } else {
    merged.treasurySignerRef = null;
  }

  const openTimeRaw = coalesce(cliConfig.openTime, npmConfig.openTime, envConfig.openTime, fileConfig.openTime);
  const startDelayRaw = coalesce(
    cliConfig.startDelaySec,
    npmConfig.startDelaySec,
    envConfig.startDelaySec,
    fileConfig.startDelaySec
  );

  if (openTimeRaw !== undefined && startDelayRaw !== undefined) {
    throw new Error("AMBIGUOUS_LAUNCH_TIME: set only one of openTime or startDelaySec");
  }

  if (openTimeRaw !== undefined) {
    merged.openTime = parseUint(openTimeRaw, "openTime");
    merged.openTimeSource = "explicit";
    merged.startDelaySec = null;
    if (merged.openTime > U64_MAX) {
      throw new Error(`openTime exceeds uint64 max: ${merged.openTime.toString()}`);
    }
    merged.openTimeIso = unixSecondsToIso(merged.openTime);
  } else if (startDelayRaw !== undefined) {
    const startDelaySec = parseUint(startDelayRaw, "startDelaySec");
    merged.openTime = null;
    merged.openTimeSource = "derived_delay";
    merged.startDelaySec = startDelaySec;
    merged.openTimeIso = null;
  } else if (isLocalLikeNetwork(networkName, chainId)) {
    merged.openTime = null;
    merged.openTimeSource = "default_local_now";
    merged.startDelaySec = 0n;
    merged.openTimeIso = null;
  } else {
    throw new Error("OPEN_TIME_REQUIRED: provide openTime (recommended) or startDelaySec");
  }

  return merged;
}

async function readLatestTimestamp(provider) {
  const latestBlock = await provider.getBlock("latest");
  if (!latestBlock) {
    throw new Error("Failed to read latest block");
  }
  return BigInt(latestBlock.timestamp);
}

async function resolveAuctionOpenTime({ provider, cfg }) {
  const latestBlockTimestamp = await readLatestTimestamp(provider);
  let openTime;

  if (cfg.openTimeSource === "explicit") {
    openTime = cfg.openTime;
  } else {
    const startDelaySec = cfg.startDelaySec ?? 0n;
    const requestedOpenTime = latestBlockTimestamp + startDelaySec;
    openTime = requestedOpenTime > latestBlockTimestamp
      ? requestedOpenTime
      : latestBlockTimestamp + 1n;
  }

  if (openTime > U64_MAX) {
    throw new Error(`openTime exceeds uint64 max: ${openTime.toString()}`);
  }
  if (openTime < latestBlockTimestamp) {
    throw new Error(
      `OPEN_TIME_IN_PAST: openTime=${openTime.toString()} latestBlockTs=${latestBlockTimestamp.toString()}`
    );
  }

  const startDelaySec = openTime - latestBlockTimestamp;
  if (startDelaySec > U64_MAX) {
    throw new Error(`startDelaySec exceeds uint64 max: ${startDelaySec.toString()}`);
  }

  return {
    openTime,
    openTimeIso: unixSecondsToIso(openTime),
    latestBlockTimestamp,
    startDelaySec
  };
}

async function main() {
  const conn = await hre.network.connect();
  const { ethers } = conn;

  const [deployer, , defaultTreasurySigner] = await ethers.getSigners();
  const networkInfo = await ethers.provider.getNetwork();
  const minterRole = ethers.id("MINTER_ROLE");
  const salesRole = ethers.id("SALES_ROLE");

  const cliConfig = parseCliConfig(process.argv.slice(2));
  const npmConfig = readNpmConfig(process.env);
  const envConfig = readEnvConfig(process.env);
  const paramsFile = cliConfig.paramsFile ?? npmConfig.paramsFile ?? envConfig.paramsFile;
  const fileConfig = await readParamsFile(paramsFile);
  const cfg = resolveDeployConfig({
    cliConfig,
    npmConfig,
    envConfig,
    fileConfig,
    ethers,
    fallbackTreasury: defaultTreasurySigner?.address ?? deployer.address,
    networkName: conn.networkName,
    chainId: networkInfo.chainId
  });

  const PathNFT = await ethers.getContractFactory("PathNFT", deployer);
  const nft = await PathNFT.deploy(
    deployer.address,
    cfg.name,
    cfg.symbol,
    cfg.baseUri
  );
  await nft.waitForDeployment();

  const PathMinter = await ethers.getContractFactory("PathMinter", deployer);
  const minter = await PathMinter.deploy(
    deployer.address,
    await nft.getAddress(),
    cfg.firstPublicId,
    cfg.reservedCap
  );
  await minter.waitForDeployment();

  const PathMinterAdapter = await ethers.getContractFactory("PathMinterAdapter", deployer);
  const adapter = await PathMinterAdapter.deploy(
    deployer.address,
    ethers.ZeroAddress,
    await minter.getAddress(),
    cfg.firstPublicId,
    cfg.epochBase
  );
  await adapter.waitForDeployment();

  const resolvedLaunch = await resolveAuctionOpenTime({
    provider: ethers.provider,
    cfg
  });

  const PulseAuction = await ethers.getContractFactory("PulseAuction", deployer);
  const auction = await PulseAuction.deploy(
    resolvedLaunch.startDelaySec,
    cfg.k,
    cfg.genesisPrice,
    cfg.genesisFloor,
    cfg.pts,
    cfg.paymentToken,
    cfg.treasury,
    await adapter.getAddress()
  );
  await auction.waitForDeployment();

  await (await adapter.setAuction(await auction.getAddress())).wait();
  await (await adapter.freezeWiring()).wait();
  await (await nft.grantRole(minterRole, await minter.getAddress())).wait();
  await (await minter.grantRole(salesRole, await adapter.getAddress())).wait();
  await (await minter.freezeSalesCaller(await adapter.getAddress())).wait();

  const contractAddresses = {
    pathNft: await nft.getAddress(),
    pathMinter: await minter.getAddress(),
    pathMinterAdapter: await adapter.getAddress(),
    pulseAuction: await auction.getAddress()
  };
  const deployTxs = {
    pathNft: nft.deploymentTransaction()?.hash ?? null,
    pathMinter: minter.deploymentTransaction()?.hash ?? null,
    pathMinterAdapter: adapter.deploymentTransaction()?.hash ?? null,
    pulseAuction: auction.deploymentTransaction()?.hash ?? null
  };
  const codeHashes = {};
  for (const [name, address] of Object.entries(contractAddresses)) {
    const code = await ethers.provider.getCode(address);
    codeHashes[name] = ethers.keccak256(code);
  }

  const deployment = {
    network: conn.networkName,
    chainId: Number(networkInfo.chainId),
    launchResolutionBlockTimestamp: resolvedLaunch.latestBlockTimestamp.toString(),
    deployer: deployer.address,
    treasury: cfg.treasury,
    paymentToken: cfg.paymentToken,
    contracts: contractAddresses,
    deployTxs,
    codeHashes,
    config: {
      name: cfg.name,
      symbol: cfg.symbol,
      baseUri: cfg.baseUri,
      openTime: resolvedLaunch.openTime.toString(),
      openTimeIso: resolvedLaunch.openTimeIso,
      openTimeSource: cfg.openTimeSource,
      startDelaySec: resolvedLaunch.startDelaySec.toString(),
      requestedStartDelaySec: cfg.startDelaySec == null ? null : cfg.startDelaySec.toString(),
      k: cfg.k.toString(),
      genesisPrice: cfg.genesisPrice.toString(),
      genesisFloor: cfg.genesisFloor.toString(),
      pts: cfg.pts.toString(),
      firstPublicId: cfg.firstPublicId.toString(),
      tokenBase: cfg.firstPublicId.toString(),
      epochBase: cfg.epochBase.toString(),
      reservedCap: cfg.reservedCap.toString()
    },
    inputs: {
      paramsFile: fileConfig.paramsFile ?? null,
      cli: cliConfig,
      npm: npmConfig,
      env: Object.fromEntries(Object.keys(envConfig).map((key) => [key, envConfig[key]]))
    },
    roles: {
      minterRole,
      salesRole
    }
  };

  if (cfg.treasurySignerRef) {
    deployment.references = {
      treasury: {
        address: cfg.treasury,
        SIGNER_REF: cfg.treasurySignerRef
      }
    };
  }

  const outFile = process.env.DEPLOY_OUT_FILE
    ? path.resolve(process.env.DEPLOY_OUT_FILE)
    : path.join(path.resolve(here, "../deployments"), `${conn.networkName}-eth.json`);
  await fs.mkdir(path.dirname(outFile), { recursive: true });
  await fs.writeFile(outFile, `${JSON.stringify(deployment, null, 2)}\n`, "utf8");

  console.log(`[deploy-local-eth] deployment saved to ${outFile}`);
  if (cfg.treasurySignerRef) {
    console.log(
      `[deploy-local-eth] treasury ref address=${cfg.treasury} SIGNER_REF=${cfg.treasurySignerRef}`
    );
  }
  console.log(JSON.stringify(deployment, null, 2));

  await conn.close();
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
