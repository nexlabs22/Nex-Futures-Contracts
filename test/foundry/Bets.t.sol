// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2 <0.9.0;

import "forge-std/Test.sol";
import "../../contracts/Bets.sol";
import "../../contracts/GameOracle.sol";
import "../../contracts/Token.sol";
import "../../contracts/test/LinkToken.sol";
import "../../contracts/test/MockGameOracle.sol";


contract BetsContract is Test {

    Bets public bets;
    LinkToken public link;
    Token public usdc;
    MockGameOracle public oracle;
    GameOracle public game;

    address addr1 = vm.addr(1);
    address addr2 = vm.addr(2);
    address addr3 = vm.addr(3);
    address addr4 = vm.addr(4);
    address addr5 = vm.addr(5);
    address admin = vm.addr(6);
    address owner = vm.addr(7);

    uint128 constant POINT_EIGHT = 8;
    uint128 constant POINT_SIX = 6;
    uint128 constant POINT_FOUR = 4;
    uint128 constant POINT_TWO = 2;
    uint128 constant ONE = 10;

    struct Bet {
        address accountA; 
        address accountB; 
        uint128 betPrice;
        uint128 contractAmount;
    }

    event BetACreated(
        address indexed accountA,
        address accountB,
        uint256 indexed betIndex,
        uint256 betPriceA,
        uint256 betPriceB,
        uint256 contractAmount
    );

    event BetBCreated(
        address accountA,
        address indexed accountB,
        uint256 indexed betIndex,
        uint256 betPriceA,
        uint256 betPriceB,
        uint256 contractAmount
    );

    event BetCanceled(
        address indexed account,
        uint256 indexed betIndex,
        uint256 betPrice,
        uint256 contractAmount
    );

    event BetTaken(
        address indexed accountA,
        address indexed accountB,
        uint256 indexed betIndex,
        uint256 betPriceA,
        uint256 betPriceB,
        uint256 contractAmount
    );

    event BetExecuted(
        address indexed winner,
        address indexed loser,
        uint256 betPriceWinner,
        uint256 betPriceLoser,
        uint256 contractAmount
    );

    function setUp() public {

        usdc = new Token(10000000e18);
        usdc.transfer(addr1, 10000e18);
        usdc.transfer(addr2, 10000e18);
        usdc.transfer(addr3, 1000e18);
        usdc.transfer(addr4, 1000e18);
        usdc.transfer(addr5, 1000e18);
        usdc.transfer(admin, 1000e18);

        vm.startPrank(owner);
            link = new LinkToken();
            oracle = new MockGameOracle(address(link));
            game = new GameOracle(address(link), address(oracle));
            bets = new Bets(
                address(game),
                address(usdc),
                address(admin)
            );
        vm.stopPrank();

        vm.startPrank(addr1);
            usdc.approve(address(bets), 10000e18);
        vm.stopPrank();

        vm.startPrank(addr2);
            usdc.approve(address(bets), 10000e18);
        vm.stopPrank();

        vm.startPrank(addr3);
            usdc.approve(address(bets), 10000e18);
        vm.stopPrank();

        vm.startPrank(addr5);
            usdc.approve(address(bets), 10000e18);
        vm.stopPrank();
    }

    function uintToBytes32(uint myUint) public pure returns (bytes32) {
            return bytes32(myUint);
    }

    function setGameOracleStatuses(string memory matchStatus, uint8 homeScore, uint8 awayScore) public {
        vm.startPrank(owner);
            //request data
            bytes32 scoreRequestId = game.requestGameScore("");
            bytes32 statusRequestId = game.requestGameStatus("");
            //set oracle data
            oracle.fulfillOracleScoreRequest(scoreRequestId, uintToBytes32(homeScore), uintToBytes32(awayScore));
            oracle.fulfillOracleStatusRequest(statusRequestId, matchStatus);
        vm.stopPrank();
    }

    function test_BetCounter() public {
        vm.startPrank(addr1);
        uint256 betIndex_1 = bets.betCounter();
        assertEq(betIndex_1, 0);

        bets.createBetA(POINT_EIGHT, 100);

        uint256 betIndex_2 = bets.betCounter();
        assertEq(betIndex_2, 1);

        vm.stopPrank();
    }

    function test_CreateBetA() public {
        vm.startPrank(addr5);
        bets.createBetA(POINT_EIGHT, 100);
        uint256 betIndex = bets.betCounter();
        (address accountA, address accountB, uint128 betPrice, uint128 contractAmount) = bets.bets(betIndex);
        assertEq(accountA, addr5);
        assertEq(accountB, address(0));
        assertEq(betPrice, POINT_EIGHT);
        assertEq(contractAmount, 100);
        vm.stopPrank();
    }

    function test_CreateBetAEvent() public {
        vm.startPrank(addr1);
        vm.expectEmit(true, true, true, true);

        uint256 previousBetIndex_1 = bets.betCounter();
        uint256 currentBetIndex_1 = ++previousBetIndex_1;

        emit BetACreated(
            addr1,
            address(0),
            currentBetIndex_1,
            POINT_EIGHT,
            POINT_TWO,
            100
        );

        bets.createBetA(POINT_EIGHT, 100);
        vm.stopPrank();

        vm.startPrank(addr5);
        vm.expectEmit(true, true, true, true);

        uint256 previousBetIndex_2 = bets.betCounter();
        uint256 currentBetIndex_2 = ++previousBetIndex_2;

        emit BetACreated(
            addr5,
            address(0),
            currentBetIndex_2,
            POINT_TWO,
            POINT_EIGHT,
            100
        );

        bets.createBetA(POINT_TWO, 100);
        vm.stopPrank();

        vm.startPrank(addr2);
        vm.expectEmit(true, true, true, true);

        uint256 previousBetIndex_3 = bets.betCounter();
        uint256 currentBetIndex_3 = ++previousBetIndex_3;

        emit BetACreated(
            addr2,
            address(0),
            currentBetIndex_3,
            POINT_SIX,
            POINT_FOUR,
            100
        );

        bets.createBetA(POINT_SIX, 100);
        vm.stopPrank();
    }

    function test_CreateBetB() public {
        vm.startPrank(addr2);
        bets.createBetB(POINT_FOUR, 100);
        uint256 betIndex = bets.betCounter();
        (address accountA, address accountB, uint128 betPrice, uint128 contractAmount) = bets.bets(betIndex);
        assertEq(accountA, address(0));
        assertEq(accountB, addr2);
        assertEq(betPrice, (ONE - POINT_FOUR));
        assertEq(contractAmount, 100);
        vm.stopPrank();
    }

    function test_CreateBetBEvent() public {
        vm.startPrank(addr2);
        vm.expectEmit(true, true, true, true);

        uint256 previousBetIndex = bets.betCounter();
        uint256 currentBetIndex = ++previousBetIndex;

        emit BetBCreated(
            address(0),
            addr2,
            currentBetIndex,
            (ONE - POINT_FOUR),
            POINT_FOUR,
            100
        );

        bets.createBetB(POINT_FOUR, 100);
        vm.stopPrank();
    }

    function test_CancelBetAEvent() public {
        vm.startPrank(addr2);
        bets.createBetA(POINT_SIX, 100);
        vm.expectEmit(true, true, true, true);
        uint256 betIndex = bets.betCounter();

        emit BetCanceled(
            addr2,
            betIndex,
            POINT_SIX,
            100
        );

        bets.cancelBetA(betIndex);
        vm.stopPrank();
    }

    function test_CancelBetBEvent() public {
        vm.startPrank(addr2);
        bets.createBetB(POINT_FOUR, 100);
        vm.expectEmit(true, true, true, true);
        uint256 betIndex = bets.betCounter();

        emit BetCanceled(
            addr2,
            betIndex,
            POINT_FOUR,
            100
        );

        bets.cancelBetB(betIndex);
        vm.stopPrank();
    }

    function test_TakeBetA() public {
        vm.startPrank(addr2);
            bets.createBetB(POINT_FOUR, 100);
        vm.stopPrank();

        uint256 betIndex = bets.betCounter();

        vm.startPrank(addr3);
            vm.expectEmit(true, true, true, true);

            emit BetTaken(
                addr3,
                addr2,
                betIndex,
                POINT_SIX,
                POINT_FOUR,
                100
            );

            bets.takeBet(betIndex);
        vm.stopPrank();
    }

    function test_TakeBetB() public {
        vm.startPrank(addr3);
            bets.createBetA(POINT_EIGHT, 100);
        vm.stopPrank();

        uint256 betIndex = bets.betCounter();

        vm.startPrank(addr2);
            vm.expectEmit(true, true, true, true);

            emit BetTaken(
                addr3,
                addr2,
                betIndex,
                POINT_EIGHT,
                POINT_TWO,
                100
            );

            bets.takeBet(betIndex);
        vm.stopPrank();
    }

    function test_ExecuteBet() public {
        vm.startPrank(addr3);
            bets.createBetA(POINT_EIGHT, 100);
        vm.stopPrank();

        uint256 betIndex = bets.betCounter();

        vm.startPrank(addr2);
            bets.takeBet(betIndex);
        vm.stopPrank();

        setGameOracleStatuses("FT", 1, 2);
        
        vm.startPrank(addr2);

            vm.expectEmit(true, true, true, true);

            emit BetExecuted(
                addr2,
                addr3,
                POINT_TWO,
                POINT_EIGHT,
                100
            );

            bets.executeBet(betIndex);
        vm.stopPrank();

    }

}