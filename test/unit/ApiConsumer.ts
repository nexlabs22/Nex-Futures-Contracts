import { numToBytes32 } from "@chainlink/test-helpers/dist/src/helpers"
import { assert, expect } from "chai"
import { BigNumber, ContractReceipt, ContractTransaction, Signer } from "ethers"
// import { network, deployments, ethers, run } from "hardhat"
import { network, ethers, run } from "hardhat"
// import { developmentChains } from "../../helper-hardhat-config"
import { ApiConsumer, ApiConsumerFactory, LinkToken, LinkTokenFactory, MockOracle, MockOracleFactory } from "../../typechain"

describe("APIConsumer Unit Tests", async function () {
      let apiConsumer: ApiConsumer
      let linkToken: LinkToken
      let mockOracle: MockOracle
      let deployer: Signer
      let deployerAddress: string
      const jobId = ethers.utils.toUtf8Bytes("29fa9aa13bf1468788b7cc4a500a45b8"); //test job id
      const fee = "100000000000000000" // fee = 0.1 linkToken

      beforeEach(async () => {
        [deployer] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress();
        linkToken = await new LinkTokenFactory(deployer).deploy();
    
        mockOracle = await new MockOracleFactory(deployer).deploy(
            linkToken.address
        );

        apiConsumer = await new ApiConsumerFactory(deployer).deploy(
            mockOracle.address,
            jobId,
            fee,
            linkToken.address
        );
        
        // await run("fund-link", { contract: apiConsumer.address, linkaddress: linkToken.address })
        await linkToken.transfer( apiConsumer.address, fee);
        
      })
      
      it(`Should successfully make an API request`, async () => {
        
        // await apiConsumer.requestVolumeData();
        await expect(apiConsumer.requestVolumeData()).to.emit(apiConsumer, "ChainlinkRequested")
      })
      
      it("Should successfully make an API request and get a result", async () => {
        const transaction: ContractTransaction = await apiConsumer.requestVolumeData()
        const transactionReceipt: ContractReceipt = await transaction.wait(1)
        if (!transactionReceipt.events) return
        const requestId: string = transactionReceipt.events[0].topics[1]
        const callbackValue: number = 777
        await mockOracle.fulfillOracleRequest(requestId, numToBytes32(callbackValue))
        const volume: BigNumber = await apiConsumer.volume()
        // console.log("VVVV", (volume).toNumber() )
        assert.equal(volume.toString(), callbackValue.toString())
      })

      it("Our event should successfully fire event on callback", async () => {
        const callbackValue: number = 777
        // we setup a promise so we can wait for our callback from the `once` function
        await new Promise(async (resolve, reject) => {
          // setup listener for our event
          apiConsumer.once("DataFullfilled", async () => {
            console.log("DataFullfilled event fired!")
            const volume: BigNumber = await apiConsumer.volume()
            // assert throws an error if it fails, so we need to wrap
            // it in a try/catch so that the promise returns event
            // if it fails.
            try {
              assert.equal(volume.toString(), callbackValue.toString())
              resolve(true)
            } catch (e) {
              reject(e)
            }
          })
          const transaction: ContractTransaction = await apiConsumer.requestVolumeData()
          const transactionReceipt: ContractReceipt = await transaction.wait(1)
          if (!transactionReceipt.events) return
          const requestId = transactionReceipt.events[0].topics[1]
          await mockOracle.fulfillOracleRequest(requestId, numToBytes32(callbackValue))
        })
      })
      
    })
