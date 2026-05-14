import {
  BASE_URI,
  EPOCH_BASE,
  FIRST_PUBLIC_ID,
  GENESIS_FLOOR,
  GENESIS_PRICE,
  K,
  NAME,
  PTS,
  SYMBOL
} from "./constants.js";

export function movementBytes32(ethers, label) {
  return ethers.encodeBytes32String(label);
}

export function roleId(ethers, label) {
  return ethers.id(label);
}

export async function deployPathNftEnv(ethers, { admin } = {}) {
  const [deployer] = await ethers.getSigners();
  const owner = admin ?? deployer.address;

  const Nft = await ethers.getContractFactory("PathNFT", deployer);
  const nft = await Nft.deploy(owner, NAME, SYMBOL, BASE_URI);
  await nft.waitForDeployment();

  return {
    deployer,
    nft,
    roles: {
      DEFAULT_ADMIN_ROLE: await nft.DEFAULT_ADMIN_ROLE(),
      MINTER_ROLE: roleId(ethers, "MINTER_ROLE"),
      FROZEN_MINTER_ADMIN_ROLE: roleId(ethers, "FROZEN_MINTER_ADMIN_ROLE")
    },
    movements: {
      THOUGHT: movementBytes32(ethers, "THOUGHT"),
      WILL: movementBytes32(ethers, "WILL"),
      AWA: movementBytes32(ethers, "AWA"),
      DREAM: movementBytes32(ethers, "DREAM")
    }
  };
}

export async function deployPathMinterEnv(ethers, { firstPublicId = FIRST_PUBLIC_ID } = {}) {
  const [deployer] = await ethers.getSigners();
  const nftEnv = await deployPathNftEnv(ethers, { admin: deployer.address });

  const Minter = await ethers.getContractFactory("PathMinter", deployer);
  const minter = await Minter.deploy(
    deployer.address,
    await nftEnv.nft.getAddress(),
    firstPublicId
  );
  await minter.waitForDeployment();

  return {
    ...nftEnv,
    minter,
    roles: {
      ...nftEnv.roles,
      SALES_ROLE: roleId(ethers, "SALES_ROLE")
    }
  };
}

async function deployPathPulseEnv(
  ethers,
  { openTime, startDelaySec = 0n, paymentToken = ethers.ZeroAddress, freezePublicMinterTo } = {}
) {
  const [deployer, alice, bob, treasury] = await ethers.getSigners();

  const nftEnv = await deployPathNftEnv(ethers, { admin: deployer.address });

  const Adapter = await ethers.getContractFactory("PathPulseAdapter", deployer);
  const adapter = await Adapter.deploy(
    deployer.address,
    ethers.ZeroAddress,
    await nftEnv.nft.getAddress(),
    FIRST_PUBLIC_ID,
    EPOCH_BASE
  );
  await adapter.waitForDeployment();

  const resolvedOpenTime = openTime ?? await resolveOpenTime(ethers, startDelaySec);
  const Auction = await ethers.getContractFactory("PulseAuction", deployer);
  const auction = await Auction.deploy(
    resolvedOpenTime,
    K,
    GENESIS_PRICE,
    GENESIS_FLOOR,
    PTS,
    paymentToken,
    treasury.address,
    await adapter.getAddress()
  );
  await auction.waitForDeployment();

  await (await adapter.setAuction(await auction.getAddress())).wait();
  await (await adapter.freezeWiring()).wait();
  const adapterAddress = await adapter.getAddress();
  await (await nftEnv.nft.grantRole(nftEnv.roles.MINTER_ROLE, adapterAddress)).wait();
  const publicMinter = freezePublicMinterTo ?? adapterAddress;
  if (publicMinter.toLowerCase() !== adapterAddress.toLowerCase()) {
    await (await nftEnv.nft.grantRole(nftEnv.roles.MINTER_ROLE, publicMinter)).wait();
  }
  await (await nftEnv.nft.freezePublicMinter(publicMinter)).wait();

  return {
    deployer,
    alice,
    bob,
    treasury,
    ...nftEnv,
    adapter,
    auction,
    roles: nftEnv.roles
  };
}

async function resolveOpenTime(ethers, startDelaySec) {
  const latestBlock = await ethers.provider.getBlock("latest");
  if (!latestBlock) {
    throw new Error("Failed to resolve latest block timestamp");
  }
  const latest = BigInt(latestBlock.timestamp);
  const requested = latest + BigInt(startDelaySec);
  return requested > latest ? requested : latest + 1n;
}

export async function deployPathPulseEthEnv(
  ethers,
  { openTime, startDelaySec = 0n, freezePublicMinterTo } = {}
) {
  return deployPathPulseEnv(ethers, {
    openTime,
    startDelaySec,
    paymentToken: ethers.ZeroAddress,
    freezePublicMinterTo
  });
}

export async function deployPathPulseErc20Env(
  ethers,
  { openTime, startDelaySec = 0n, tokenName = "Mock USD", tokenSymbol = "mUSD", tokenDecimals = 18 } = {}
) {
  const [deployer] = await ethers.getSigners();
  const MockErc20 = await ethers.getContractFactory("MockERC20", deployer);
  const paymentToken = await MockErc20.deploy(tokenName, tokenSymbol, tokenDecimals);
  await paymentToken.waitForDeployment();

  const env = await deployPathPulseEnv(ethers, {
    openTime,
    startDelaySec,
    paymentToken: await paymentToken.getAddress()
  });

  return { ...env, paymentToken };
}

export async function getSaleEventFromReceipt(auction, receipt) {
  const logs = await auction.queryFilter(
    auction.filters.Sale(),
    receipt.blockNumber,
    receipt.blockNumber
  );

  if (logs.length === 0) {
    throw new Error("Sale event not found in receipt block");
  }

  return logs[0].args;
}
