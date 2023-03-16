import { ethers } from "hardhat";
import { BigNumber, Contract, ContractReceipt, ContractTransaction, Signer } from "ethers";
import chai, { should, assert } from "chai";
import { solidity } from "ethereum-waffle";
import { getAddress } from "@ethersproject/address";
import { Bets } from "../typechain/Bets";
import { BetsFactory } from "../typechain/BetsFactory";
import { Token } from "../typechain/Token";
import { TokenFactory } from "../typechain/TokenFactory";
import { GameOracle, LinkToken, LinkTokenFactory, MockGameOracle, MockGameOracleFactory } from "../typechain";
import { numToBytes32 } from "@chainlink/test-helpers/dist/src/helpers";

chai.use(solidity);

const { expect } = chai;

const provider = ethers.provider;
const POINT_TWO_TOKENS = ethers.BigNumber.from("200000000000000000") as BigNumber;
const POINT_FOUR_TOKENS = ethers.BigNumber.from("400000000000000000") as BigNumber;
const POINT_SIX_TOKENS = ethers.BigNumber.from("600000000000000000") as BigNumber;
const POINT_EIGHT_TOKENS = ethers.BigNumber.from("800000000000000000") as BigNumber;
const ONE_TOKEN = ethers.BigNumber.from("1000000000000000000") as BigNumber;
const NINE_TOKENS = ethers.BigNumber.from("9000000000000000000") as BigNumber;
const TEN_TOKENS = ethers.BigNumber.from("10000000000000000000") as BigNumber;
const HUNDRED_TOKENS = ethers.BigNumber.from("100000000000000000000") as BigNumber;
const THOUSAND_TOKENS = ethers.BigNumber.from("1000000000000000000000") as BigNumber;
const TEN_THOUSAND_TOKENS = ethers.BigNumber.from("10000000000000000000000") as BigNumber;
const HUNDRED_THOUSAND_TOKENS = ethers.BigNumber.from("100000000000000000000000") as BigNumber;
const MILLION_TOKENS = ethers.BigNumber.from("100000000000000000000000") as BigNumber;


describe.only("Bets", () => {
  let bets: Bets
  let usdc: Token,
  deployer: Signer,
  admin1: Signer,
  admin2: Signer,
  vault: Signer,
  addresses: Signer[];

  let linkToken: LinkToken
  let mockGameOracle: MockGameOracle


  //oracle input data (they are fixed value for testing)
  const jobId = ethers.utils.toUtf8Bytes("29fa9aa13bf1468788b7cc4a500a45b8"); //test job id
  const fee = "100000000000000000" // fee = 0.1 linkToken
  const market = "resolve";
  const sprotId = "1";
  const gameId = 1;
  const statusId = "1";


  //request data from oracle
  async function requestGame() {
    //fund link befor request
    await linkToken.transfer( bets.address, fee);
  
    const date = new Date();
    //request for data
    const transaction: ContractTransaction = await bets.requestGames(
        jobId, //specId
        fee,   //payment
        market,//market
        sprotId,//sportId
        date.getTime(),//date
        {gasLimit:1000000}
    );
    const transactionReceipt: ContractReceipt = await transaction.wait(1);
    if (!transactionReceipt.events) return
    const requestId: string = transactionReceipt.events[0].topics[1];
    return requestId;
  }


  //change oracle data for testing
  async function changeOracleData(homeScore:number, awayScore:number, requestId:any) {
    const abiCoder = new ethers.utils.AbiCoder;
    let data = abiCoder.encode([ "bytes32", "uint8", "uint8", "uint8" ], [numToBytes32(gameId), homeScore.toString(), awayScore.toString(), statusId]);
    await mockGameOracle.fulfillOracleRequest(requestId, [data]);
  }

  const setupBets = async () => {
    [deployer, admin1, admin2, vault, ...addresses] = await ethers.getSigners();

    //deploy link
    linkToken = await new LinkTokenFactory(deployer).deploy();
    //deploy mockGameOracle to test oracle
    mockGameOracle = await new MockGameOracleFactory(deployer).deploy(
        linkToken.address
    );

    usdc = await new TokenFactory(deployer).deploy(
      MILLION_TOKENS
        );
    await usdc.deployed();

    bets = await new BetsFactory(deployer).deploy(
      await usdc.address,
      linkToken.address,
      mockGameOracle.address
      );
    await bets.deployed();

  };

  describe("Deployment", async () => {
    beforeEach(setupBets)

    it("should deploy", async () => {
      expect(bets).to.be.ok;
    });
  });

  describe("Create and get orders", async () => {
    beforeEach(async function instance() {
        setupBets
        await usdc.transfer(await addresses[0].getAddress(), THOUSAND_TOKENS);
        await usdc.connect(addresses[0]).approve(bets.address, HUNDRED_TOKENS);
    });

    it("test game oracle", async () => {
      //request data
      const requestId:any = await requestGame();
      //set oracle data
      await changeOracleData(1, 2, requestId);
      //get oracle data
      const volume = await bets.getGameResult(requestId, 0)
      assert.equal(Number(volume.gameId), gameId);
      assert.equal(Number(volume.homeScore), 1);
      assert.equal(Number(volume.awayScore), 2);
      assert.equal(Number(volume.statusId), Number(sprotId));
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


    it("gets an order", async () => {
        const user = await addresses[0].getAddress();
        const betIndex = 1;
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

  describe("cancels orders", async () => {
    beforeEach(async function instance() {
        setupBets
        await usdc.transfer(await addresses[0].getAddress(), THOUSAND_TOKENS);
        await usdc.connect(addresses[0]).approve(bets.address, HUNDRED_TOKENS);
        const betIndex = 3;
        const betPrice = TEN_TOKENS;
        const contractAmount = 10;
        const side = true;
        await bets.connect(addresses[0]).createOrder(betIndex, betPrice, contractAmount, side); 
    });

    it("cancels an order", async () => {
      const user = await addresses[0].getAddress();
      const betIndex = 3;
      await bets.connect(addresses[0]).cancelOrder(betIndex, 1);
      const orders = await bets.orders(user, betIndex, 1);
      expect(orders.account).to.equal("0x0000000000000000000000000000000000000000");
      expect(orders.betIndex).to.equal(0);
      expect(orders.betPrice).to.equal(0);
      expect(orders.contractAmount).to.equal(0);
      expect(orders.side).to.equal(false);
    });

    it("cancels an order and emits the OrderCanceled event", async () => {
      const user = await addresses[0].getAddress();
      const betIndex = 1;
      const betPrice = TEN_TOKENS;
      const contractAmount = 10;
      const side = true;
      const orderIndex = await bets.ordersIndex(user, betIndex);
      const cancelOrder = await bets.connect(addresses[0]).cancelOrder(betIndex, orderIndex);
      expect(cancelOrder
        ).to.emit(bets, "OrderCanceled").withArgs(
          user, betIndex, betPrice, contractAmount, side
      );
    });
  });

  describe("Executing orders", async () => {
    beforeEach(async function instance() {
      setupBets
      await usdc.transfer(await addresses[6].getAddress(), HUNDRED_TOKENS);
      await usdc.connect(addresses[6]).approve(bets.address, HUNDRED_TOKENS);
      await usdc.transfer(await addresses[7].getAddress(), HUNDRED_TOKENS);
      await usdc.connect(addresses[7]).approve(bets.address, HUNDRED_TOKENS);
    });

    it("Executes orders and emits the ExecutesOrder event", async () => {
      const winner = await addresses[6].getAddress();
      const loser = await addresses[7].getAddress();
      const betIndex = 3;
      const betPriceWinner = POINT_EIGHT_TOKENS;
      const betPriceLoser = POINT_TWO_TOKENS;
      const contractAmount = 10;
      const sideWinner = true;
      const sideLoser = false;
      await bets.connect(addresses[6]).createOrder(betIndex, betPriceWinner, contractAmount, sideWinner);
      await bets.connect(addresses[7]).createOrder(betIndex, betPriceLoser, contractAmount, sideLoser);
      const orderIndexWinner = await bets.ordersIndex(winner, betIndex);
      const orderIndexLoser = await bets.ordersIndex(loser, betIndex);
      const executeOrder = await bets.connect(deployer).executeOrder(winner, loser, betIndex, orderIndexWinner, orderIndexLoser);
      expect(executeOrder).to.emit(bets, "OrderExecuted"
      ).withArgs(
        winner, 
        loser, 
        betIndex, 
        betPriceWinner,
        betPriceLoser,
        contractAmount
        );
    });

    it("Reverts when bet prices do not match", async () => {
      const winner = await addresses[6].getAddress();
      const loser = await addresses[7].getAddress();
      const betIndex = 3;
      const betPriceWinner = POINT_EIGHT_TOKENS;
      const betPriceLoser1 = POINT_SIX_TOKENS;
      const contractAmount = 10;
      const sideWinner = true;
      const sideLoser = false;
      await bets.connect(addresses[6]).createOrder(betIndex, betPriceWinner, contractAmount, sideWinner);
      await bets.connect(addresses[7]).createOrder(betIndex, betPriceLoser1, contractAmount, sideLoser);
      const orderIndexWinner = await bets.ordersIndex(winner, betIndex);
      const orderIndexLoser = await bets.ordersIndex(loser, betIndex);
      await expect(bets.connect(deployer).executeOrder(winner, loser, betIndex, orderIndexWinner, orderIndexLoser)
      ).to.be.revertedWith("Bet prices do not match");
    });

    it("Reverts when execute order function is not called by the admin", async () => {
      const winner = await addresses[6].getAddress();
      const loser = await addresses[7].getAddress();
      const betIndex = 3;
      const betPriceWinner = POINT_EIGHT_TOKENS;
      const betPriceLoser1 = POINT_SIX_TOKENS;
      const contractAmount = 10;
      const sideWinner = true;
      const sideLoser = false;
      await bets.connect(addresses[6]).createOrder(betIndex, betPriceWinner, contractAmount, sideWinner);
      await bets.connect(addresses[7]).createOrder(betIndex, betPriceLoser1, contractAmount, sideLoser);
      const orderIndexWinner = await bets.ordersIndex(winner, betIndex);
      const orderIndexLoser = await bets.ordersIndex(loser, betIndex);
      await expect(bets.connect(addresses[0]).executeOrder(winner, loser, betIndex, orderIndexWinner, orderIndexLoser)
      ).to.be.revertedWith("Forbidden");
    })
  });
});
