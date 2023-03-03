import { ethers } from "hardhat";
import { BigNumber, Contract, Signer } from "ethers";
import chai, { should } from "chai";
import { solidity } from "ethereum-waffle";
import { getAddress } from "@ethersproject/address";
import { Collateral } from "../typechain/Collateral";
import { CollateralFactory } from "../typechain/CollateralFactory";
import { Token } from "../typechain/Token";
import { TokenFactory } from "../typechain/TokenFactory";

chai.use(solidity);

const { expect } = chai;

const provider = ethers.provider;
const ONE_TOKEN = ethers.BigNumber.from("1000000000000000000") as BigNumber;
const NINE_TOKENS = ethers.BigNumber.from("9000000000000000000") as BigNumber;
const TEN_TOKENS = ethers.BigNumber.from("10000000000000000000") as BigNumber;
const HUNDRED_TOKENS = ethers.BigNumber.from("100000000000000000000") as BigNumber;
const THOUSAND_TOKENS = ethers.BigNumber.from("1000000000000000000000") as BigNumber;
const TEN_THOUSAND_TOKENS = ethers.BigNumber.from("10000000000000000000000") as BigNumber;

describe("Collateral", () => {
  let col: Collateral
  let usdc: Token,
  deployer: Signer,
  admin1: Signer,
  admin2: Signer,
  vault: Signer,
  addresses: Signer[];

  const setupCollateral = async () => {
    [deployer, admin1, admin2, vault, ...addresses] = await ethers.getSigners();
    usdc = await new TokenFactory(deployer).deploy(
      TEN_THOUSAND_TOKENS
        );
    await usdc.deployed();

    col = await new CollateralFactory(deployer).deploy(
      await usdc.address
      );
    await col.deployed();
  };

  describe("Deployment", async () => {
    beforeEach(setupCollateral)

    it("should deploy", async () => {
      expect(col).to.be.ok;
    });
  });

  describe("Depositing and withdrawing collateral", async () => {
    beforeEach(async function instance() {
      setupCollateral
      await usdc.transfer(await addresses[0].getAddress(), THOUSAND_TOKENS);
      await usdc.connect(addresses[0]).approve(col.address, HUNDRED_TOKENS);
    })

    it("deposits collateral", async () => {
      await col.connect(addresses[0]).depositCollateral(TEN_TOKENS);
      const collateralBalance = await col.collateral(usdc.address, await addresses[0].getAddress());
      expect(collateralBalance).to.equal(TEN_TOKENS);
    });

    it("withdraws collateral", async () => {
      await col.connect(addresses[0]).withdrawCollateral(ONE_TOKEN);
      const collateralBalance = await col.collateral(usdc.address, await addresses[0].getAddress());
      expect(collateralBalance).to.equal(NINE_TOKENS);
    });    
    
    it("emits the Deposit event upon depositing collateral", async () => {
      const deposit = await col.connect(addresses[0]).depositCollateral(TEN_TOKENS);
      const collateralBalance = await col.collateral(usdc.address, await addresses[0].getAddress());
      expect(deposit).to.emit(col, "Deposit"
      ).withArgs(usdc.address, await addresses[0].getAddress(), TEN_TOKENS, collateralBalance);
    });

    it("emits the Withdraw event upon depositing collateral", async () => {
      const withdraw = await col.connect(addresses[0]).withdrawCollateral(ONE_TOKEN);
      const collateralBalance = await col.collateral(usdc.address, await addresses[0].getAddress());
      expect(withdraw).to.emit(col, "Withdraw"
      ).withArgs(usdc.address, await addresses[0].getAddress(), ONE_TOKEN, collateralBalance);
    });

  });

});