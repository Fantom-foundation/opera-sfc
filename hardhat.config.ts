import { HardhatUserConfig } from 'hardhat/config';
import * as dotenv from 'dotenv';
import '@nomicfoundation/hardhat-chai-matchers';
import '@nomicfoundation/hardhat-ethers';
import '@nomicfoundation/hardhat-ignition';
import '@openzeppelin/hardhat-upgrades';
import '@typechain/hardhat';
import 'hardhat-contract-sizer';
import 'hardhat-gas-reporter';
import 'solidity-coverage';

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.27',
    settings: {
      evmVersion: 'cancun',
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {},
    mainnet: {
      url: process.env.MAINNET_RPC_URL!,
      accounts: [process.env.MAINNET_PRIVATE_KEY_DEPLOY!],
    },
    testnet: {
      url: process.env.TESTNET_RPC_URL!,
      accounts: [process.env.TESTNET_PRIVATE_KEY_DEPLOY!],
    },
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.SONICSCAN_API_KEY!,
    },
    customChains: [
      {
        network: 'mainnet',
        chainId: 146,
        urls: {
          apiURL: 'https://api.sonicscan.org/api',
          browserURL: 'https://sonicscan.org',
        },
      },
    ],
  },
  gasReporter: {
    currency: 'USD',
    enabled: !!process.env.REPORT_GAS,
    gasPrice: 50,
  },
  contractSizer: {
    runOnCompile: true,
  },
};

export default config;
