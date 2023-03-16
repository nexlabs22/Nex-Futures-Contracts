import { numToBytes32 } from "@chainlink/test-helpers/dist/src/helpers"
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
      


      async function requestGame() {
        const date = new Date();
        const transaction: ContractTransaction = await gameOracle.requestGames(
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


      async function changeOracleData(homeScore:number, awayScore:number, requestId:string) {
        const abiCoder = new ethers.utils.AbiCoder;
        let data = abiCoder.encode([ "bytes32", "uint8", "uint8", "uint8" ], [numToBytes32(gameId), homeScore.toString(), awayScore.toString(), "1"]);
        await mockGameOracle.fulfillOracleRequest(requestId, [data]);
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
        const transaction: ContractTransaction = await gameOracle.requestGames(
            jobId, //specId
            fee,   //payment
            market,//market
            sprotId,//sportId
            date.getTime(),//date
            {gasLimit:1000000}
        );
        
        const transactionReceipt: ContractReceipt = await transaction.wait(1);
        if (!transactionReceipt.events) return
        const requestId: string = transactionReceipt.events[0].topics[1]
        const abiCoder = new ethers.utils.AbiCoder;
        let data = abiCoder.encode([ "bytes32", "uint8", "uint8", "uint8" ], [numToBytes32(gameId), "1", "2", "1"]);
        await mockGameOracle.fulfillOracleRequest(requestId, [data])
        const volume = await gameOracle.getGamesResolved(requestId, 0)
        assert.equal(Number(volume.gameId), gameId);
        assert.equal(Number(volume.homeScore), 1);
        assert.equal(Number(volume.awayScore), 2);
        assert.equal(Number(volume.statusId), Number(sprotId));
      });

      
      it("request with functions", async () => {
        //request data
        const requestId:any = await requestGame();
        //set oracle data
        await changeOracleData(1, 2, requestId);
        //get oracle data
        const volume = await gameOracle.getGamesResolved(requestId, 0)
        assert.equal(Number(volume.gameId), gameId);
        assert.equal(Number(volume.homeScore), 1);
        assert.equal(Number(volume.awayScore), 2);
        assert.equal(Number(volume.statusId), Number(sprotId));
      });
      
    })
