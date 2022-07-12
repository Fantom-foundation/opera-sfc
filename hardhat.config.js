require('hardhat-contract-sizer');
require('dotenv').config();
require('@nomiclabs/hardhat-truffle5');
require('@nomiclabs/hardhat-waffle');
require('@openzeppelin/hardhat-upgrades');
require('@openzeppelin/test-helpers');
require('@nomiclabs/hardhat-ethers');
require('@nomiclabs/hardhat-web3');

const PRIVATE_KEY = process.env.PRIVATE_KEY;

module.exports = {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true
    },
    localhost: {
      url: 'http://127.0.0.1:8545'
    },
    mainnet: {
      url: 'https://rpcapi.fantom.network',
      chainId: 250
    },
    testnet: {
      url: 'https://rpc.testnet.fantom.network',
      chainId: 4002,
      accounts: [`0x${PRIVATE_KEY}`]
    }
  },
  mocha: {},
  abiExporter: {
    path: './build/contracts',
    clear: true,
    flat: true,
    spacing: 2
  },
  solidity: {
    version: '0.5.17',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  gasReporter: {
    currency: 'USD',
    enabled: false,
    gasPrice: 50
  }
};
