// SPDX-License-Identifier: MIT
// https://glink.solutions
// Discord=https://discord.gg/a69JjGd3y6

/**
 * THIS IS AN EXAMPLE CONTRACT WHICH USES HARDCODED VALUES FOR CLARITY.
 * THIS EXAMPLE USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

 // spolia link address = 0x779877A7B0D9E8603169DdbD7836e478b4624789
 // spolia oracle address = 0x6c2e87340Ef6F3b7e21B2304D6C057091814f25E


/**
SHORT	LONG	                                    TYPE	
TBD	  Time To Be Defined	                      Scheduled	
NS	  Not Started	                              Scheduled	
1H	  "First Half, Kick Off"	                  In Play	
HT	  Halftime	                                In Play	
2H	  "Second Half, 2nd Half Started"	          In Play	
ET	  Extra Time	                              In Play	
BT	  Break Time	                              In Play	
P	    Penalty In Progress	                      In Play	
SUSP	Match Suspended	                          In Play	
INT	  Match Interrupted	                        In Play	
FT	  Match Finished	                          Finished	
AET	  Match Finished After Extra Time	          Finished	
PEN	  Match Finished After Penalty	            Finished	
PST	  Match Postponed	                          Postponed	
CANC	Match Cancelled	                          Cancelled	
ABD	  Match Abandoned	                          Abandoned	
AWD	  Technical Loss	                          Not Played	
WO	  WalkOver	                                Not Played	
LIVE	In Progress	                              In Play	
*/


/**
 team ids
 [
    {teamName: "Manchester City", teamId: 50},
    {teamName: "Arsenal", teamId: 42},
    {teamName: "Newcastle United", teamId: 34},
    {teamName: "Manchester United", teamId: 33},
    {teamName: "Liverpool", teamId: 40},
    {teamName: "Tottenham", teamId: 47},
    {teamName: "Aston Villa", teamId: 66},
    {teamName: "Brighton", teamId: 51},
    {teamName: "Brentford", teamId: 55},
    {teamName: "Fulham", teamId: 36},
    {teamName: "Crystal Palace", teamId: 52},
    {teamName: "Chelsea", teamId: 49},
    {teamName: "Bournemouth", teamId: 35 },
    {teamName: "Wolves", teamId: 39},
    {teamName: "West Ham", teamId: 48},
    {teamName: "Leicester", teamId: 46},
    {teamName: "Leeds", teamId: 63},
    {teamName: "Nottingham Forest", teamId: 65},
    {teamName: "Everton", teamId: 45},
    {teamName: "Southampton", teamId: 41}
]
 */

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

contract GameOracle is ChainlinkClient, ConfirmedOwner {
  using Chainlink for Chainlink.Request;

  string public baseAPIUrl = "https://app.nexlabs.io/api/footballH2H";
  bytes32 private externalJobId;
  bytes32 private externalJobIdString;
  uint256 private oraclePayment;


  uint256 public homeScore;
  uint256 public awayScore;
  string public gameStatus;

  constructor(address _linkAddress, address _oracleAddress) ConfirmedOwner(msg.sender){
  setChainlinkToken(_linkAddress);
  setChainlinkOracle(_oracleAddress);
  externalJobId = "e35ba51d6ac14220b2e5554e5e1a97a5";
  externalJobIdString = "59b95d44dae442d69f48d09a0ddabf6e";
  oraclePayment = ((0 * LINK_DIVISIBILITY) / 10); // n * 10**18
  }

  function requestGameScore(string memory _gameId)
    public
    onlyOwner
    returns(bytes32)
  {
    Chainlink.Request memory req = buildChainlinkRequest(externalJobId, address(this), this.fulfillScores.selector);
    req.add("get", concatenation(baseAPIUrl, _gameId));
    req.add("path1", "response,0,goals,home");
    req.add("path2", "response,0,goals,away");
    req.addInt("times", 100);
    return sendChainlinkRequestTo(chainlinkOracleAddress(), req, oraclePayment);
  }

  event RequestFulfilledGameStatusScores(bytes32 indexed requestId, uint256 indexed Value1, uint256 indexed Value2);

  function fulfillScores(bytes32 requestId, uint256 _Value1, uint256 _Value2)
    public
    recordChainlinkFulfillment(requestId)
  {
    emit RequestFulfilledGameStatusScores(requestId, _Value1, _Value2);
    homeScore = _Value1;
    awayScore = _Value2;
  }


  function requestGameStatus(
    string memory _gameId
  )
    public
    returns(bytes32)
  {
    Chainlink.Request memory req = buildChainlinkRequest(externalJobIdString, address(this), this.fulfillGameStatus.selector);
    req.add("get", concatenation(baseAPIUrl, _gameId));
    req.add("path", "response,0,fixture,status,short");
    return sendChainlinkRequestTo(chainlinkOracleAddress(), req, oraclePayment);
  }

  event RequestFulfilledGameStatus(bytes32 indexed requestId, string stringVariable);

  function fulfillGameStatus(bytes32 requestId, string memory _stringVariable)
    public
    recordChainlinkFulfillment(requestId)
  {
    emit RequestFulfilledGameStatus(requestId, _stringVariable);
    gameStatus = _stringVariable;
  }

  function compare(string memory str2) public view returns (bool) {
        return keccak256(abi.encodePacked(gameStatus)) == keccak256(abi.encodePacked(str2));
    }
  
  function concatenation(string memory a, string memory b) public pure returns (string memory) {
        return string(bytes.concat(bytes(a), bytes(b)));
    }

}