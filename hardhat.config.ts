import { HardhatUserConfig } from "hardhat/config";
//import "@nomiclabs/hardhat-etherscan";
import "@nomicfoundation/hardhat-verify";
import "@nomicfoundation/hardhat-toolbox";
import "@typechain/hardhat";
import * as dotenv from "dotenv";
import path from "path";

// Imports values from the .env file
dotenv.config();

const RPC_URL = process.env.RPC_URL || "";
const PRIVATE_KEY = process.env.PRIVATE_KEY || "";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "";

const config: HardhatUserConfig = {
  gasReporter: {
    enabled: true,
  },
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      evmVersion: "shanghai",  // Specify the EVM version for Cancun
    },
  },
  // typechain: {
  //   outDir: "typechain", // Folder of type files to be created
  //   target: "ethers-v5", // Create types for Ethers.js
  // },
  defaultNetwork: "hardhat",
  networks: {
    // hardhat: {
    //   forking: {
    //     url: RPC_URL || "",        
    //     blockNumber: 21671501,// arb: 278070393 // sepolia: 7468704 // eth 21671501
    //   },
    //   accounts: {
    //     count: 32,
    //   },
    // },
    eth: {
      url: process.env.RPC_URL, // Your eth RPC URL
      accounts: [process.env.PRIVATE_KEY!], // Your wallet private key
    },
    // sepolia: {
    //   url: process.env.RPC_URL, // Your Sepolia RPC URL
    //   accounts: [process.env.PRIVATE_KEY!], // Your wallet private key
    // },

  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY, // Your Etherscan API Key
  },
  // sourcify: {
  //   // Disabled by default
  //   // Doesn't need an API key
  //   enabled: true
  // },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};

export default config;


