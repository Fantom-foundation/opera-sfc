import { HardhatUserConfig } from 'hardhat/config';
import * as dotenv from 'dotenv';
import '@nomicfoundation/hardhat-chai-matchers';
import '@nomicfoundation/hardhat-ethers';
import 'hardhat-contract-sizer';
import 'hardhat-gas-reporter';
import 'solidity-coverage';
import "@typechain/hardhat";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.24',
    settings: {
      evmVersion: 'london',
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
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
