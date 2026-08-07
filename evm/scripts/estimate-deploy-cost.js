import hre from "hardhat";

const OPEN_TIME_OFFSET_SEC = 60n;
const K = 600n;
const GENESIS_PRICE = 1_000n;
const GENESIS_FLOOR = 900n;
const PTS = 1n;
const FIRST_PUBLIC_ID = 1n;
const EPOCH_BASE = 1n;
const MOVEMENT_QUOTAS = { THOUGHT: 1n, WILL: 10n, AWA: 1n };
const RESERVED_CAP = BigInt(process.env.DEPLOY_RESERVED_CAP ?? "99");
const SPARK_CLAIM_DURATION_SEC = BigInt(
  process.env.DEPLOY_SPARK_CLAIM_DURATION_SEC ?? "604800"
);

const NAME = "PATH";
const SYMBOL = "PATH";
const BASE_URI = "";

async function resolveOpenTime(provider) {
  const latestBlock = await provider.getBlock("latest");
  if (!latestBlock) {
    throw new Error("Failed to read latest block for openTime");
  }
  return BigInt(latestBlock.timestamp) + OPEN_TIME_OFFSET_SEC;
}

function parsePositiveNumber(raw, name) {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) {
    throw new Error(`${name} must be a positive number. Received: ${raw}`);
  }
  return n;
}

function parseScenarioList(raw) {
  return raw
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
    .map((s) => parsePositiveNumber(s, "GAS_SCENARIOS_GWEI"));
}

async function fetchJson(url, timeoutMs = 8_000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) {
      throw new Error(`HTTP ${res.status}`);
    }
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

async function resolveGasPriceGwei(provider) {
  if (process.env.GAS_PRICE_GWEI) {
    return {
      gwei: parsePositiveNumber(process.env.GAS_PRICE_GWEI, "GAS_PRICE_GWEI"),
      source: "env:GAS_PRICE_GWEI"
    };
  }

  const etherscanUrls = [
    "https://api.etherscan.io/v2/api?chainid=1&module=gastracker&action=gasoracle",
    "https://api.etherscan.io/api?module=gastracker&action=gasoracle"
  ];

  for (const url of etherscanUrls) {
    try {
      const data = await fetchJson(url);
      const candidate =
        data?.result?.ProposeGasPrice ??
        data?.result?.suggestBaseFee ??
        data?.result?.SafeGasPrice;
      if (candidate) {
        const gwei = parsePositiveNumber(candidate, "etherscan gas price");
        return { gwei, source: `etherscan:${url}` };
      }
    } catch {
      // Try next source.
    }
  }

  const feeData = await provider.getFeeData();
  const gasPriceWei = feeData.gasPrice ?? feeData.maxFeePerGas;
  if (!gasPriceWei) {
    throw new Error(
      "Failed to resolve gas price. Set GAS_PRICE_GWEI explicitly, e.g. GAS_PRICE_GWEI=20"
    );
  }

  const gwei = Number(gasPriceWei) / 1e9;
  return { gwei, source: "provider:getFeeData" };
}

async function resolveEthUsd() {
  if (process.env.ETH_USD) {
    return {
      usd: parsePositiveNumber(process.env.ETH_USD, "ETH_USD"),
      source: "env:ETH_USD"
    };
  }

  try {
    const data = await fetchJson(
      "https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd"
    );
    const usd = data?.ethereum?.usd;
    if (usd) {
      return { usd: parsePositiveNumber(usd, "coingecko ETH/USD"), source: "coingecko" };
    }
  } catch {
    // Fallback to no USD conversion.
  }

  return { usd: null, source: "unavailable" };
}

function formatUsd(usd) {
  return `$${usd.toFixed(2)}`;
}

function formatCost(gasUsed, gasPriceGwei, ethUsd) {
  const gas = Number(gasUsed);
  const eth = (gas * gasPriceGwei) / 1e9;
  return {
    eth,
    usd: ethUsd == null ? null : eth * ethUsd
  };
}

function printRow(label, gasUsed, gasPriceGwei, ethUsd) {
  const cost = formatCost(gasUsed, gasPriceGwei, ethUsd);
  const usdPart = cost.usd == null ? "n/a" : formatUsd(cost.usd);
  console.log(
    `${label.padEnd(22)} gas=${gasUsed.toString().padStart(8)}  cost=${cost.eth
      .toFixed(9)
      .padStart(12)} ETH  (${usdPart})`
  );
}

async function deploymentGas(contract) {
  const tx = contract.deploymentTransaction();
  if (!tx) {
    throw new Error("missing deployment transaction");
  }
  const receipt = await tx.wait();
  if (!receipt) {
    throw new Error("missing deployment receipt");
  }
  return receipt.gasUsed;
}

async function txGas(txPromise) {
  const tx = await txPromise;
  const receipt = await tx.wait();
  if (!receipt) {
    throw new Error("missing transaction receipt");
  }
  return receipt.gasUsed;
}

async function estimateDeployments(ethers, deployer) {
  const openTime = await resolveOpenTime(ethers.provider);

  const Nft = await ethers.getContractFactory("PathNFT", deployer);
  const nft = await Nft.deploy(deployer.address, NAME, SYMBOL, BASE_URI, RESERVED_CAP, SPARK_CLAIM_DURATION_SEC);
  const nftGas = await deploymentGas(nft);

  const Adapter = await ethers.getContractFactory("PathPulseAdapter", deployer);
  const adapter = await Adapter.deploy(
    deployer.address,
    ethers.ZeroAddress,
    await nft.getAddress(),
    FIRST_PUBLIC_ID,
    EPOCH_BASE
  );
  const adapterGas = await deploymentGas(adapter);

  const Auction = await ethers.getContractFactory("PulseAuction", deployer);
  const auction = await Auction.deploy(
    openTime,
    K,
    GENESIS_PRICE,
    GENESIS_FLOOR,
    PTS,
    ethers.ZeroAddress,
    deployer.address,
    await adapter.getAddress()
  );
  const auctionGas = await deploymentGas(auction);

  const totalGas = nftGas + adapterGas + auctionGas;

  return {
    nftGas,
    adapterGas,
    auctionGas,
    totalGas
  };
}

async function estimateWiringAndAuthorityGas(ethers, deployer, finalAdmin) {
  const openTime = await resolveOpenTime(ethers.provider);

  const Nft = await ethers.getContractFactory("PathNFT", deployer);
  const nft = await Nft.deploy(deployer.address, NAME, SYMBOL, BASE_URI, RESERVED_CAP, SPARK_CLAIM_DURATION_SEC);
  await nft.waitForDeployment();

  const Adapter = await ethers.getContractFactory("PathPulseAdapter", deployer);
  const adapter = await Adapter.deploy(
    deployer.address,
    ethers.ZeroAddress,
    await nft.getAddress(),
    FIRST_PUBLIC_ID,
    EPOCH_BASE
  );
  await adapter.waitForDeployment();

  const Auction = await ethers.getContractFactory("PulseAuction", deployer);
  const auction = await Auction.deploy(
    openTime,
    K,
    GENESIS_PRICE,
    GENESIS_FLOOR,
    PTS,
    ethers.ZeroAddress,
    deployer.address,
    await adapter.getAddress()
  );
  await auction.waitForDeployment();

  const minterRole = ethers.id("MINTER_ROLE");
  const defaultAdminRole = await nft.DEFAULT_ADMIN_ROLE();

  const movementConfigGas = {};
  for (const label of Object.keys(MOVEMENT_QUOTAS)) {
    const movement = await nft[`MOVEMENT_${label}`]();
    const setGas = await txGas(nft.setMovementConfig(movement, deployer.address, MOVEMENT_QUOTAS[label]));
    const freezeGas = await txGas(nft.freezeMovementConfig(movement));
    movementConfigGas[label] = { setGas, freezeGas };
  }
  const movementConfigTotalGas = Object.values(movementConfigGas)
    .reduce((total, item) => total + item.setGas + item.freezeGas, 0n);

  const setAuctionGas = await txGas(adapter.setAuction(await auction.getAddress()));
  const freezeWiringGas = await txGas(adapter.freezeWiring());
  const grantMinterRoleGas = await txGas(nft.grantRole(minterRole, await adapter.getAddress()));
  const freezePublicMinterGas = await txGas(nft.freezePublicMinter(await adapter.getAddress()));
  const grantNftAdminGas = await txGas(nft.grantRole(defaultAdminRole, finalAdmin.address));
  const renounceNftAdminGas = await txGas(nft.renounceRole(defaultAdminRole, deployer.address));
  const transferAdapterOwnerGas = await txGas(adapter.transferOwnership(finalAdmin.address));

  const wiringTotalGas =
    setAuctionGas
    + freezeWiringGas
    + grantMinterRoleGas
    + freezePublicMinterGas;
  const authorityTotalGas =
    grantNftAdminGas
    + renounceNftAdminGas
    + transferAdapterOwnerGas;

  return {
    setAuctionGas,
    freezeWiringGas,
    grantMinterRoleGas,
    freezePublicMinterGas,
    movementConfigGas,
    movementConfigTotalGas,
    wiringTotalGas,
    grantNftAdminGas,
    renounceNftAdminGas,
    transferAdapterOwnerGas,
    authorityTotalGas,
    totalGas: movementConfigTotalGas + wiringTotalGas + authorityTotalGas
  };
}

async function estimateSparkIssuanceGas(ethers, deployer, recipient) {
  const Nft = await ethers.getContractFactory("PathNFT", deployer);
  const nft = await Nft.deploy(
    deployer.address,
    NAME,
    SYMBOL,
    BASE_URI,
    RESERVED_CAP === 0n ? 1n : RESERVED_CAP,
    SPARK_CLAIM_DURATION_SEC
  );
  await nft.waitForDeployment();

  const reservedRole = ethers.id("RESERVED_ROLE");
  const sparkName = "Gas Sample";
  const expectedNameHash = ethers.keccak256(ethers.toUtf8Bytes(sparkName));
  const grantReservedRoleGas = await txGas(nft.grantRole(reservedRole, deployer.address));
  const allowSparkerGas = await txGas(nft.allowSparker(recipient.address, sparkName));
  const mintSparkerGas = await txGas(
    nft.connect(recipient).mintSparker(expectedNameHash, "0x")
  );

  return {
    grantReservedRoleGas,
    allowSparkerGas,
    mintSparkerGas,
    totalGas: grantReservedRoleGas + allowSparkerGas + mintSparkerGas
  };
}

async function main() {
  const conn = await hre.network.connect();
  const { ethers } = conn;
  const allowedLiveEstimateNetworks = new Set(["default", "hardhat", "localhost"]);
  if (!allowedLiveEstimateNetworks.has(conn.networkName)) {
    await conn.close();
    throw new Error(
      `estimate-deploy-cost sends live deploy/wiring/authority transactions and is only allowed on hardhat(default)/localhost. Refusing network: ${conn.networkName}`
    );
  }
  const [deployer, finalAdmin, sparkRecipient] = await ethers.getSigners();

  const deployments = await estimateDeployments(ethers, deployer);
  const wiring = await estimateWiringAndAuthorityGas(ethers, deployer, finalAdmin);
  const spark = await estimateSparkIssuanceGas(ethers, deployer, sparkRecipient);
  const combinedGas = deployments.totalGas + wiring.totalGas;

  const gasPrice = await resolveGasPriceGwei(ethers.provider);
  const ethUsd = await resolveEthUsd();

  const scenarioGasPrices = process.env.GAS_SCENARIOS_GWEI
    ? parseScenarioList(process.env.GAS_SCENARIOS_GWEI)
    : [1, 5, 10, 20, 30];

  console.log("[estimate-deploy-cost]");
  console.log(`network: ${conn.networkName}`);
  console.log(`gas price source: ${gasPrice.source}`);
  console.log(`ETH/USD source: ${ethUsd.source}`);
  console.log(`assumed gas price: ${gasPrice.gwei} gwei`);
  if (ethUsd.usd != null) {
    console.log(`assumed ETH/USD: ${ethUsd.usd}`);
  }
  console.log("");

  console.log("Estimated deployment gas:");
  printRow("PathNFT", deployments.nftGas, gasPrice.gwei, ethUsd.usd);
  printRow("PathPulseAdapter", deployments.adapterGas, gasPrice.gwei, ethUsd.usd);
  printRow("PulseAuction", deployments.auctionGas, gasPrice.gwei, ethUsd.usd);
  printRow("DEPLOY TOTAL", deployments.totalGas, gasPrice.gwei, ethUsd.usd);

  console.log("");
  console.log("Estimated movement configuration gas:");
  for (const [label, item] of Object.entries(wiring.movementConfigGas)) {
    printRow(`nft.set${label}`, item.setGas, gasPrice.gwei, ethUsd.usd);
    printRow(`nft.freeze${label}`, item.freezeGas, gasPrice.gwei, ethUsd.usd);
  }
  printRow("MOVEMENT TOTAL", wiring.movementConfigTotalGas, gasPrice.gwei, ethUsd.usd);

  console.log("");
  console.log("Estimated wiring gas:");
  printRow("adapter.setAuction", wiring.setAuctionGas, gasPrice.gwei, ethUsd.usd);
  printRow("adapter.freezeWiring", wiring.freezeWiringGas, gasPrice.gwei, ethUsd.usd);
  printRow("nft.grantRole", wiring.grantMinterRoleGas, gasPrice.gwei, ethUsd.usd);
  printRow("nft.freezeMinter", wiring.freezePublicMinterGas, gasPrice.gwei, ethUsd.usd);
  printRow("WIRING TOTAL", wiring.wiringTotalGas, gasPrice.gwei, ethUsd.usd);

  console.log("");
  console.log("Estimated authority-finalization gas:");
  printRow("nft.grantAdmin", wiring.grantNftAdminGas, gasPrice.gwei, ethUsd.usd);
  printRow("nft.renounceAdmin", wiring.renounceNftAdminGas, gasPrice.gwei, ethUsd.usd);
  printRow("adapter.transferOwner", wiring.transferAdapterOwnerGas, gasPrice.gwei, ethUsd.usd);
  printRow("AUTHORITY TOTAL", wiring.authorityTotalGas, gasPrice.gwei, ethUsd.usd);

  console.log("");
  console.log("Measured Spark issuance gas (separate from ALL-IN deployment total):");
  printRow("nft.grantReserved", spark.grantReservedRoleGas, gasPrice.gwei, ethUsd.usd);
  printRow("nft.allowSparker", spark.allowSparkerGas, gasPrice.gwei, ethUsd.usd);
  printRow("nft.mintSparker", spark.mintSparkerGas, gasPrice.gwei, ethUsd.usd);
  printRow("SPARK FLOW TOTAL", spark.totalGas, gasPrice.gwei, ethUsd.usd);

  console.log("");
  printRow("ALL-IN TOTAL", combinedGas, gasPrice.gwei, ethUsd.usd);

  console.log("");
  console.log("Scenario table for ALL-IN TOTAL (override with GAS_SCENARIOS_GWEI=1,5,10,...):");
  for (const gwei of scenarioGasPrices) {
    const totalCost = formatCost(combinedGas, gwei, ethUsd.usd);
    const usdPart = totalCost.usd == null ? "n/a" : formatUsd(totalCost.usd);
    console.log(
      `  ${gwei.toString().padStart(6)} gwei -> ${totalCost.eth
        .toFixed(9)
        .padStart(12)} ETH  (${usdPart})`
    );
  }

  await conn.close();
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
