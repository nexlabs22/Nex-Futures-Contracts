// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2 <0.9.0;

import "forge-std/Test.sol";
import "../../contracts/Bets.sol";
import "../../contracts/GameOracle.sol";
import "../../contracts/Token.sol";
import "../../contracts/test/LinkToken.sol";
import "../../contracts/test/MockGameOracle.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";


contract BetsContract is Test {
    using Counters for Counters.Counter;

    Bets public bets;
    LinkToken public link;
    Token public usdc;
    MockGameOracle public mockOracle;
    GameOracle public gameOracle;

    Counters.Counter public gameCounter;
    //mapping(uint256 => Game) public games;

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

    struct Game {
        uint16 homeTeam;
        uint16 awayTeam;
        uint256 matchId;
        uint256 homeScore;
        uint256 awayScore;
        string status;
        bool isMatchStarted;
        bool isMatchFinished;
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
            mockOracle = new MockGameOracle(address(link));
            gameOracle = new GameOracle(address(link), address(mockOracle));
            bets = new Bets(
                "England",
                "Premier League",
                address(gameOracle),
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
    
    function updateOracle(string memory _gameId, string memory status, uint homeScore, uint awayScore) public {
        bytes32 scoreRequestId = gameOracle.requestGameScore(_gameId);
        bytes32 statusRequestId = gameOracle.requestGameStatus(_gameId);
        mockOracle.fulfillOracleScoreRequest(scoreRequestId, uintToBytes32(homeScore), uintToBytes32(awayScore));
        mockOracle.fulfillOracleStatusRequest(statusRequestId, status);
    }
    
    function test_UpdateGameStruct() public {
        vm.startPrank(owner);
            updateOracle("1", "FT", 1, 2);
            bets.setGame(34, 38);
            uint256 gameIndex = bets.gameCounter();
            (uint256 gameId, uint16 homeTeam, uint16 awayTeam, uint256 homeScore, uint256 awayScore, string memory status) = bets.games(gameIndex);
            assertEq(homeTeam, 34);
            assertEq(awayTeam, 38);
            assertEq(gameId, gameIndex);
            assertEq(homeScore, 1);
            assertEq(awayScore, 2);
            assertEq(status, "FT");
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

    function test_CreateBetATransfer() public {
        vm.startPrank(addr2);
        bets.createBetA(POINT_SIX, 100);
        assertEq(usdc.balanceOf(address(bets)), 60*10**18);
        vm.stopPrank();
    }

    function test_RevertCreateBetAandBIfGameStarted() public {
        vm.startPrank(owner);
            updateOracle("1", "HT", 0, 0);
            bets.setGame(34, 38);
        vm.stopPrank();
        vm.startPrank(addr2);
            bytes4 selector = bytes4(keccak256("GameStarted()"));
            vm.expectRevert(selector);
            bets.createBetA(POINT_EIGHT, 100);
            vm.expectRevert(selector);
            bets.createBetB(POINT_EIGHT, 100);
        vm.stopPrank();
    }

    function test_RevertTakeBetIfGameStarted() public {
        vm.startPrank(owner);
            updateOracle("1", "TBD", 0, 0);
            bets.setGame(34, 38);
        vm.stopPrank();
        vm.startPrank(addr3);
            bets.createBetB(POINT_EIGHT, 100);
        vm.stopPrank();
        uint256 betIndex = bets.betCounter();
        vm.startPrank(owner);
            updateOracle("1", "HT", 0, 0);
            bets.setGame(34, 38);
        vm.stopPrank();
        vm.startPrank(addr2);
            bytes4 selector = bytes4(keccak256("GameStarted()"));
            vm.expectRevert(selector);
            bets.takeBet(betIndex);
        vm.stopPrank();
    }

    function test_RevertTakeBetIfAlreadyFilled() public {
        vm.startPrank(owner);
            updateOracle("1", "TBD", 0, 0);
            bets.setGame(34, 38);
        vm.stopPrank();
        vm.startPrank(addr3);
            bets.createBetB(POINT_EIGHT, 100);
        vm.stopPrank();
        uint256 betIndex = bets.betCounter();
        vm.startPrank(addr3);
            bets.takeBet(betIndex);
        vm.stopPrank();
        vm.startPrank(addr5);
            bytes4 selector = bytes4(keccak256("BetAlreadyFilled()"));
            vm.expectRevert(selector);
            bets.takeBet(betIndex);
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

    function test_CreateBetBTransfer() public {
        vm.startPrank(addr2);
        bets.createBetB(POINT_FOUR, 100);
        assertEq(usdc.balanceOf(address(bets)), 40*10**18);
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

    function test_RevertCancelBetAandBIfGameStarted() public {
        vm.startPrank(addr2);
            bets.createBetA(POINT_SIX, 100);
        vm.stopPrank();

        uint256 betIndex = bets.betCounter();

        vm.startPrank(addr3);
            bets.createBetB(POINT_FOUR, 100);
        vm.stopPrank();

        uint256 betIndex2 = bets.betCounter();

        vm.startPrank(owner);
            updateOracle("1", "HT", 0, 0);
            bets.setGame(34, 38);
        vm.stopPrank();

        vm.startPrank(addr2);
            bytes4 selector = bytes4(keccak256("GameStarted()"));
            vm.expectRevert(selector);
            bets.cancelBetA(betIndex);
        vm.stopPrank();

        vm.startPrank(addr3);
            vm.expectRevert(selector);
            bets.cancelBetB(betIndex2);
        vm.stopPrank();
    }

    function test_RevertCancelBetAandBIfOrderDoesNotExist() public {
        vm.startPrank(addr2);
            bets.createBetA(POINT_SIX, 100);
        vm.stopPrank();

        uint256 betIndex = bets.betCounter();

        vm.startPrank(addr3);
            bets.createBetB(POINT_FOUR, 100);
        vm.stopPrank();

        uint256 betIndex2 = bets.betCounter();
        
        vm.startPrank(address(0));
            bytes4 selector = bytes4(keccak256("NonExistentOrder()"));
            vm.expectRevert(selector);
            bets.cancelBetA(betIndex);
        vm.stopPrank();

        vm.startPrank(address(0));
            vm.expectRevert(selector);
            bets.cancelBetB(betIndex2);
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

        vm.startPrank(owner);
            updateOracle("1", "FT", 1, 2);
            bets.setGame(34, 38);
        vm.stopPrank();
        
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

    function test_ExecuteBetTransfers() public {
        vm.startPrank(addr3);
            bets.createBetA(POINT_EIGHT, 100);
        vm.stopPrank();

        uint256 betIndex = bets.betCounter();

        uint256 balanceBeforeWin = usdc.balanceOf(addr2);
        vm.startPrank(addr2);
            bets.takeBet(betIndex);
        vm.stopPrank();

        vm.startPrank(owner);
            updateOracle("1", "FT", 1, 2);
            bets.setGame(34, 38);
        vm.stopPrank();
        
        vm.startPrank(addr2);
            bets.executeBet(betIndex);
            uint256 wonStake = 80 * 10**18;
            uint256 executionFee = 100 * 10**18 * 10/10000;
            assertEq(usdc.balanceOf(addr2), (balanceBeforeWin + wonStake - executionFee));
        vm.stopPrank();
    }

    function test_RevertExecuteBetIfOrderNotFilled() public {
        vm.startPrank(addr3);
            bets.createBetA(POINT_EIGHT, 100);
        vm.stopPrank();

        uint256 betIndex = bets.betCounter();

        vm.startPrank(owner);
            updateOracle("1", "FT", 1, 2);
            bets.setGame(34, 38);
        vm.stopPrank();
        
        vm.startPrank(addr2);
            bytes4 selector = bytes4(keccak256("UnfilledBet()"));
            vm.expectRevert(selector);
            bets.executeBet(betIndex);
        vm.stopPrank();
    }

    function test_RevertExecuteBetIfOrderDoesNotExist() public {
        vm.startPrank(addr3);
            bets.createBetA(POINT_EIGHT, 100);
        vm.stopPrank();

        uint256 betIndex = bets.betCounter();

        vm.startPrank(addr2);
            bets.takeBet(betIndex);
        vm.stopPrank();

        vm.startPrank(owner);
            updateOracle("1", "FT", 1, 2);
            bets.setGame(34, 38);
        vm.stopPrank();

        vm.startPrank(addr2);
            bytes4 selector = bytes4(keccak256("NonExistentOrder()"));
            vm.expectRevert(selector);
            bets.executeBet(0);
        vm.stopPrank();
    }

    function test_RevertExecuteBetIfYouLost() public {
        vm.startPrank(addr3);
            bets.createBetA(POINT_EIGHT, 100);
        vm.stopPrank();

        uint256 betIndex = bets.betCounter();

        vm.startPrank(addr2);
            bets.takeBet(betIndex);
        vm.stopPrank();

        vm.startPrank(owner);
            updateOracle("1", "FT", 1, 2);
            bets.setGame(34, 38);
        vm.stopPrank();

        vm.startPrank(addr3);
            bytes4 selector = bytes4(keccak256("NotWinner()"));
            vm.expectRevert(selector);
            bets.executeBet(betIndex);
        vm.stopPrank();
    }

    function test_RevertExecuteBetIfGameNotFinished() public {
        vm.startPrank(addr3);
            bets.createBetA(POINT_EIGHT, 100);
        vm.stopPrank();

        uint256 betIndex = bets.betCounter();

        vm.startPrank(addr2);
            bets.takeBet(betIndex);
        vm.stopPrank();

        vm.startPrank(owner);
            updateOracle("1", "HT", 1, 2);
            bets.setGame(34, 38);
        vm.stopPrank();

        vm.startPrank(addr2);
            bytes4 selector = bytes4(keccak256("GameNotFinished()"));
            vm.expectRevert(selector);
            bets.executeBet(betIndex);
        vm.stopPrank();
    }

    function test_SetExecutionFee() public {
        vm.startPrank(admin);
            bets.setExecutionFee(50);
            assertEq(bets.executionFee(), 50);
        vm.stopPrank();
    }

    function test_RevertSetExecutionFee() public {
        vm.startPrank(admin);
            bytes4 selector = bytes4(keccak256("FeeOutOfRange()"));
            vm.expectRevert(selector);
            bets.setExecutionFee(5000);
        vm.stopPrank();
    }
}