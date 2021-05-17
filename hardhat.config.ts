import { task } from "hardhat/config";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-ganache";

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (args, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: "ganache",
  networks: {
    ganache: {
      url: "http://127.0.0.1:8545",
      forking: {
        url: "https://eth-mainnet.alchemyapi.io/v2/hnIRjX9mL-joACOxqov1Tm2EyUZjCnI6"
      }
    }
  },
  solidity: {
    compilers: [
      {
        version: "0.6.12"
      },
      {
        version: "0.6.6"
      },
      {
        version: "0.5.16"
      }
    ]
  }
};

