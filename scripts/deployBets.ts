import { ethers } from "hardhat";

async function main() {

  // goerli game oracle address = 0x48a423ff0ACDE8f08eEa7E6bA6bcbc2ac58B905C
  // goerli bets = 0x680627bbF8853aEa8e605152959AB391ee783Aaa

  
  const [deployer] = await ethers.getSigners();
  const Bets = await ethers.getContractFactory("Bets");
  const bets = await Bets.deploy(
    "0x48a423ff0ACDE8f08eEa7E6bA6bcbc2ac58B905C", // game oracle address
    "0x636b346942ee09Ee6383C22290e89742b55797c5", // goerli usdc
    deployer.address // admin address
  );

  await bets.deployed();

  console.log(`Bets contract deployed to ${bets.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
