import hardhatToolboxMochaEthers from "@nomicfoundation/hardhat-toolbox-mocha-ethers";

/** @type {import("hardhat/config").HardhatUserConfig} */
export default {
  plugins: [hardhatToolboxMochaEthers],
  solidity: "0.8.24",
  paths: {
    sources: "./src",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  }
};
