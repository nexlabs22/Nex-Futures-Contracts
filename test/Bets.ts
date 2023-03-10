import { ethers } from "hardhat";
import { BigNumber, Contract, Signer } from "ethers";
import chai, { should } from "chai";
import { solidity } from "ethereum-waffle";
import { getAddress } from "@ethersproject/address";
import { Bets } from "../typechain/Bets";
import { BetsFactory } from "../typechain/BetsFactory";
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

describe.only("Bets", () => {
  let bets: Bets
  let usdc: Token,
  deployer: Signer,
  admin1: Signer,
  admin2: Signer,
  vault: Signer,
  addresses: Signer[];

  const setupBets = async () => {
    [deployer, admin1, admin2, vault, ...addresses] = await ethers.getSigners();
    usdc = await new TokenFactory(deployer).deploy(
      TEN_THOUSAND_TOKENS
        );
    await usdc.deployed();

    bets = await new BetsFactory(deployer).deploy(
      await usdc.address
      );
    await bets.deployed();
  };

  describe("Deployment", async () => {
    beforeEach(setupBets)

    it("should deploy", async () => {
      expect(bets).to.be.ok;
    });
  });

  describe("Initiate and retrieve orders", async () => {
    beforeEach(async function instance() {
        setupBets
        await usdc.transfer(await addresses[0].getAddress(), THOUSAND_TOKENS);
        await usdc.connect(addresses[0]).approve(bets.address, HUNDRED_TOKENS);
    });

    it("creates an order and emits the OrderCreated event", async () => {
        const user = await addresses[0].getAddress();
        const betIndex = 1;
        const betPrice = ONE_TOKEN;
        const contractAmount = 100;
        const side = true;
        const createOrder = await bets.connect(addresses[0]).createOrder(betIndex, betPrice, contractAmount, side);
        expect(createOrder
            ).to.emit(bets, "OrderCreated").withArgs(
            user, betIndex, betPrice, contractAmount, side);
    });

    it("creates an order", async () => {
        const user = await addresses[0].getAddress();
        const betIndex = 1;
        const betPrice = ONE_TOKEN;
        const contractAmount = 100;
        const side = true;
        await bets.connect(addresses[0]).createOrder(betIndex, betPrice, contractAmount, side);
        const orderIndex = await bets.ordersIndex(user, betIndex);
        const orders = await bets.orders(user, betIndex, orderIndex);
        expect(orders.account).to.equal(user);
        expect(orders.betIndex).to.equal(betIndex);
        expect(orders.betPrice).to.equal(betPrice);
        expect(orders.contractAmount).to.equal(contractAmount);
        expect(orders.side).to.equal(side);
    });

    it("gets an order", async () => {
        const user = await addresses[0].getAddress();
        const betIndex = 3;
        const betPrice = TEN_TOKENS;
        const contractAmount = 10;
        const side = true;
        await bets.connect(addresses[0]).createOrder(betIndex, betPrice, contractAmount, side);
        const orderIndex = await bets.ordersIndex(user, betIndex);
        const getOrder = await bets.connect(addresses[0]).getOrder(betIndex, orderIndex);
        expect(getOrder.account).to.equal(user);
        expect(getOrder.betIndex).to.equal(betIndex);
        expect(getOrder.betPrice).to.equal(betPrice);
        expect(getOrder.contractAmount).to.equal(contractAmount);
        expect(getOrder.side).to.equal(side);

    });
  });

});
