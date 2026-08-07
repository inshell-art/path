import hardhatToolboxMochaEthers from "@nomicfoundation/hardhat-toolbox-mocha-ethers";

const localChainId = Number(process.env.PATH_LOCAL_CHAIN_ID ?? 31338);

const networks = {
  default: {
    type: "edr-simulated",
    chainId: localChainId,
    networkId: localChainId
  },
  localhost: {
    type: "http",
    url: process.env.PATH_LOCAL_RPC_URL ?? "http://127.0.0.1:8546",
    chainId: localChainId
  }
};

if (process.env.SEPOLIA_RPC_URL) {
  networks.sepolia = {
    type: "http",
    url: process.env.SEPOLIA_RPC_URL,
    accounts: process.env.SEPOLIA_PRIVATE_KEY ? [process.env.SEPOLIA_PRIVATE_KEY] : []
  };
}

if (process.env.MAINNET_RPC_URL) {
  networks.mainnet = {
    type: "http",
    url: process.env.MAINNET_RPC_URL,
    accounts: process.env.MAINNET_PRIVATE_KEY ? [process.env.MAINNET_PRIVATE_KEY] : []
  };
}

/** @type {import("hardhat/config").HardhatUserConfig} */
export default {
  plugins: [hardhatToolboxMochaEthers],
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1
      },
      viaIR: true
    }
  },
  paths: {
    sources: "./src",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  networks
};
