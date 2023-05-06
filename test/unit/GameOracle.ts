import { numToBytes32, stringToBytes, toBytes32String } from "@chainlink/test-helpers/dist/src/helpers"
import { assert, expect } from "chai"
import { BigNumber, ContractReceipt, ContractTransaction, Signer } from "ethers"
// import { network, deployments, ethers, run } from "hardhat"
import { network, ethers, run } from "hardhat"
// import { developmentChains } from "../../helper-hardhat-config"
import { ApiConsumer, ApiConsumerFactory, GameOracle, GameOracleFactory, LinkToken, LinkTokenFactory, MockGameOracle, MockGameOracleFactory, MockOracle, MockOracleFactory } from "../typechain"

describe("GameOracle Unit Tests", async function () {
      let apiConsumer: ApiConsumer
      let linkToken: LinkToken
      let mockGameOracle: MockGameOracle
      let gameOracle: GameOracle
      let deployer: Signer
      let deployerAddress: string

      const jobId = ethers.utils.toUtf8Bytes("29fa9aa13bf1468788b7cc4a500a45b8"); //test job id
      const fee = "100000000000000000" // fee = 0.1 linkToken
      const market = "resolve";
      const sprotId = "1";
      const gameId = 1;
      


      async function requestGameScore() {
        const transaction: ContractTransaction = await gameOracle.requestGameScore("");
        const transactionReceipt: ContractReceipt = await transaction.wait(1);
        if (!transactionReceipt.events) return
        const requestId: string = transactionReceipt.events[0].topics[1];
        return requestId;
      }

      async function requestGameStatus() {
        const date = new Date();
        const transaction: ContractTransaction = await gameOracle.requestGameStatus("");
        const transactionReceipt: ContractReceipt = await transaction.wait(1);
        if (!transactionReceipt.events) return
        const requestId: string = transactionReceipt.events[0].topics[1];
        return requestId;
      }


      async function changeOracleScoreData(homeScore:number, awayScore:number, requestId:string) {
        await mockGameOracle.fulfillOracleScoreRequest(requestId, numToBytes32(homeScore), numToBytes32(awayScore));
      }

      async function changeOracleStatusData(status:string, requestId:string) {
        const abiCoder = new ethers.utils.AbiCoder;
        await mockGameOracle.fulfillOracleStatusRequest(requestId, (status));
      }


      beforeEach(async () => {
        [deployer] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress();
        linkToken = await new LinkTokenFactory(deployer).deploy();
    
        mockGameOracle = await new MockGameOracleFactory(deployer).deploy(
            linkToken.address
        );
        
        gameOracle = await new GameOracleFactory(deployer).deploy(
            linkToken.address,
            mockGameOracle.address
        );

        apiConsumer = await new ApiConsumerFactory(deployer).deploy(
            mockGameOracle.address,
            jobId,
            fee,
            linkToken.address
        );
        
        // await run("fund-link", { contract: apiConsumer.address, linkaddress: linkToken.address })
        await linkToken.transfer( apiConsumer.address, fee);
        await linkToken.transfer( gameOracle.address, fee);
      })
      
    
      
      it("Should successfully make a request and get a result", async () => {
        const date = new Date();
        const transaction: ContractTransaction = await gameOracle.requestGameScore("");
        
        const transactionReceipt: ContractReceipt = await transaction.wait(1);
        if (!transactionReceipt.events) return
        const requestId: string = transactionReceipt.events[0].topics[1]
        // const abiCoder = new ethers.utils.AbiCoder;
        // let data = abiCoder.encode([ "bytes32", "uint8", "uint8", "uint8" ], [numToBytes32(gameId), "1", "2", "1"]);
        await mockGameOracle.fulfillOracleScoreRequest(requestId, numToBytes32(1), numToBytes32(2));
        // const volume = await gameOracle.getGamesResolved(requestId, 0)
        assert.equal(Number(await gameOracle.homeScore()), 1);
        assert.equal(Number(await gameOracle.awayScore()), 2);
        
      });

      
      it("request with functions", async () => {
        //request data
        const scoreRequestId:any = await requestGameScore();
        const statusRequestId:any = await requestGameStatus();
        //set oracle data
        await changeOracleScoreData(1, 2, scoreRequestId);
        await changeOracleStatusData("FT", statusRequestId);
        //get oracle data
        assert.equal(Number(await gameOracle.homeScore()), 1);
        assert.equal(Number(await gameOracle.awayScore()), 2);
        assert.equal(await gameOracle.gameStatus(), "FT");
      });
      
    })
