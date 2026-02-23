import hre from "hardhat";

const START_DELAY_SEC = 0n;
const K = 600n;
const GENESIS_PRICE = 1_000n;
const GENESIS_FLOOR = 900n;
const PTS = 1n;
const FIRST_PUBLIC_ID = 0n;
const RESERVED_CAP = 3n;

const NAME = "PATH NFT";
const SYMBOL = "PATH";
const BASE_URI = "";

const DUMMY_ADDRESS = "0x000000000000000000000000000000000000dEaD";

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

async function estimateDeployments(ethers, deployer) {
  const Nft = await ethers.getContractFactory("PathNFT", deployer);
  const nftTx = await Nft.getDeployTransaction(deployer.address, NAME, SYMBOL, BASE_URI);
  nftTx.from = deployer.address;
  const nftGas = await ethers.provider.estimateGas(nftTx);

  const Minter = await ethers.getContractFactory("PathMinter", deployer);
  const minterTx = await Minter.getDeployTransaction(deployer.address, DUMMY_ADDRESS, FIRST_PUBLIC_ID, RESERVED_CAP);
  minterTx.from = deployer.address;
  const minterGas = await ethers.provider.estimateGas(minterTx);

  const Adapter = await ethers.getContractFactory("PathMinterAdapter", deployer);
  const adapterTx = await Adapter.getDeployTransaction(deployer.address, DUMMY_ADDRESS, DUMMY_ADDRESS);
  adapterTx.from = deployer.address;
  const adapterGas = await ethers.provider.estimateGas(adapterTx);

  const Auction = await ethers.getContractFactory("PulseAuction", deployer);
  const auctionTx = await Auction.getDeployTransaction(
    START_DELAY_SEC,
    K,
    GENESIS_PRICE,
    GENESIS_FLOOR,
    PTS,
    ethers.ZeroAddress,
    deployer.address,
    DUMMY_ADDRESS
  );
  auctionTx.from = deployer.address;
  const auctionGas = await ethers.provider.estimateGas(auctionTx);

  const totalGas = nftGas + minterGas + adapterGas + auctionGas;

  return {
    nftGas,
    minterGas,
    adapterGas,
    auctionGas,
    totalGas
  };
}

async function estimateWiringGas(ethers, deployer) {
  const Nft = await ethers.getContractFactory("PathNFT", deployer);
  const nft = await Nft.deploy(deployer.address, NAME, SYMBOL, BASE_URI);
  await nft.waitForDeployment();

  const Minter = await ethers.getContractFactory("PathMinter", deployer);
  const minter = await Minter.deploy(deployer.address, await nft.getAddress(), FIRST_PUBLIC_ID, RESERVED_CAP);
  await minter.waitForDeployment();

  const Adapter = await ethers.getContractFactory("PathMinterAdapter", deployer);
  const adapter = await Adapter.deploy(deployer.address, ethers.ZeroAddress, await minter.getAddress());
  await adapter.waitForDeployment();

  const Auction = await ethers.getContractFactory("PulseAuction", deployer);
  const auction = await Auction.deploy(
    START_DELAY_SEC,
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
  const salesRole = ethers.id("SALES_ROLE");

  const setAuctionGas = await adapter.setAuction.estimateGas(await auction.getAddress());
  const grantMinterRoleGas = await nft.grantRole.estimateGas(minterRole, await minter.getAddress());
  const grantSalesRoleGas = await minter.grantRole.estimateGas(salesRole, await adapter.getAddress());

  const totalGas = setAuctionGas + grantMinterRoleGas + grantSalesRoleGas;

  return {
    setAuctionGas,
    grantMinterRoleGas,
    grantSalesRoleGas,
    totalGas
  };
}

async function main() {
  const conn = await hre.network.connect();
  const { ethers } = conn;
  const [deployer] = await ethers.getSigners();

  const deployments = await estimateDeployments(ethers, deployer);
  const wiring = await estimateWiringGas(ethers, deployer);
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
  printRow("PathMinter", deployments.minterGas, gasPrice.gwei, ethUsd.usd);
  printRow("PathMinterAdapter", deployments.adapterGas, gasPrice.gwei, ethUsd.usd);
  printRow("PulseAuction", deployments.auctionGas, gasPrice.gwei, ethUsd.usd);
  printRow("DEPLOY TOTAL", deployments.totalGas, gasPrice.gwei, ethUsd.usd);

  console.log("");
  console.log("Estimated wiring gas:");
  printRow("adapter.setAuction", wiring.setAuctionGas, gasPrice.gwei, ethUsd.usd);
  printRow("nft.grantRole", wiring.grantMinterRoleGas, gasPrice.gwei, ethUsd.usd);
  printRow("minter.grantRole", wiring.grantSalesRoleGas, gasPrice.gwei, ethUsd.usd);
  printRow("WIRING TOTAL", wiring.totalGas, gasPrice.gwei, ethUsd.usd);

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
