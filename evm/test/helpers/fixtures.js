import {
  BASE_URI,
  FIRST_PUBLIC_ID,
  GENESIS_FLOOR,
  GENESIS_PRICE,
  K,
  NAME,
  PTS,
  RESERVED_CAP,
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
      MINTER_ROLE: roleId(ethers, "MINTER_ROLE")
    },
    movements: {
      THOUGHT: movementBytes32(ethers, "THOUGHT"),
      WILL: movementBytes32(ethers, "WILL"),
      AWA: movementBytes32(ethers, "AWA"),
      DREAM: movementBytes32(ethers, "DREAM")
    }
  };
}

export async function deployPathMinterEnv(ethers, { firstPublicId = FIRST_PUBLIC_ID, reservedCap = RESERVED_CAP } = {}) {
  const [deployer] = await ethers.getSigners();
  const nftEnv = await deployPathNftEnv(ethers, { admin: deployer.address });

  const Minter = await ethers.getContractFactory("PathMinter", deployer);
  const minter = await Minter.deploy(
    deployer.address,
    await nftEnv.nft.getAddress(),
    firstPublicId,
    reservedCap
  );
  await minter.waitForDeployment();

  return {
    ...nftEnv,
    minter,
    roles: {
      ...nftEnv.roles,
      SALES_ROLE: roleId(ethers, "SALES_ROLE"),
      RESERVED_ROLE: roleId(ethers, "RESERVED_ROLE")
    }
  };
}

export async function deployPathPulseEthEnv(ethers, { startDelaySec = 0n } = {}) {
  const [deployer, alice, bob, treasury] = await ethers.getSigners();

  const nftEnv = await deployPathNftEnv(ethers, { admin: deployer.address });

  const Minter = await ethers.getContractFactory("PathMinter", deployer);
  const minter = await Minter.deploy(
    deployer.address,
    await nftEnv.nft.getAddress(),
    FIRST_PUBLIC_ID,
    RESERVED_CAP
  );
  await minter.waitForDeployment();

  const Adapter = await ethers.getContractFactory("PathMinterAdapter", deployer);
  const adapter = await Adapter.deploy(deployer.address, ethers.ZeroAddress, await minter.getAddress());
  await adapter.waitForDeployment();

  const Auction = await ethers.getContractFactory("PulseAuction", deployer);
  const auction = await Auction.deploy(
    startDelaySec,
    K,
    GENESIS_PRICE,
    GENESIS_FLOOR,
    PTS,
    ethers.ZeroAddress,
    treasury.address,
    await adapter.getAddress()
  );
  await auction.waitForDeployment();

  await (await adapter.setAuction(await auction.getAddress())).wait();
  await (await nftEnv.nft.grantRole(nftEnv.roles.MINTER_ROLE, await minter.getAddress())).wait();
  await (await minter.grantRole(roleId(ethers, "SALES_ROLE"), await adapter.getAddress())).wait();

  return {
    deployer,
    alice,
    bob,
    treasury,
    ...nftEnv,
    minter,
    adapter,
    auction,
    roles: {
      ...nftEnv.roles,
      SALES_ROLE: roleId(ethers, "SALES_ROLE"),
      RESERVED_ROLE: roleId(ethers, "RESERVED_ROLE")
    }
  };
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
