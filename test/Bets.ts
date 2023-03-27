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
  const statusIdV2 = "10";


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
    let data = abiCoder.encode([ "bytes32", "uint8", "uint8", "uint8" ], 
    [numToBytes32(gameId), homeScore.toString(), awayScore.toString(), statusId]);
    await mockGameOracle.fulfillOracleRequest(requestId, [data]);
  }

  async function changeOracleDataV2(homeScore:number, awayScore:number, requestId:any) {
    const abiCoder = new ethers.utils.AbiCoder;
    let data = abiCoder.encode([ "bytes32", "uint8", "uint8", "uint8" ], 
    [numToBytes32(gameId), homeScore.toString(), awayScore.toString(), statusIdV2]);
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

  describe("Create bets", async () => {
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

    it("creates a bet for side A and emits the event", async () => {
      const user = await addresses[0].getAddress();
      const betPriceA = POINT_EIGHT_TOKENS;
      const betPriceB = ONE_TOKEN.sub(betPriceA);
      const contractAmount = 100;
      const createBetA = await bets.connect(addresses[0]).createBetA(betPriceA, contractAmount);
      const betIndex = await bets.betCounter();
      expect(createBetA
        ).to.emit(bets, "BetACreated").withArgs(
        user, ZERO_ADDRESS, betIndex, betPriceA, betPriceB, contractAmount);
    });

    it("creates a bet for side B and emits the event", async () => {
      const user = await addresses[1].getAddress();
      const betPriceB = POINT_SIX_TOKENS;
      const betPriceA = ONE_TOKEN.sub(betPriceB);
      const contractAmount = 100;
      const createBetB = await bets.connect(addresses[1]).createBetB(betPriceB, contractAmount);
      const betIndex = await bets.betCounter();
      expect(createBetB
        ).to.emit(bets, "BetBCreated").withArgs(
        ZERO_ADDRESS, user, betIndex, betPriceA, betPriceB, contractAmount);
    });

    it("adds a bet to the mapping", async () => {
      const user = await addresses[1].getAddress();
      const betPriceB = POINT_SIX_TOKENS;
      const betPriceA = ONE_TOKEN.sub(betPriceB);
      const contractAmount = 100;
      await bets.connect(addresses[1]).createBetB(betPriceB, contractAmount);
      const betIndex = await bets.betCounter();
      const bet = await bets.bets(betIndex);
      const betPriceBUsingStruct = ONE_TOKEN.sub(bet.betPrice); 
      expect(bet.accountA).to.equal(ZERO_ADDRESS);
      expect(bet.accountB).to.equal(user);
      expect(bet.betPrice).to.equal(betPriceA);
      expect(betPriceBUsingStruct).to.equal(betPriceB);
      expect(bet.contractAmount).to.equal(contractAmount);
    });
  });

  describe("Cancel bets", async () => {
    beforeEach(async function instance() {
      setupBets
      await usdc.transfer(await addresses[0].getAddress(), THOUSAND_TOKENS);
      await usdc.connect(addresses[0]).approve(bets.address, HUNDRED_TOKENS);
      await usdc.transfer(await addresses[1].getAddress(), THOUSAND_TOKENS);
      await usdc.connect(addresses[1]).approve(bets.address, HUNDRED_TOKENS);
      const requestId:any = await requestGame();
      await changeOracleData(1, 2, requestId);
    });

    it("cancels an A bet before the game if there is no bet match", async () => {
      const requestId:any = await requestGame();
      await changeOracleDataV2(1, 2, requestId);
      const betPriceA = POINT_EIGHT_TOKENS;
      const contractAmount = 10;
      await bets.connect(addresses[1]).createBetA(betPriceA, contractAmount);
      const betIndex = await bets.betCounter();
      const bet = await bets.bets(betIndex);
      const cancelBet = await bets.connect(addresses[1]).cancelBetA(requestId, 0, betIndex);
      expect(cancelBet
        ).to.emit(bets, "BetCanceled").withArgs(
          bet.accountA, betIndex, bet.betPrice, contractAmount
      );
    });

    it("cancels a B bet before the game if there is no bet match", async () => {
      const requestId:any = await requestGame();
      await changeOracleDataV2(1, 2, requestId);
      const betPriceB = POINT_TWO_TOKENS;
      const contractAmount = 10;
      await bets.connect(addresses[1]).createBetB(betPriceB, contractAmount);
      const betIndex = await bets.betCounter();
      const bet = await bets.bets(betIndex);
      const cancelBet = await bets.connect(addresses[1]).cancelBetB(requestId, 0, betIndex);
      const betPriceBUsingStruct = ONE_TOKEN.sub(bet.betPrice);
      expect(cancelBet
        ).to.emit(bets, "BetCanceled").withArgs(
          bet.accountB, betIndex, betPriceBUsingStruct, contractAmount
      );
    });

    it("cancels an A bet before the game and if there is a bet match", async () => {
      const requestId:any = await requestGame();
      await changeOracleDataV2(1, 2, requestId);
      const betPriceA = POINT_EIGHT_TOKENS;
      const contractAmount = 10;
      await bets.connect(addresses[0]).createBetA(betPriceA, contractAmount);
      const betIndex = await bets.betCounter();
      await bets.connect(addresses[1]).takeBet(betIndex);
      const bet = await bets.bets(betIndex);
      const cancelBetA = await bets.connect(addresses[0]).cancelBetA(requestId, 0, betIndex);
      expect(cancelBetA
        ).to.emit(bets, "BetCanceled").withArgs(
          bet.accountA, betIndex, bet.betPrice, bet.contractAmount
      );
      const betIndexV2 = await bets.betCounter();
      const betV2 = await bets.bets(betIndexV2);
      expect(cancelBetA
        ).to.emit(bets, "BetBCreated").withArgs(
          ZERO_ADDRESS, betV2.accountB, betIndexV2, betV2.betPrice, ONE_TOKEN.sub(bet.betPrice), betV2.contractAmount
      );
    });

    it("cancels a B bet before the game and if there is a bet match", async () => {
      const requestId:any = await requestGame();
      await changeOracleDataV2(1, 2, requestId);
      const betPriceB = POINT_TWO_TOKENS;
      const contractAmount = 10;
      await bets.connect(addresses[1]).createBetB(betPriceB, contractAmount);
      const betIndex = await bets.betCounter();
      await bets.connect(addresses[0]).takeBet(betIndex);
      const bet = await bets.bets(betIndex);
      const cancelBetB = await bets.connect(addresses[1]).cancelBetB(requestId, 0, betIndex);
      expect(cancelBetB
        ).to.emit(bets, "BetCanceled").withArgs(
          bet.accountB, betIndex, ONE_TOKEN.sub(bet.betPrice), bet.contractAmount
      );
      const betIndexV2 = await bets.betCounter();
      const betV2 = await bets.bets(betIndexV2);
      expect(cancelBetB
        ).to.emit(bets, "BetACreated").withArgs(
          betV2.accountA, ZERO_ADDRESS, betIndexV2, betV2.betPrice, ONE_TOKEN.sub(betV2.betPrice), betV2.contractAmount
      );
    });

    it("reverts an A bet after the match started", async () => {
      const requestId:any = await requestGame();
      await changeOracleData(1, 2, requestId);
      const betPriceA = POINT_EIGHT_TOKENS;
      const contractAmount = 10;
      await bets.connect(addresses[0]).createBetA(betPriceA, contractAmount);
      const betIndex = await bets.betCounter();
      await expect(bets.connect(addresses[0]).cancelBetA(requestId, 0, betIndex)
      ).to.be.revertedWith('Game started, cannot cancel order');
    });
  });

  describe("Taking bets", async () => {
    beforeEach(async function instance() {
      setupBets
      await usdc.transfer(await addresses[4].getAddress(), HUNDRED_TOKENS);
      await usdc.connect(addresses[4]).approve(bets.address, HUNDRED_TOKENS);
      await usdc.transfer(await addresses[5].getAddress(), HUNDRED_TOKENS);
      await usdc.connect(addresses[5]).approve(bets.address, HUNDRED_TOKENS);
    });

    it("takes an existing bet", async () => {
      const betPriceA = POINT_EIGHT_TOKENS;
      const contractAmount = 10;
      const sideB = await addresses[5].getAddress();
      await bets.connect(addresses[4]).createBetA(betPriceA, contractAmount);
      const betsIndex = await bets.betCounter();
      const bet = await bets.bets(betsIndex);
      const takeBet = await bets.connect(addresses[5]).takeBet(betsIndex);
      expect(takeBet).to.emit(bets, "BetTaken").withArgs(
        bet.accountA, sideB, betsIndex, bet.betPrice, ONE_TOKEN.sub(bet.betPrice), bet.contractAmount
      );
    });

    it("returns the fulfilled bet", async () => {
      const betPriceA = POINT_EIGHT_TOKENS;
      const betPriceB = ONE_TOKEN.sub(betPriceA);
      const contractAmount = 10;
      const sideA = await addresses[4].getAddress();
      const sideB = await addresses[5].getAddress();
      await bets.connect(addresses[4]).createBetA(betPriceA, contractAmount);
      const betsIndex = await bets.betCounter();
      await bets.connect(addresses[5]).takeBet(betsIndex);
      const bet = await bets.bets(betsIndex);
      const betPriceBUsingStruct = ONE_TOKEN.sub(bet.betPrice);
      expect(bet.accountA).to.equal(sideA);
      expect(bet.accountB).to.equal(sideB);
      expect(bet.betPrice).to.equal(betPriceA);
      expect(betPriceBUsingStruct).to.equal(betPriceB);
      expect(bet.contractAmount).to.equal(contractAmount);
    });
  });

  describe("Executing bets", async () => {
    beforeEach(async function instance() {
      setupBets
      await usdc.transfer(await addresses[6].getAddress(), HUNDRED_TOKENS);
      await usdc.connect(addresses[6]).approve(bets.address, HUNDRED_TOKENS);
      await usdc.transfer(await addresses[7].getAddress(), HUNDRED_TOKENS);
      await usdc.connect(addresses[7]).approve(bets.address, HUNDRED_TOKENS);
    });

    it("Executes bets when home wins and emits the ExecutesOrder event", async () => {
      const requestId:any = await requestGame();
      await changeOracleData(2, 1, requestId); //home wins
      const betPriceA = POINT_EIGHT_TOKENS;
      const betPriceB = POINT_TWO_TOKENS;
      const contractAmount = 10;
      await bets.connect(addresses[6]).createBetA(betPriceA, contractAmount);
      const betsIndex = await bets.betCounter();
      await bets.connect(addresses[7]).takeBet(betsIndex);
      const bet = await bets.bets(betsIndex);
      const totalAmountTransferred = betPriceA.mul(contractAmount).add(betPriceB.mul(contractAmount));
      const fee = await bets.executionFee();
      const feeAmount = totalAmountTransferred.mul(fee).div(10000);
      const feeAdjustedAmountTransferred = totalAmountTransferred.sub(feeAmount);
      const executeBets = await bets.connect(addresses[6]).executeBet(
        requestId, 
        0,
        betsIndex 
        );
      expect(executeBets).to.emit(bets, "FeeTransferred").withArgs(
        await deployer.getAddress(),
        feeAmount
      );  
      expect(executeBets).to.emit(bets, "StakeTransferred").withArgs(
        bets.address,
        bet.accountA,
        usdc.address,
        feeAdjustedAmountTransferred
      );  
      expect(executeBets).to.emit(bets, "BetExecuted"
      ).withArgs(
        bet.accountA, 
        bet.accountB,  
        betPriceA,
        betPriceB,
        contractAmount
      );
    });

    it("Executes bets when away wins and emits the ExecutesOrder event", async () => {
      const requestId:any = await requestGame();
      await changeOracleData(1, 2, requestId); //away wins
      const betPriceA = POINT_EIGHT_TOKENS;
      const betPriceB = POINT_TWO_TOKENS;
      const contractAmount = 10;
      await bets.connect(addresses[7]).createBetB(betPriceA, contractAmount);
      const betsIndex = await bets.betCounter();
      await bets.connect(addresses[6]).takeBet(betsIndex);
      const bet = await bets.bets(betsIndex);

      const totalAmountTransferred = betPriceA.mul(contractAmount).add(betPriceB.mul(contractAmount));
      const fee = await bets.executionFee();
      const feeAmount = totalAmountTransferred.mul(fee).div(10000);
      const feeAdjustedAmountTransferred = totalAmountTransferred.sub(feeAmount);

      const executeBets = await bets.connect(addresses[7]).executeBet(
        requestId, 
        0,  
        betsIndex);
      expect(executeBets).to.emit(bets, "FeeTransferred").withArgs(
        await deployer.getAddress(),
        feeAmount
      );  
      expect(executeBets).to.emit(bets, "StakeTransferred").withArgs(
        bets.address,
        bet.accountB,
        usdc.address,
        feeAdjustedAmountTransferred
      );  
      expect(executeBets).to.emit(bets, "BetExecuted"
      ).withArgs(
        bet.accountB, 
        bet.accountA,
        ONE_TOKEN.sub(bet.betPrice),  
        bet.betPrice,
        bet.contractAmount
      );
    });

    it("Reverts when the loser tries to execute the order", async () => {
      const requestId:any = await requestGame();
      await changeOracleData(2, 1, requestId);
      const betPriceA = POINT_EIGHT_TOKENS;
      const contractAmount = 10;
      await bets.connect(addresses[6]).createBetA(betPriceA, contractAmount);
      const betsIndex = await bets.betCounter();
      await bets.connect(addresses[7]).takeBet(betsIndex);
      await expect(bets.connect(addresses[7]).executeBet(
        requestId, 
        0,  
        betsIndex)
        ).to.be.revertedWith("You are not the winner");
    });

    it("Refunds stakes when the match results is a draw", async () => {
      const requestId:any = await requestGame();
      await changeOracleData(2, 2, requestId);
      const betPriceA = POINT_EIGHT_TOKENS;
      const betPriceB = POINT_TWO_TOKENS;
      const contractAmount = 10;
      await bets.connect(addresses[6]).createBetA(betPriceA, contractAmount);
      const betsIndex = await bets.betCounter();
      await bets.connect(addresses[7]).takeBet(betsIndex);
      const bet = await bets.bets(betsIndex);
      const totalAmountA = bet.betPrice.mul(bet.contractAmount);
      const betPriceBUsingStruct = ONE_TOKEN.sub(bet.betPrice);
      const totalAmountB = betPriceBUsingStruct.mul(bet.contractAmount);
      const executeWinner = await bets.connect(addresses[7]).executeBet(
        requestId, 
        0,
        betsIndex 
        );
      expect(executeWinner).to.emit(bets, "StakeReturned"
      ).withArgs(
        bets.address,
        bet.accountA, 
        bet.accountB,
        usdc.address,  
        totalAmountA,
        totalAmountB,
        );
    });
  });
});
