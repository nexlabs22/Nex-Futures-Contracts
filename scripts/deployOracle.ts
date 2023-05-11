import { ethers } from "hardhat";

/**
 verify command:
 npx hardhat verify --contract contracts/GameOracle.sol:GameOracle <deployedContractAddress> <arg1> <arg2...> --network goerli
 */

async function main() {
  // goerli game oracle address = 0x48a423ff0ACDE8f08eEa7E6bA6bcbc2ac58B905C
  // goerli bets = 0x680627bbF8853aEa8e605152959AB391ee783Aaa

  const GameOracle = await ethers.getContractFactory("GameOracle");
  const gameOracle = await GameOracle.deploy(
    "0x326C977E6efc84E512bB9C30f76E30c160eD06FB", //goerli link token address
    "0x6c2e87340Ef6F3b7e21B2304D6C057091814f25E" //goerli oracle address
  );

  await gameOracle.deployed();

  console.log(`GameOracle contract deployed to ${gameOracle.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
