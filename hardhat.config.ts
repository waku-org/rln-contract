import * as dotenv from "dotenv";

import { HardhatUserConfig } from "hardhat/config";
import { NetworksUserConfig } from "hardhat/types";

import "@nomicfoundation/hardhat-foundry";
import "hardhat-deploy";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";
import "hardhat-gas-reporter";
import "solidity-docgen";

dotenv.config();
const { SEPOLIA_URL, PRIVATE_KEY, ETHERSCAN_API_KEY, RPC_PROVIDER } =
  process.env;

const getNetworkConfig = (): NetworksUserConfig | undefined => {
  if (SEPOLIA_URL && PRIVATE_KEY) {
    return {
      sepolia: {
        url: SEPOLIA_URL,
        accounts: [PRIVATE_KEY],
        forking: {
          url: SEPOLIA_URL,
        },
        verify: {
          etherscan: {
            apiKey: ETHERSCAN_API_KEY,
            apiUrl: "https://api-sepolia.etherscan.io",
          },
        },
      },
      localhost_integration: {
        url: "http://localhost:8545",
      },
    };
  } else if (RPC_PROVIDER) {
    return {
      localhost_integration: {
        url: RPC_PROVIDER,
      },
    };
  }
  return undefined;
};

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.15",
      },
      {
        version: "0.6.11",
      },
    ],
  },
  networks: getNetworkConfig(),
};

export default config;
