// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2 <0.9.0;

import "forge-std/Test.sol";
import "../../contracts/Bets.sol";
import "../../contracts/GameOracle.sol";
import "../../contracts/Token.sol";
import "../../contracts/test/LinkToken.sol";
import "../../contracts/test/MockGameOracle.sol";


contract BetsContract is Test {

    
    LinkToken public link;
    MockGameOracle public oracle;
    GameOracle public game;

    function setUp() public {
        link = new LinkToken();
        oracle = new MockGameOracle(address(link));
        game = new GameOracle(address(link), address(oracle));
    }

    function testGameScoreAndStatus() public {
        // request data
        bytes32 scoreRequestId = game.requestGameScore("");
        bytes32 statusRequestId = game.requestGameStatus("");
        //set oracle data
        oracle.fulfillOracleScoreRequest(scoreRequestId, uintToBytes32(1), uintToBytes32(2));
        oracle.fulfillOracleStatusRequest(statusRequestId, "FT");
        // check oracle data
        assertEq(game.homeScore(), 1);
        assertEq(game.awayScore(), 2);
        assertEq(game.gameStatus(), "FT");
    }

    function uintToBytes32(uint myUint) public pure returns (bytes32 myBytes32) {
    myBytes32 = bytes32(myUint);
    }

}