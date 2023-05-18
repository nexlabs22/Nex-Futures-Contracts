//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {GameOracle} from "./GameOracle.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

contract Bets is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    error BetAlreadyFilled();
    error FeeOutOfRange();
    error GameStarted();
    error GameNotFinished();
    error NotWinner();
    error NonExistentOrder();
    error NotYourOrder();
    error Unauthorized();
    error UnfilledBet();

    GameOracle public oracle;

    address public usdc;
    address public owner;
    address public admin;

    string public country;
    string public league;
    string public season;

    uint16 public constant ONE = 10;
    uint16 public executionFee = 10; //=> 10/10000 = 0.1%
    
    Counters.Counter public betCounter;
    Counters.Counter public gameCounter;
    uint256 constant ONE_TOKEN = 10**18;

    mapping(uint256 => Bet) public bets;
    mapping(uint256 => Game) public games;

    struct Bet {
        address accountA; 
        address accountB; 
        uint128 betPrice;
        uint128 contractAmount;
    }

    struct Game {
        uint256 gameId;
        uint16 homeTeam;
        uint16 awayTeam;
        uint256 homeScore;
        uint256 awayScore;
        string status;
    }

    event FeeTransferred(
        address to,
        uint256 amount
    );

    event StakeTransferred(
        address from,
        address to,
        address token,
        uint256 amount
    );

    event StakeReturned(
        address from,
        address to1,
        address to2,
        address token,
        uint256 amount1,
        uint256 amount2
    );

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

    event BetTaken(
        address indexed accountA,
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

    event BetExecuted(
        address indexed winner,
        address indexed loser,
        uint256 betPriceWinner,
        uint256 betPriceLoser,
        uint256 contractAmount
    );

    modifier onlyOwner() {
        if(msg.sender != owner) revert Unauthorized(); 
        _;
    }
    
    modifier onlyAdmin() {
        if(msg.sender != admin) revert Unauthorized();
        _;
    }

    constructor(
        string memory _country,
        string memory _league,
        address _gameOracleAddress,
        address _usdc,
        address _admin
    ) {
        oracle = GameOracle(_gameOracleAddress);
        usdc = _usdc;
        admin = _admin;
        owner = msg.sender;
        country = _country;
        league = _league;
    }

    /**
     * @notice retrieves and fulfills information about the game of interest
     * @param _gameId the Id of the game of interest
     */
    function updateOracle(string memory _gameId) public onlyOwner {
        bytes32 scoreRequestId = oracle.requestGameScore(_gameId);
        bytes32 statusRequestId = oracle.requestGameStatus(_gameId);
        oracle.fulfillScores(scoreRequestId, oracle.homeScore(), oracle.awayScore());
        oracle.fulfillGameStatus(statusRequestId, oracle.gameStatus());
    }

    /**
     * @notice sets the current game, can only be called by the owner
     * @param _homeTeam team currently playing home
     * @param _awayTeam team currently playing away
     */
    function setGame(uint16 _homeTeam, uint16 _awayTeam) public onlyOwner {

        gameCounter.increment();
        uint256 _gameIndex = gameCounter.current();

        Game memory game = Game(
            _gameIndex,
            _homeTeam,
            _awayTeam,
            oracle.homeScore(),
            oracle.awayScore(),
            oracle.gameStatus()
        );
        games[_gameIndex] = game;
    }

    /**
     * @notice updates the current season
     * @param _newSeason new season as a string
     */
    function updateSeason(string memory _newSeason) public onlyAdmin {
        season = _newSeason;
    }

    /**
     * @notice change game oracle address by admin.
     * @param _gameOracleAddress the new game oracle address.
     */
     function setGameOracle(address _gameOracleAddress) public onlyAdmin {
        oracle = GameOracle(_gameOracleAddress);
     }

    /**
     * @notice check that match is started or not
     */
     function isMatchStarted() public view returns(bool) {
        if(
            oracle.compare("TBD") ||  //Time To Be Defined
            oracle.compare("NS") ||   //Not Started	  
            oracle.compare("PST") ||  //Match Postponed
            oracle.compare("CANC") || //Match Cancelled	
            oracle.compare("ABD") ||  //Match Abandoned	
            oracle.compare("AWD") ||  //Technical Loss
            oracle.compare("WO") ||   //WalkOver
            oracle.compare("")        // no data
        ){
            return false;
        } else {
            return true;
        }
     }


    /**
    * @notice check that match is finished or not
    */
    function isMatchFinished() public view returns(bool) {
        if(
            oracle.compare("FT") ||  //Match Finished	
            oracle.compare("AET") ||   //Match Finished After Extra Time	  
            oracle.compare("PEN")  //Match Finished After Penalty
        ){
            return true;
        } else {
            return false;
        }
    }

    /**
     * @notice deposits the stake determined by the user.
     * @param _amount the amount of USDC that will be transferred.
     */
    function depositStake(
        uint256 _amount
    ) internal {

        IERC20(usdc).safeTransferFrom(msg.sender, address(this), _amount);

        emit StakeTransferred(msg.sender, address(this), usdc, _amount);
    }
    
    /**
     * @notice transfers the stake set by the user
     * @param _account the account that the funds will be transferred to.
     * @param _amount the amount of USDC that will be transferred.
     */
    function transferStake(
        address _account,
        uint256 _amount
    ) internal {

        IERC20(usdc).safeTransfer(_account, _amount);

        emit StakeTransferred(address(this), _account, usdc, _amount);
    }
    /**
     * @notice allows user to take an existing bet
     * @param _betIndex the index of the taken bet
     */
    function takeBet(uint256 _betIndex) external nonReentrant {
        if (isMatchStarted()) revert GameStarted();
        Bet memory bet = bets[_betIndex];

        if(bet.accountB == address(0)) {

            Bet memory filledBet = Bet(
                bet.accountA,
                msg.sender,
                bet.betPrice,
                bet.contractAmount
            );

            bets[_betIndex] = filledBet;

            uint256 betPriceB = ONE - bet.betPrice;
            uint256 complimentaryStake = betPriceB*bet.contractAmount*(10**17);
            depositStake(complimentaryStake);

            emit BetTaken(
                bet.accountA,
                msg.sender,
                _betIndex,
                bet.betPrice,
                betPriceB,
                bet.contractAmount
            );

        } else if(bet.accountA == address(0)) {
            Bet memory filledBet = Bet(
                msg.sender,
                bet.accountB,
                bet.betPrice,
                bet.contractAmount
            );

            bets[_betIndex] = filledBet;

            uint256 betPriceB = ONE - bet.betPrice;
            uint256 complimentaryStake = betPriceB*bet.contractAmount*(10**17);

            depositStake(complimentaryStake);

            emit BetTaken(
                msg.sender,
                bet.accountB,
                _betIndex,
                bet.betPrice,
                betPriceB,
                bet.contractAmount
            );
        } else {
            revert BetAlreadyFilled();
        }
    }

    /**
     * @notice returns the funds of both stakers
     * @param _account1 account address of staker 1
     * @param _account2 account address of staker 2
     * @param _amountAcc1 amount staked by account 1
     * @param _amountAcc2 amount staked by account 2
     */
    function returnFunds(
        address _account1,
        address _account2,
        uint256 _amountAcc1,
        uint256 _amountAcc2
    ) internal {

        IERC20(usdc).safeTransfer(_account1, _amountAcc1);
        IERC20(usdc).safeTransfer(_account2, _amountAcc2);

        emit StakeReturned(address(this), _account1, _account2, usdc, _amountAcc1, _amountAcc2);
    }

    /**
     * @notice sends execution order fee to owner
     * @param _usdcAmount the amount that is sent to the winner upon execution of the order
     */
    function sendFeeToOwner(uint256 _usdcAmount) internal returns(uint256) {
        uint256 fee = (_usdcAmount * executionFee) / 10000;
        IERC20(usdc).safeTransfer(owner, fee);
        emit FeeTransferred(owner,fee);
        return fee;
    }

    /**
     * @notice creates a side A order
     * @param _betPrice the price of the bet determined by the user
     * @param _contractAmount the amount of bet contracts set by the user
     */
    function _createBetA(
        uint128 _betPrice, 
        uint128 _contractAmount
        ) internal {

        Bet memory bet = Bet(
            msg.sender,
            address(0),
            _betPrice,
            _contractAmount
        );

        betCounter.increment();
        uint256 _betIndex = betCounter.current();
        
        bets[_betIndex] = bet;

        uint256 _stakedAmount = bet.betPrice * bet.contractAmount * 10**17;

        depositStake(_stakedAmount);

        uint256 _betPriceB = ONE - bet.betPrice;

        emit BetACreated(
            msg.sender,
            address(0),
            _betIndex,
            _betPrice,
            _betPriceB,
            bet.contractAmount
        );
    }

    /**
     * @notice creates a side B order
     * @param _contractAmount the amount of bet contracts set by the user.
     */
    function _createBetB(
        uint128 _betPrice, 
        uint128 _contractAmount
        ) internal {

        Bet memory bet = Bet(
            address(0),
            msg.sender,
            (ONE - _betPrice),
            _contractAmount
        );

        betCounter.increment();
        uint256 _betIndex = betCounter.current();

        bets[_betIndex] = bet;

        uint256 _stakedAmount = _betPrice * bet.contractAmount * 10**17;

        depositStake(_stakedAmount);

        emit BetBCreated(
            address(0),
            msg.sender,
            _betIndex,
            bet.betPrice,
            _betPrice,
            bet.contractAmount
        );
    }

    /**
     * @notice changes the admin address
     * @param newAdmin the address of the new admin
     */
    function setAdmin(address newAdmin) external onlyOwner {
        admin = newAdmin;
    }

    /**
     * @notice sets the fee paid by the winner on execution of the order
     * @param _newFee the new fee that needs to be paid per order execution
     */
    function setExecutionFee(uint16 _newFee) external onlyAdmin {
        if (_newFee > 100 || _newFee < 1) revert FeeOutOfRange();
        executionFee = _newFee;
    }

    /**
     * @notice Allows users to cancel side A orders
     * @param _betIndex the index of the order for the _betIndex chosen by the user.
     */
     
    function cancelBetA(
        uint256 _betIndex
    ) external nonReentrant {
        if (msg.sender == address(0) 
            || _betIndex == 0) revert NonExistentOrder();

        Bet memory bet = bets[_betIndex];

        if(msg.sender != bet.accountA) revert NotYourOrder(); 

        uint256 _stakedAmount = bet.betPrice * bet.contractAmount;

        bool beforeGame = !isMatchStarted();
        bool betMatch = bet.accountA != address(0) && bet.accountB != address(0);
        bool noMatch = bet.accountB == address(0);

        if (beforeGame) {
            if (betMatch) {
                delete bets[_betIndex];
                _createBetB((ONE - bet.betPrice), bet.contractAmount);
                transferStake(msg.sender, _stakedAmount);

            } else if (noMatch) {
                delete bets[_betIndex];
                transferStake(msg.sender, _stakedAmount);
            }
        } else {
            revert GameStarted();
        }

        emit BetCanceled(
            msg.sender,
            _betIndex,
            bet.betPrice,
            bet.contractAmount
        );
    }

    /**
     * @notice Allows users to cancel side B orders
     * @param _betIndex the index of the order for the _betIndex chosen by the user.
     */
    function cancelBetB(
        uint256 _betIndex
    ) external nonReentrant {
        if (msg.sender == address(0) 
            || _betIndex == 0) revert NonExistentOrder();

        Bet memory bet = bets[_betIndex];

        if(msg.sender != bet.accountB) revert NotYourOrder();

        uint256 _stakedAmount = bet.betPrice * bet.contractAmount;

        bool beforeGame = !isMatchStarted();
        bool betMatch = bet.accountA != address(0) && bet.accountB != address(0);
        bool noMatch = bet.accountA == address(0);

        if (beforeGame) {
            if (betMatch) {
                delete bets[_betIndex];
                _createBetA((ONE - bet.betPrice), bet.contractAmount);
                transferStake(msg.sender, _stakedAmount);
            } else if (noMatch) {
                delete bets[_betIndex];
                transferStake(msg.sender, _stakedAmount);
            }
        } else {
            revert GameStarted();
        }

        emit BetCanceled(
            msg.sender,
            _betIndex,
            (ONE - bet.betPrice),
            bet.contractAmount
        );
    }
    
    /**
     * @notice Executes the winning order/bet
     * @param _betIndex the index of the bet that will be executed
     */
    function executeBet(  
        uint256 _betIndex
        ) external nonReentrant {
        if (!isMatchFinished()) revert GameNotFinished();

        if (_betIndex == 0) revert NonExistentOrder();
        
        Game memory game = games[gameCounter.current()];
        uint256 homeScore = game.homeScore;
        uint256 awayScore = game.awayScore;

        Bet memory bet = bets[_betIndex];

        if(bet.accountA == address(0) || bet.accountB == address(0)) revert UnfilledBet();

        uint256 _totalStake = bet.contractAmount * ONE_TOKEN;

        if (homeScore > awayScore) {
            if(msg.sender != bet.accountA) revert NotWinner();
            uint256 _feeAdjustedStake = _totalStake - sendFeeToOwner(_totalStake);
            transferStake(bet.accountA, _feeAdjustedStake);

            emit BetExecuted(
                bet.accountA,
                bet.accountB,
                bet.betPrice,
                (ONE - bet.betPrice),
                bet.contractAmount
            );
        } else if (awayScore > homeScore) {
            if(msg.sender != bet.accountB) revert NotWinner();
            uint256 _feeAdjustedStake = _totalStake - sendFeeToOwner(_totalStake);
            transferStake(bet.accountB, _feeAdjustedStake);

            emit BetExecuted(
                bet.accountB,
                bet.accountA,
                (ONE - bet.betPrice),
                bet.betPrice,
                bet.contractAmount
            );

        } else {
            returnFunds(bet.accountA, bet.accountB, 
            (uint256(bet.betPrice)*(10**17)*(bet.contractAmount)), 
            (uint256(ONE_TOKEN-(uint256(bet.betPrice)*(10**17)))*(bet.contractAmount)));
        }
        delete bets[_betIndex];
    }
    
    /**
     * @notice creates a side A order
     * @param _betPrice the price of the bet determined by the user
     * @param _contractAmount the amount of bet contracts set by the user
     */
    function createBetA(        
        uint128 _betPrice, 
        uint128 _contractAmount
        ) external nonReentrant {
        if (isMatchStarted()) revert GameStarted();
        _createBetA(_betPrice, _contractAmount);
    }

    /**
     * @notice creates a side B order
     * @param _betPrice the price of the bet determined by the user
     * @param _contractAmount the amount of bet contracts set by the user
     */
    function createBetB(        
        uint128 _betPrice, 
        uint128 _contractAmount
        ) external nonReentrant {
        if (isMatchStarted()) revert GameStarted();
        _createBetB(_betPrice, _contractAmount);
    } 
}