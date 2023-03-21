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
const POINT_SIX_TOKENS = ethers.BigNumber.from("600000000000000000") as BigNumber;
const POINT_EIGHT_TOKENS = ethers.BigNumber.from("800000000000000000") as BigNumber;
const ONE_TOKEN = ethers.BigNumber.from("1000000000000000000") as BigNumber;
const TEN_TOKENS = ethers.BigNumber.from("10000000000000000000") as BigNumber;
const HUNDRED_TOKENS = ethers.BigNumber.from("100000000000000000000") as BigNumber;
const THOUSAND_TOKENS = ethers.BigNumber.from("1000000000000000000000") as BigNumber;
const MILLION_TOKENS = ethers.BigNumber.from("100000000000000000000000") as BigNumber;
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"


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
    await linkToken.transfer(bets.address, fee);
  
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
      mockGameOracle.address,
      await admin1.getAddress()
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
      await usdc.transfer(await addresses[1].getAddress(), THOUSAND_TOKENS);
      await usdc.connect(addresses[1]).approve(bets.address, HUNDRED_TOKENS);
    });

    it("tests game oracle", async () => {
      //request data
      const requestId:any = await requestGame();
      //set oracle data
      await changeOracleData(1, 2, requestId);
      //get oracle data
      const volume = await bets.getGameResult(requestId, 0);
      assert.equal(Number(volume.gameId), gameId);
      assert.equal(Number(volume.homeScore), 1);
      assert.equal(Number(volume.awayScore), 2);
      assert.equal(Number(volume.statusId), Number(sprotId));
    });

    it("creates an order for side A and emits the event", async () => {
      const requestId:any = await requestGame();
      await changeOracleData(1, 2, requestId);
      const volume = await bets.getGameResult(requestId, 0);
      const gameId = volume.gameId;
      const user = await addresses[0].getAddress();
      const betPrice = ONE_TOKEN;
      const contractAmount = 100;
      const createOrderSideA = await bets.connect(addresses[0]).createOrderSideA(gameId, betPrice, contractAmount);
      const orderIndex = await bets.ordersIndex(user, gameId);
      expect(createOrderSideA
        ).to.emit(bets, "OrderCreatedSideA").withArgs(
        user, orderIndex, gameId, betPrice, contractAmount);
    });

    it("creates an order for side B and emits the event", async () => {
      const requestId:any = await requestGame();
      await changeOracleData(1, 2, requestId);
      const volume = await bets.getGameResult(requestId, 0);
      const gameId = volume.gameId;
      const user = await addresses[1].getAddress();
      const betPrice = ONE_TOKEN;
      const contractAmount = 100;
      const createOrderSideB = await bets.connect(addresses[1]).createOrderSideB(gameId, betPrice, contractAmount);
      const orderIndex = await bets.ordersIndex(user, gameId);
      expect(createOrderSideB
        ).to.emit(bets, "OrderCreatedSideB").withArgs(
        user, orderIndex, gameId, betPrice, contractAmount);
    });
  });

  describe("cancels orders", async () => {
    beforeEach(async function instance() {
      setupBets
      await usdc.transfer(await addresses[0].getAddress(), THOUSAND_TOKENS);
      await usdc.connect(addresses[0]).approve(bets.address, HUNDRED_TOKENS);
      const requestId:any = await requestGame();
      await changeOracleData(1, 2, requestId);
      const volume = await bets.getGameResult(requestId, 0);
      const gameId = volume.gameId;
      const betPrice = TEN_TOKENS;
      const contractAmount = 10;
      await bets.connect(addresses[0]).createOrderSideA(gameId, betPrice, contractAmount); 
    });

    it("cancels an order and emits the OrderCanceled event", async () => {
      const requestId:any = await requestGame();
      await changeOracleData(1, 2, requestId);
      const volume = await bets.getGameResult(requestId, 0);
      const gameId = volume.gameId;
      const user = await addresses[0].getAddress();
      const betPrice = TEN_TOKENS;
      const contractAmount = 10;
      const orderIndex = await bets.ordersIndex(user, gameId);
      const cancelOrder = await bets.connect(addresses[0]).cancelOrderSideA(gameId, orderIndex);
      expect(cancelOrder
        ).to.emit(bets, "OrderCanceled").withArgs(
          user, orderIndex, gameId, betPrice, contractAmount
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

    it("Executes orders when home wins and emits the ExecutesOrder event", async () => {
      const requestId:any = await requestGame();
      await changeOracleData(2, 1, requestId); //home wins
      const volume = await bets.getGameResult(requestId, 0);
      const gameId = volume.gameId;
      const sideA = await addresses[6].getAddress();
      const sideB = await addresses[7].getAddress();
      const betPriceSideA = POINT_EIGHT_TOKENS;
      const betPriceSideB = POINT_TWO_TOKENS;
      const contractAmount = 10;
      await bets.connect(addresses[6]).createOrderSideA(gameId, betPriceSideA, contractAmount);
      await bets.connect(addresses[7]).createOrderSideB(gameId, betPriceSideB, contractAmount);
      const orderIndexSideA = await bets.ordersIndex(sideA, gameId);
      const orderIndexSideB = await bets.ordersIndex(sideB, gameId);
      const totalAmountTransferred = betPriceSideA.mul(contractAmount).add(betPriceSideB.mul(contractAmount));
      const fee = await bets.executionFee();
      const feeAmount = totalAmountTransferred.mul(fee).div(10000);
      const feeAdjustedAmountTransferred = totalAmountTransferred.sub(feeAmount);
      const executeOrder = await bets.connect(addresses[6]).executeOrder(
        requestId, 
        0, 
        sideA, 
        sideB,  
        orderIndexSideA, 
        orderIndexSideB);
      expect(executeOrder).to.emit(bets, "FeeTransferred").withArgs(
        await deployer.getAddress(),
        feeAmount
      );
      expect(executeOrder).to.emit(bets, "StakeTransferred").withArgs(
        bets.address,
        sideA,
        usdc.address,
        feeAdjustedAmountTransferred
      );  
      expect(executeOrder).to.emit(bets, "OrderExecuted"
      ).withArgs(
        sideA, 
        sideB,
        gameId,  
        betPriceSideA,
        betPriceSideB,
        contractAmount
      );
    });

    it("Executes orders when away wins and emits the ExecutesOrder event", async () => {
      const requestId:any = await requestGame();
      await changeOracleData(1, 2, requestId); //away wins
      const volume = await bets.getGameResult(requestId, 0);
      const gameId = volume.gameId;
      const sideA = await addresses[6].getAddress();
      const sideB = await addresses[7].getAddress();
      const betPriceSideA = POINT_EIGHT_TOKENS;
      const betPriceSideB = POINT_TWO_TOKENS;
      const contractAmount = 10;
      await bets.connect(addresses[6]).createOrderSideA(gameId, betPriceSideA, contractAmount);
      await bets.connect(addresses[7]).createOrderSideB(gameId, betPriceSideB, contractAmount);
      const orderIndexAccount1 = await bets.ordersIndex(sideA, gameId);
      const orderIndexAccount2 = await bets.ordersIndex(sideB, gameId);
      const totalAmountTransferred = betPriceSideA.mul(contractAmount).add(betPriceSideB.mul(contractAmount));
      const fee = await bets.executionFee();
      const feeAmount = totalAmountTransferred.mul(fee).div(10000);
      const feeAdjustedAmountTransferred = totalAmountTransferred.sub(feeAmount);
      const executeOrder = await bets.connect(addresses[7]).executeOrder(
        requestId, 
        0, 
        sideA, 
        sideB,  
        orderIndexAccount1, 
        orderIndexAccount2);
      expect(executeOrder).to.emit(bets, "FeeTransferred").withArgs(
        await deployer.getAddress(),
        feeAmount
      );  
      expect(executeOrder).to.emit(bets, "StakeTransferred").withArgs(
        bets.address,
        sideB,
        usdc.address,
        feeAdjustedAmountTransferred
      );  
      expect(executeOrder).to.emit(bets, "OrderExecuted"
      ).withArgs(
        sideA, 
        sideB,
        gameId,  
        betPriceSideA,
        betPriceSideB,
        contractAmount
      );
    });

    it("Reverts when the loser tries to execute the order", async () => {
      const requestId:any = await requestGame();
      await changeOracleData(2, 1, requestId); //home wins --> side A wins
      const volume = await bets.getGameResult(requestId, 0);
      const gameId = volume.gameId;
      const sideA = await addresses[6].getAddress();
      const sideB = await addresses[7].getAddress();
      const betPriceSideA = POINT_EIGHT_TOKENS;
      const betPriceSideB = POINT_TWO_TOKENS;
      const contractAmount = 10;
      await bets.connect(addresses[6]).createOrderSideA(gameId, betPriceSideA, contractAmount);
      await bets.connect(addresses[7]).createOrderSideB(gameId, betPriceSideB, contractAmount);
      const orderIndexAccount1 = await bets.ordersIndex(sideA, gameId);
      const orderIndexAccount2 = await bets.ordersIndex(sideB, gameId);
      await expect(bets.connect(addresses[7]).executeOrder(
        requestId, 
        0, 
        sideA, 
        sideB,  
        orderIndexAccount1, 
        orderIndexAccount2)
        ).to.be.revertedWith("You are not the winner");
    });

    it("Refunds stakes when the match results is a draw", async () => {
      const requestId:any = await requestGame();
      await changeOracleData(2, 2, requestId);
      const volume = await bets.getGameResult(requestId, 0);
      const gameId = volume.gameId;
      const sideA = await addresses[6].getAddress();
      const sideB = await addresses[7].getAddress();
      const betPriceSideA = POINT_EIGHT_TOKENS;
      const betPriceSideB = POINT_TWO_TOKENS;
      const contractAmount = 10;
      await bets.connect(addresses[6]).createOrderSideA(gameId, betPriceSideA, contractAmount);
      await bets.connect(addresses[7]).createOrderSideB(gameId, betPriceSideB, contractAmount);
      const orderIndexAccount1 = await bets.ordersIndex(sideA, gameId);
      const orderIndexAccount2 = await bets.ordersIndex(sideB, gameId);
      const totalAmountSideA = betPriceSideA.mul(contractAmount);
      const totalAmountSideB = betPriceSideB.mul(contractAmount);
      const executeWinner = await bets.connect(addresses[7]).executeOrder(
        requestId, 
        0, 
        sideA, 
        sideB,  
        orderIndexAccount1, 
        orderIndexAccount2);
      expect(executeWinner).to.emit(bets, "StakeReturned"
      ).withArgs(
        bets.address,
        sideA, 
        sideB,
        usdc.address,  
        totalAmountSideA,
        totalAmountSideB,
        );
    });

    it("Reverts when bet prices do not match", async () => {
      const sideA = await addresses[6].getAddress();
      const sideB = await addresses[7].getAddress();
      const requestId:any = await requestGame();
      await changeOracleData(1, 2, requestId);
      const volume = await bets.getGameResult(requestId, 0);
      const gameId = volume.gameId;
      const betPriceSideA = POINT_EIGHT_TOKENS;
      const betPriceSideB = POINT_SIX_TOKENS;
      const contractAmount = 10;
      await bets.connect(addresses[6]).createOrderSideA(gameId, betPriceSideA, contractAmount);
      await bets.connect(addresses[7]).createOrderSideB(gameId, betPriceSideB, contractAmount);
      const orderIndexWinner = await bets.ordersIndex(sideA, gameId);
      const orderIndexLoser = await bets.ordersIndex(sideB, gameId);
      await expect(bets.connect(deployer).executeOrder(requestId, 0, sideA, sideB, orderIndexWinner, orderIndexLoser)
      ).to.be.revertedWith("Bet prices do not match");
    });
  });
});
