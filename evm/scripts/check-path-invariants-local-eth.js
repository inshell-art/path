import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import hre from "hardhat";
import { Wallet } from "ethers";

const here = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_DEPLOY_FILE = path.resolve(here, "../deployments/localhost-eth.json");
const REPO_ROOT = path.resolve(here, "../..");
const EIP1967_IMPLEMENTATION_SLOT = "0x360894A13BA1A3210667C828492DB98DCA3E2076CC3735A920A3CA505D382BBC";
const MOVEMENT_LABELS = ["THOUGHT", "WILL", "AWA"];
const MOVEMENT_MINTER_SYMBOLS = {
  "@deployer": "deployer",
  "@pathNft": "pathNft",
  "@pathMinter": "pathMinter",
  "@pathMinterAdapter": "pathMinterAdapter",
  "@pulseAuction": "pulseAuction",
  "@zero": null
};

const EXPECTED_CHAIN_IDS = {
  localhost: 31337,
  sepolia: 11155111,
  mainnet: 1
};

function lower(value) {
  return String(value ?? "").toLowerCase();
}

function toBigInt(value) {
  return typeof value === "bigint" ? value : BigInt(value);
}

function normalizeUrl(value) {
  return String(value ?? "").trim().replace(/\/+$/, "").toLowerCase();
}

function normalizeHost(value) {
  const raw = String(value ?? "").trim().toLowerCase();
  if (raw === "") return "";
  try {
    return new URL(raw.includes("://") ? raw : `https://${raw}`).host.toLowerCase();
  } catch {
    return raw.replace(/^https?:\/\//, "").replace(/\/+$/, "");
  }
}

function hostFromUrl(value) {
  const normalized = normalizeUrl(value);
  if (normalized === "") return "";
  try {
    return new URL(normalized).host.toLowerCase();
  } catch {
    return "";
  }
}

function pickUrl(value) {
  if (!value) return "";
  if (typeof value === "string") return value;
  if (typeof value === "object") {
    if (typeof value.url === "string") return value.url;
    if (value.url) {
      const nestedUrl = pickUrl(value.url);
      if (nestedUrl) return nestedUrl;
    }
    if (typeof value.href === "string") return value.href;
  }
  return "";
}

function sameAddressSet(actualList, expectedList) {
  const actual = [...actualList].map(lower).sort();
  const expected = [...expectedList].map(lower).sort();
  return JSON.stringify(actual) === JSON.stringify(expected);
}

function roleMembers(roleMap, role) {
  return [...(roleMap.get(lower(role)) ?? new Set())].sort();
}

function expandUserPath(value) {
  const raw = String(value ?? "").trim();
  if (raw === "~") return os.homedir();
  if (raw.startsWith("~/")) return path.join(os.homedir(), raw.slice(2));
  return raw;
}

function trimTrailingNewline(value) {
  return String(value ?? "").replace(/\r?\n$/, "");
}

async function resolveConfiguredSigner(networkName) {
  const upper = String(networkName ?? "").toUpperCase();
  const privateKeyVar = `${upper}_PRIVATE_KEY`;
  const keystoreVar = `${upper}_DEPLOY_KEYSTORE_JSON`;
  const passwordVar = `${upper}_DEPLOY_KEYSTORE_PASSWORD`;
  const passwordFileVar = `${upper}_DEPLOY_KEYSTORE_PASSWORD_FILE`;

  const rawPrivateKey = String(process.env[privateKeyVar] ?? "").trim();
  if (rawPrivateKey) {
    try {
      const wallet = new Wallet(rawPrivateKey);
      return {
        address: wallet.address,
        source: `env:${privateKeyVar}`
      };
    } catch (error) {
      return {
        address: null,
        source: `env:${privateKeyVar}`,
        error: error?.message ?? String(error)
      };
    }
  }

  const keystoreRef = expandUserPath(process.env[keystoreVar] ?? "");
  if (!keystoreRef) {
    return {
      address: null,
      source: "none",
      error: "no signer env configured"
    };
  }

  const keystoreCandidates = [keystoreRef];
  if (keystoreRef.endsWith("/keystore.json")) {
    keystoreCandidates.push(keystoreRef.replace(/\/keystore\.json$/i, "/keystore"));
  }
  let keystorePath = "";
  for (const candidate of keystoreCandidates) {
    try {
      const stat = await fs.stat(candidate);
      if (stat.isFile()) {
        keystorePath = candidate;
        break;
      }
    } catch {
      // Keep scanning.
    }
  }
  if (!keystorePath) {
    return {
      address: null,
      source: `env:${keystoreVar}`,
      error: `keystore file not found: ${keystoreRef}`
    };
  }

  let password = String(process.env[passwordVar] ?? "");
  if (!password) {
    const passwordFile = expandUserPath(process.env[passwordFileVar] ?? "");
    if (passwordFile) {
      try {
        password = trimTrailingNewline(await fs.readFile(passwordFile, "utf8"));
      } catch (error) {
        return {
          address: null,
          source: `env:${keystoreVar}`,
          path: keystorePath,
          error: `failed to read password file: ${error?.message ?? String(error)}`
        };
      }
    }
  }
  if (!password) {
    return {
      address: null,
      source: `env:${keystoreVar}`,
      path: keystorePath,
      error: `missing ${passwordVar} or ${passwordFileVar}`
    };
  }

  try {
    const wallet = await Wallet.fromEncryptedJson(await fs.readFile(keystorePath, "utf8"), password);
    return {
      address: wallet.address,
      source: `keystore:${keystoreVar}`,
      path: keystorePath
    };
  } catch (error) {
    return {
      address: null,
      source: `keystore:${keystoreVar}`,
      path: keystorePath,
      error: `failed to decrypt keystore: ${error?.message ?? String(error)}`
    };
  }
}

function contractAddressBySymbol(symbol, deployment, ethers) {
  const key = MOVEMENT_MINTER_SYMBOLS[symbol];
  if (key === null) return ethers.ZeroAddress;
  if (!key) return null;
  if (key === "deployer") return deployment.deployer;
  return deployment.contracts?.[key] ?? null;
}

function resolveExpectedMovementMinter(raw, deployment, ethers) {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== "string") return null;
  const trimmed = raw.trim();
  if (trimmed === "") return null;
  if (trimmed.startsWith("@")) {
    return contractAddressBySymbol(trimmed, deployment, ethers);
  }
  return trimmed;
}

async function loadPolicy() {
  const explicit = process.env.POLICY_FILE;
  if (explicit) {
    return {
      policyPath: explicit,
      policy: JSON.parse(await fs.readFile(explicit, "utf8"))
    };
  }

  const networkHint = String(process.env.NETWORK || "devnet").trim() || "devnet";
  const candidates = [
    path.resolve(REPO_ROOT, `ops/policy/lane.${networkHint}.json`),
    path.resolve(REPO_ROOT, `ops/policy/lane.${networkHint}.example.json`),
    path.resolve(REPO_ROOT, "ops/policy/lane.devnet.json"),
    path.resolve(REPO_ROOT, "ops/policy/lane.devnet.example.json")
  ];
  for (const candidate of candidates) {
    try {
      const raw = await fs.readFile(candidate, "utf8");
      return { policyPath: candidate, policy: JSON.parse(raw) };
    } catch {
      // Keep scanning.
    }
  }
  return { policyPath: null, policy: {} };
}

async function queryFilterPaginated(contract, filter, fromBlock, toBlock, maxBlockRange) {
  if (!Number.isFinite(maxBlockRange) || maxBlockRange <= 0) {
    return contract.queryFilter(filter, fromBlock, toBlock);
  }

  const logs = [];
  let start = fromBlock;
  while (start <= toBlock) {
    const end = Math.min(toBlock, start + maxBlockRange - 1);
    const chunk = await contract.queryFilter(filter, start, end);
    logs.push(...chunk);
    start = end + 1;
  }
  return logs;
}

async function collectRoleMembers(contract) {
  let fromBlock = 0;
  if (arguments.length > 1 && Number.isFinite(arguments[1])) {
    fromBlock = Math.max(0, Number(arguments[1]));
  }
  const latestBlock = await contract.runner.provider.getBlockNumber();
  let maxBlockRange = 0;
  if (arguments.length > 2 && Number.isFinite(arguments[2])) {
    maxBlockRange = Math.max(0, Number(arguments[2]));
  }
  const grants = await queryFilterPaginated(
    contract,
    contract.filters.RoleGranted(),
    fromBlock,
    latestBlock,
    maxBlockRange
  );
  const revokes = await queryFilterPaginated(
    contract,
    contract.filters.RoleRevoked(),
    fromBlock,
    latestBlock,
    maxBlockRange
  );
  const events = [];

  for (const log of grants) {
    events.push({
      kind: "grant",
      blockNumber: Number(log.blockNumber),
      index: Number(log.index ?? log.logIndex ?? 0),
      role: lower(log.args?.role ?? log.args?.[0]),
      account: lower(log.args?.account ?? log.args?.[1])
    });
  }
  for (const log of revokes) {
    events.push({
      kind: "revoke",
      blockNumber: Number(log.blockNumber),
      index: Number(log.index ?? log.logIndex ?? 0),
      role: lower(log.args?.role ?? log.args?.[0]),
      account: lower(log.args?.account ?? log.args?.[1])
    });
  }

  events.sort((a, b) => {
    if (a.blockNumber !== b.blockNumber) return a.blockNumber - b.blockNumber;
    if (a.index !== b.index) return a.index - b.index;
    return a.kind === "revoke" ? 1 : -1;
  });

  const roleMap = new Map();
  for (const event of events) {
    if (!roleMap.has(event.role)) roleMap.set(event.role, new Set());
    const members = roleMap.get(event.role);
    if (event.kind === "grant") members.add(event.account);
    if (event.kind === "revoke") members.delete(event.account);
  }
  return roleMap;
}

async function resolveDeploymentBlock(provider, txHash) {
  if (!txHash) return null;
  try {
    const receipt = await provider.getTransactionReceipt(txHash);
    if (!receipt || receipt.blockNumber == null) return null;
    return Number(receipt.blockNumber);
  } catch {
    return null;
  }
}

async function main() {
  const deployFile = process.env.DEPLOY_FILE ?? DEFAULT_DEPLOY_FILE;
  const lane = process.env.LANE ?? "deploy";
  const { policyPath, policy } = await loadPolicy();

  const conn = await hre.network.connect();
  const { ethers } = conn;
  const provider = ethers.provider;
  const signers = await ethers.getSigners();
  const deployerSigner = signers[0] ?? null;
  const buyer = signers[1] ?? null;
  const allowWriteHandshake = process.env.ALLOW_WRITE_HANDSHAKE === "1";
  const configuredSigner = await resolveConfiguredSigner(conn.networkName);

  const networkInfo = await provider.getNetwork();
  let deployment = null;
  try {
    deployment = JSON.parse(await fs.readFile(deployFile, "utf8"));
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }

  const laneConfig = policy?.lanes?.[lane] ?? {};

  // Policy-required checks that do not depend on deployed contracts.
  const rpcAllowlist = Array.isArray(policy?.rpc_allowlist) ? policy.rpc_allowlist.map(normalizeUrl) : [];
  const rpcHostAllowlist = Array.isArray(policy?.rpc_host_allowlist) ? policy.rpc_host_allowlist.map(normalizeHost) : [];
  const defaultRpcFallback = conn.networkName === "localhost" ? "http://127.0.0.1:8545" : "";
  const networkRpcEnv = process.env[`${String(conn.networkName ?? "").toUpperCase()}_RPC_URL`] ?? "";
  const configuredRpc = normalizeUrl(
    pickUrl(conn.networkConfig)
      || pickUrl(hre.config?.networks?.[conn.networkName])
      || pickUrl(hre.config?.networks?.localhost)
      || pickUrl(networkRpcEnv)
      || process.env.RPC_URL
      || defaultRpcFallback
  );
  const configuredRpcHost = hostFromUrl(configuredRpc);
  const logQueryMaxBlockRange =
    configuredRpcHost.includes("alchemy.com") ? 10 : 0;
  const rpcAllowlistMatches =
    (configuredRpc !== "" && rpcAllowlist.includes(configuredRpc))
    || (configuredRpcHost !== "" && rpcHostAllowlist.includes(configuredRpcHost));
  const expectedChainId = deployment?.chainId ?? EXPECTED_CHAIN_IDS[conn.networkName] ?? null;
  const chainIdMatches = expectedChainId !== null && Number(networkInfo.chainId) === Number(expectedChainId);

  const allowedSignerAliases = Array.isArray(laneConfig.allowed_signers) ? laneConfig.allowed_signers : [];
  const signerAliasMap = policy?.signer_alias_map ?? {};
  const mappedSignerAddresses = allowedSignerAliases
    .map((alias) => signerAliasMap[alias])
    .filter((address) => typeof address === "string" && address.trim() !== "")
    .map(lower);
  const signerAddressForChecks = lower(configuredSigner.address ?? deployerSigner?.address ?? "");
  const signerAllowlistMatches = mappedSignerAddresses.length > 0
    ? signerAddressForChecks !== "" && mappedSignerAddresses.includes(signerAddressForChecks)
    : signerAddressForChecks !== "";
  const requiredChecks = {
    chain_id: chainIdMatches,
    rpc_allowlist: rpcAllowlistMatches,
    signer_allowlist: signerAllowlistMatches,
    bytecode_hash: false,
    proxy_implementation: false
  };

  if (!deployment) {
    const report = {
      generatedAt: new Date().toISOString(),
      network: conn.networkName,
      chainId: Number(networkInfo.chainId),
      deployFile,
      lane,
      phase: "predeploy",
      deploymentPresent: false,
      policyFile: policyPath,
      requiredChecks,
      pathInvariants: {
        adapter_wiring_frozen: false,
        sales_caller_frozen_to_adapter: false,
        epoch_token_coupling_holds: false,
        role_owner_hygiene_ok: false,
        auction_config_matches: false,
        sale_handshake_ok: false,
        movement_config_policy_ok: false
      },
      observations: {
        requiredChecks: {
          configuredRpc,
          configuredRpcHost,
          rpcAllowlist,
          rpcHostAllowlist,
          expectedChainId,
          allowedSignerAliases,
          signerAliasMap,
          mappedSignerAddresses,
          deployerSigner: deployerSigner?.address ?? null,
          configuredSigner
        },
        deploymentMissing: true
      }
    };

    console.log(JSON.stringify(report, null, 2));
    await conn.close();
    return;
  }

  const nft = await ethers.getContractAt("PathNFT", deployment.contracts.pathNft);
  const adapter = await ethers.getContractAt("PathMinterAdapter", deployment.contracts.pathMinterAdapter);
  const minter = await ethers.getContractAt("PathMinter", deployment.contracts.pathMinter);
  const auction = await ethers.getContractAt("PulseAuction", deployment.contracts.pulseAuction);

  const deployTxs = deployment.deployTxs ?? {};
  const nftDeployBlock = await resolveDeploymentBlock(provider, deployTxs.pathNft);
  const minterDeployBlock = await resolveDeploymentBlock(provider, deployTxs.pathMinter);

  const expectedCodeHashes = deployment.codeHashes ?? deployment.codehashes ?? {};
  const observedCodeHashes = {};
  const bytecodeChecks = {};
  let bytecodeHashesMatch = true;
  for (const [name, address] of Object.entries(deployment.contracts ?? {})) {
    const code = await provider.getCode(address);
    const codeHash = ethers.keccak256(code);
    const expectedHash = expectedCodeHashes[name] ?? null;
    const codePresent = code !== "0x";
    const hashMatches = expectedHash !== null && lower(codeHash) === lower(expectedHash);
    observedCodeHashes[name] = codeHash;
    bytecodeChecks[name] = {
      address,
      codePresent,
      observedHash: codeHash,
      expectedHash,
      hashMatches
    };
    if (!codePresent || !hashMatches) bytecodeHashesMatch = false;
  }

  const proxySlots = {};
  let proxyImplementationClean = true;
  for (const [name, address] of Object.entries(deployment.contracts ?? {})) {
    const value = await provider.getStorage(address, EIP1967_IMPLEMENTATION_SLOT);
    const isZero = toBigInt(value) === 0n;
    proxySlots[name] = { address, slotValue: value, isZero };
    if (!isZero) proxyImplementationClean = false;
  }

  const wiringFrozen = await adapter.wiringFrozen();
  const authorizedAuction = await adapter.getAuthorizedAuction();
  const minterTarget = await adapter.getMinterTarget();

  const salesCallerFrozen = await minter.salesCallerFrozen();
  const salesCaller = await minter.salesCaller();

  const epochBefore = toBigInt(await auction.getEpochIndex());
  const nextSaleEpochBefore = epochBefore + 1n;
  const nextIdBefore = toBigInt(await minter.nextId());

  const tokenBase = toBigInt(await adapter.tokenBase());
  const epochBase = toBigInt(await adapter.epochBase());
  const couplingDefined = nextSaleEpochBefore >= epochBase;
  const expectedNextId = couplingDefined ? tokenBase + (nextSaleEpochBefore - epochBase) : null;
  const couplingMatchesBeforeSale = couplingDefined && expectedNextId === nextIdBefore;

  // Role / owner hygiene.
  const nftRoleMembers = await collectRoleMembers(nft, nftDeployBlock ?? 0, logQueryMaxBlockRange);
  const minterRoleMembers = await collectRoleMembers(minter, minterDeployBlock ?? 0, logQueryMaxBlockRange);
  const adapterOwner = await adapter.owner();
  const nftDefaultAdminRole = await nft.DEFAULT_ADMIN_ROLE();
  const nftMinterRole = await nft.MINTER_ROLE();
  const minterDefaultAdminRole = await minter.DEFAULT_ADMIN_ROLE();
  const salesRole = await minter.SALES_ROLE();
  const reservedRole = await minter.RESERVED_ROLE();
  const frozenSalesAdminRole = await minter.FROZEN_SALES_ADMIN_ROLE();

  const roleExpectations = {
    nftDefaultAdmin: [deployment.deployer],
    nftMinterRole: [deployment.contracts.pathMinter],
    minterDefaultAdmin: [deployment.deployer],
    minterSalesRole: [deployment.contracts.pathMinterAdapter],
    minterReservedRole: [],
    minterFrozenSalesAdminRole: []
  };
  const roleObservations = {
    nftDefaultAdmin: roleMembers(nftRoleMembers, nftDefaultAdminRole),
    nftMinterRole: roleMembers(nftRoleMembers, nftMinterRole),
    minterDefaultAdmin: roleMembers(minterRoleMembers, minterDefaultAdminRole),
    minterSalesRole: roleMembers(minterRoleMembers, salesRole),
    minterReservedRole: roleMembers(minterRoleMembers, reservedRole),
    minterFrozenSalesAdminRole: roleMembers(minterRoleMembers, frozenSalesAdminRole)
  };
  const roleOwnerHygieneOk =
    lower(adapterOwner) === lower(deployment.deployer)
    && sameAddressSet(roleObservations.nftDefaultAdmin, roleExpectations.nftDefaultAdmin)
    && sameAddressSet(roleObservations.nftMinterRole, roleExpectations.nftMinterRole)
    && sameAddressSet(roleObservations.minterDefaultAdmin, roleExpectations.minterDefaultAdmin)
    && sameAddressSet(roleObservations.minterSalesRole, roleExpectations.minterSalesRole)
    && sameAddressSet(roleObservations.minterReservedRole, roleExpectations.minterReservedRole)
    && sameAddressSet(roleObservations.minterFrozenSalesAdminRole, roleExpectations.minterFrozenSalesAdminRole);

  // Auction config consistency.
  const auctionPaymentToken = await auction.paymentToken();
  const auctionTreasury = await auction.treasury();
  const auctionMintAdapter = await auction.mintAdapter();
  const [openTime, genesisPrice, genesisFloor, curveK, pts] = await auction.getConfig();
  const auctionConfigMatches =
    lower(auctionPaymentToken) === lower(deployment.paymentToken)
    && lower(auctionTreasury) === lower(deployment.treasury)
    && lower(auctionMintAdapter) === lower(deployment.contracts.pathMinterAdapter)
    && toBigInt(genesisPrice) === toBigInt(deployment.config.genesisPrice)
    && toBigInt(genesisFloor) === toBigInt(deployment.config.genesisFloor)
    && toBigInt(curveK) === toBigInt(deployment.config.k)
    && toBigInt(pts) === toBigInt(deployment.config.pts);

  // Movement configuration policy.
  const movementPolicy = policy?.path?.movement_config ?? null;
  const movementPolicyMode = typeof movementPolicy?.mode === "string" ? movementPolicy.mode : "unspecified";
  const expectedMovementPolicy = movementPolicy?.expected ?? {};
  const movementConstants = {
    THOUGHT: await nft.MOVEMENT_THOUGHT(),
    WILL: await nft.MOVEMENT_WILL(),
    AWA: await nft.MOVEMENT_AWA()
  };
  const movementObserved = {};
  let allMovementsUnset = true;
  for (const label of MOVEMENT_LABELS) {
    const movement = movementConstants[label];
    const minterAddress = await nft.getAuthorizedMinter(movement);
    const quota = await nft.getMovementQuota(movement);
    const unset = lower(minterAddress) === lower(ethers.ZeroAddress) && toBigInt(quota) === 0n;
    movementObserved[label] = {
      minter: minterAddress,
      quota: quota.toString(),
      unset
    };
    if (!unset) allMovementsUnset = false;
  }

  const expectedMovementForAll = MOVEMENT_LABELS.every((label) => {
    const item = expectedMovementPolicy?.[label];
    return item && item.minter !== undefined && item.quota !== undefined;
  });
  let expectedMovementMatches = expectedMovementForAll;
  for (const label of MOVEMENT_LABELS) {
    if (!expectedMovementForAll) break;
    const expected = expectedMovementPolicy[label];
    const expectedMinter = resolveExpectedMovementMinter(expected.minter, deployment, ethers);
    const expectedQuota = toBigInt(expected.quota);
    if (!expectedMinter) {
      expectedMovementMatches = false;
      break;
    }
    if (lower(expectedMinter) !== lower(movementObserved[label].minter)) {
      expectedMovementMatches = false;
      break;
    }
    if (expectedQuota !== toBigInt(movementObserved[label].quota)) {
      expectedMovementMatches = false;
      break;
    }
  }

  const movementConfigPolicyOk = movementPolicyMode === "require_expected"
    ? expectedMovementForAll && expectedMovementMatches
    : movementPolicyMode === "allow_unset"
      ? allMovementsUnset || (expectedMovementForAll && expectedMovementMatches)
      : false;

  // Live sale handshake.
  let saleHandshakeOk = false;
  let saleHandshakeObservation = {
    skipped: false
  };
  try {
    if (!allowWriteHandshake) {
      saleHandshakeOk = true;
      saleHandshakeObservation = {
        skipped: true,
        reason: "WRITE_HANDSHAKE_DISABLED"
      };
    } else if (lower(auctionPaymentToken) !== lower(ethers.ZeroAddress)) {
      saleHandshakeObservation = {
        skipped: true,
        reason: "PAYMENT_TOKEN_NOT_ETH"
      };
    } else {
      const maxBid = toBigInt(await auction.getCurrentPrice());
      const treasuryBefore = toBigInt(await provider.getBalance(deployment.treasury));
      const tx = await auction.connect(buyer).bid(maxBid, { value: maxBid });
      const receipt = await tx.wait();
      const saleLogs = await auction.queryFilter(
        auction.filters.Sale(),
        receipt.blockNumber,
        receipt.blockNumber
      );
      const settledLogs = await adapter.queryFilter(
        adapter.filters.EpochMinted(),
        receipt.blockNumber,
        receipt.blockNumber
      );
      const epochAfter = toBigInt(await auction.getEpochIndex());
      const nextIdAfter = toBigInt(await minter.nextId());
      const ownerAfter = await nft.ownerOf(nextIdBefore);
      const treasuryAfter = toBigInt(await provider.getBalance(deployment.treasury));
      const sale = saleLogs.length > 0 ? saleLogs[0].args : null;
      const settled = settledLogs.length > 0 ? settledLogs[0].args : null;

      const salePrice = sale ? toBigInt(sale.price) : 0n;
      const saleEpoch = sale ? toBigInt(sale.epochIndex) : 0n;
      const settledTokenId = settled ? toBigInt(settled.tokenId) : 0n;
      const settledEpoch = settled ? toBigInt(settled.epoch) : 0n;
      const settledTo = settled ? settled.to : ethers.ZeroAddress;

      saleHandshakeOk =
        saleLogs.length === 1
        && settledLogs.length === 1
        && salePrice <= maxBid
        && saleEpoch === epochBefore + 1n
        && settledEpoch === epochBefore + 1n
        && settledTokenId === nextIdBefore
        && lower(settledTo) === lower(buyer.address)
        && epochAfter === epochBefore + 1n
        && nextIdAfter === nextIdBefore + 1n
        && lower(ownerAfter) === lower(buyer.address)
        && treasuryAfter - treasuryBefore === salePrice;

      saleHandshakeObservation = {
        skipped: false,
        txHash: receipt.hash,
        buyer: buyer.address,
        maxBid: maxBid.toString(),
        saleLogs: saleLogs.length,
        settledLogs: settledLogs.length,
        salePrice: salePrice.toString(),
        saleEpoch: saleEpoch.toString(),
        settledEpoch: settledEpoch.toString(),
        settledTokenId: settledTokenId.toString(),
        expectedTokenId: nextIdBefore.toString(),
        ownerAfter,
        epochBefore: epochBefore.toString(),
        epochAfter: epochAfter.toString(),
        nextIdBefore: nextIdBefore.toString(),
        nextIdAfter: nextIdAfter.toString(),
        treasuryDelta: (treasuryAfter - treasuryBefore).toString()
      };
    }
  } catch (error) {
    saleHandshakeObservation = {
      skipped: false,
      error: error?.message ?? String(error)
    };
  }

  requiredChecks.bytecode_hash = bytecodeHashesMatch;
  requiredChecks.proxy_implementation = proxyImplementationClean;

  const pathInvariants = {
    adapter_wiring_frozen:
      wiringFrozen
      && lower(authorizedAuction) === lower(deployment.contracts.pulseAuction)
      && lower(minterTarget) === lower(deployment.contracts.pathMinter),
    sales_caller_frozen_to_adapter:
      salesCallerFrozen && lower(salesCaller) === lower(deployment.contracts.pathMinterAdapter),
    epoch_token_coupling_holds: couplingMatchesBeforeSale,
    role_owner_hygiene_ok: roleOwnerHygieneOk,
    auction_config_matches: auctionConfigMatches,
    sale_handshake_ok: saleHandshakeOk,
    movement_config_policy_ok: movementConfigPolicyOk
  };

  const report = {
    generatedAt: new Date().toISOString(),
    network: conn.networkName,
    chainId: Number(networkInfo.chainId),
    deployFile,
    lane,
    phase: "postdeploy",
    deploymentPresent: true,
    policyFile: policyPath,
    requiredChecks,
    pathInvariants,
    observations: {
      requiredChecks: {
        configuredRpc,
        configuredRpcHost,
        logQueryMaxBlockRange,
        rpcAllowlist,
        rpcHostAllowlist,
        allowedSignerAliases,
        signerAliasMap,
        deploymentDeployer: deployment.deployer,
        mappedSignerAddresses,
        signerAddressForChecks,
        configuredSigner,
        bytecodeChecks,
        proxySlots
      },
      adapter: {
        wiringFrozen,
        expectedAuction: deployment.contracts.pulseAuction,
        observedAuction: authorizedAuction,
        expectedMinter: deployment.contracts.pathMinter,
        observedMinter: minterTarget
      },
      salesCaller: {
        frozen: salesCallerFrozen,
        expected: deployment.contracts.pathMinterAdapter,
        observed: salesCaller
      },
      coupling: {
        tokenBase: tokenBase.toString(),
        epochBase: epochBase.toString(),
        observedEpochIndex: epochBefore.toString(),
        expectedNextSaleEpoch: nextSaleEpochBefore.toString(),
        expectedNextId: expectedNextId === null ? null : expectedNextId.toString(),
        observedNextId: nextIdBefore.toString()
      },
      roleOwnerHygiene: {
        adapterOwner,
        expectedAdapterOwner: deployment.deployer,
        expected: roleExpectations,
        observed: roleObservations
      },
      auctionConfig: {
        expected: {
          paymentToken: deployment.paymentToken,
          treasury: deployment.treasury,
          mintAdapter: deployment.contracts.pathMinterAdapter,
          k: String(deployment.config.k),
          genesisPrice: String(deployment.config.genesisPrice),
          genesisFloor: String(deployment.config.genesisFloor),
          pts: String(deployment.config.pts)
        },
        observed: {
          openTime: String(openTime),
          paymentToken: auctionPaymentToken,
          treasury: auctionTreasury,
          mintAdapter: auctionMintAdapter,
          k: String(curveK),
          genesisPrice: String(genesisPrice),
          genesisFloor: String(genesisFloor),
          pts: String(pts)
        }
      },
      saleHandshake: saleHandshakeObservation,
      movementPolicy: {
        mode: movementPolicyMode,
        expected: expectedMovementPolicy,
        observed: movementObserved,
        allMovementsUnset,
        expectedMovementForAll,
        expectedMovementMatches
      },
      observedCodeHashes
    }
  };

  console.log(JSON.stringify(report, null, 2));
  await conn.close();
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
