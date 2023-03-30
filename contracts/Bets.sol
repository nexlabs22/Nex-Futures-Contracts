//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {GameOracle} from "./GameOracle.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

contract Bets is ReentrancyGuard, GameOracle {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    address public usdc;
    address public owner;
    address public admin;
    uint16 public executionFee = 10; //=> 10/10000 = 0.1%
    Counters.Counter public betCounter;
    uint256 constant ONE_TOKEN = 10**18;

    mapping(uint256 => Bet) public bets;
    mapping(address => uint256) public betsIndex;

    struct Bet {
        address accountA; 
        address accountB; 
        uint256 betPrice;
        uint256 contractAmount;
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
        uint256 BetPriceLoser,
        uint256 contractAmount
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Forbidden, not owner");
        _;
    }
    
    modifier onlyAdmin() {
        require(msg.sender == admin, "Forbidden, not admin");
        _;
    }

    constructor(
        address _usdc,
        address _link,
        address _oracle,
        address _admin
    ) GameOracle(_link, _oracle) {
        usdc = _usdc;
        admin = _admin;
        owner = msg.sender;
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

        Bet memory bet = bets[_betIndex];

        if(bet.accountB == address(0)) {

            Bet memory filledBet = Bet(
                bet.accountA,
                msg.sender,
                bet.betPrice,
                bet.contractAmount
            );

            betsIndex[msg.sender] += 1;

            bets[_betIndex] = filledBet;

            uint256 betPriceB = ONE_TOKEN.sub(bet.betPrice);
            uint256 complimentaryStake = betPriceB.mul(bet.contractAmount);
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

            betsIndex[msg.sender] += 1;

            bets[_betIndex] = filledBet;

            uint256 betPriceB = ONE_TOKEN.sub(bet.betPrice);
            uint256 complimentaryStake = betPriceB.mul(bet.contractAmount);

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
            revert("Bet has already been filled");
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
        uint256 _betPrice, 
        uint256 _contractAmount
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

        uint256 _stakedAmount = bet.betPrice * bet.contractAmount;

        depositStake(_stakedAmount);

        uint256 _betPriceB = ONE_TOKEN.sub(bet.betPrice);

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
        uint256 _betPrice, 
        uint256 _contractAmount
        ) internal {

        Bet memory bet = Bet(
            address(0),
            msg.sender,
            ONE_TOKEN.sub(_betPrice),
            _contractAmount
        );

        betCounter.increment();
        uint256 _betIndex = betCounter.current();

        bets[_betIndex] = bet;

        uint256 _stakedAmount = bet.betPrice * bet.contractAmount;

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
        require(_newFee <= 100 && _newFee >= 1, "New fee out of range");
        executionFee = _newFee;
    }

    /**
     * @notice Allows users to cancel side A orders
     * @param _requestId the requestId returned by requestGame function
     * @param _idx match Id returned by requestGame function 
     * @param _betIndex the index of the order for the _betIndex chosen by the user.
     */
    function cancelBetA(
        bytes32 _requestId,
        uint256 _idx,
        uint256 _betIndex
    ) external nonReentrant {
        require(
            msg.sender != address(0)
            || _betIndex != 0, 
            "Order does not exist");

        GameResolve memory game = getGameResult(_requestId, _idx);
        uint256 _statusId = game.statusId;

        Bet memory bet = bets[_betIndex];

        require(msg.sender == bet.accountA, "Not your order");

        uint256 _stakedAmount = bet.betPrice * bet.contractAmount;

        bool beforeGame = _statusId == 10 || _statusId == 13;
        bool betMatch = bet.accountA != address(0) && bet.accountB != address(0);
        bool noMatch = bet.accountB == address(0);

        if (beforeGame) {
            if (betMatch) {
                delete bets[_betIndex];
                _createBetB(ONE_TOKEN.sub(bet.betPrice), bet.contractAmount);
                transferStake(msg.sender, _stakedAmount);

            } else if (noMatch) {
                delete bets[_betIndex];
                transferStake(msg.sender, _stakedAmount);
            }
        } else {
            revert("Game started, cannot cancel order");
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
     * @param _requestId the requestId returned by requestGame function
     * @param _idx match Id returned by requestGame function 
     * @param _betIndex the index of the order for the _betIndex chosen by the user.
     */
    function cancelBetB(
        bytes32 _requestId,
        uint256 _idx,
        uint256 _betIndex
    ) external nonReentrant {
        require(
            msg.sender != address(0)
            || _betIndex != 0, 
            "Order does not exist");

        GameResolve memory game = getGameResult(_requestId, _idx);
        uint256 _statusId = game.statusId;

        Bet memory bet = bets[_betIndex];

        require(msg.sender == bet.accountB, "Not your order");

        uint256 _stakedAmount = bet.betPrice * bet.contractAmount;

        bool beforeGame = _statusId == 10 || _statusId == 13;
        bool betMatch = bet.accountA != address(0) && bet.accountB != address(0);
        bool noMatch = bet.accountA == address(0);

        if (beforeGame) {
            if (betMatch) {
                delete bets[_betIndex];
                _createBetA((ONE_TOKEN.sub(bet.betPrice)), bet.contractAmount);
                transferStake(msg.sender, _stakedAmount);
            } else if (noMatch) {
                delete bets[_betIndex];
                transferStake(msg.sender, _stakedAmount);
            }
        } else {
            revert("Game started, cannot cancel order");
        }

        emit BetCanceled(
            msg.sender,
            _betIndex,
            ONE_TOKEN.sub(bet.betPrice),
            bet.contractAmount
        );
    }


    /**
     * @notice Executes the winning order/bet
     * @param _requestId the requestId returned by requestGame function
     * @param _idx match Id returned by requestGame function 
     * @param _betIndex the index of the bet that will be executed
     */
    function executeBet(  
        bytes32 _requestId, 
        uint256 _idx,
        uint256 _betIndex
        ) external nonReentrant {

        require(_betIndex != 0, "Order does not exist");
        
        GameResolve memory game = getGameResult(_requestId, _idx);

        Bet memory bet = bets[_betIndex];

        require(bet.accountA != address(0) && bet.accountB != address(0), "Bet has not been filled");

        uint256 _totalStake = bet.contractAmount * ONE_TOKEN;

        if (game.homeScore > game.awayScore) {
            require(msg.sender == bet.accountA, "You are not the winner");
            uint256 _feeAdjustedStake = _totalStake - sendFeeToOwner(_totalStake);
            transferStake(bet.accountA, _feeAdjustedStake);

            emit BetExecuted(
                bet.accountA,
                bet.accountB,
                bet.betPrice,
                ONE_TOKEN.sub(bet.betPrice),
                bet.contractAmount
            );
        } else if (game.awayScore > game.homeScore) {
            require(msg.sender == bet.accountB, "You are not the winner");
            uint256 _feeAdjustedStake = _totalStake - sendFeeToOwner(_totalStake);
            transferStake(bet.accountB, _feeAdjustedStake);

            emit BetExecuted(
                bet.accountB,
                bet.accountA,
                ONE_TOKEN.sub(bet.betPrice),
                bet.betPrice,
                bet.contractAmount
            );

        } else {
            returnFunds(bet.accountA, bet.accountB, 
            (uint256(bet.betPrice).mul(bet.contractAmount)), 
            (uint256(ONE_TOKEN.sub(bet.betPrice)).mul(bet.contractAmount)));
        }

        delete bets[_betIndex];

    }
    
    /**
     * @notice creates a side A order
     * @param _betPrice the price of the bet determined by the user
     * @param _contractAmount the amount of bet contracts set by the user
     */
    function createBetA(        
        uint256 _betPrice, 
        uint256 _contractAmount
        ) external nonReentrant {
        _createBetA(_betPrice, _contractAmount);
    }

    /**
     * @notice creates a side B order
     * @param _betPrice the price of the bet determined by the user
     * @param _contractAmount the amount of bet contracts set by the user
     */
    function createBetB(        
        uint256 _betPrice, 
        uint256 _contractAmount
        ) external nonReentrant {
        _createBetB(_betPrice, _contractAmount);
    }

    /**
     * @notice retrieves the game result
     * @param _requestId the requestId returned by requestGame function
     * @param _idx match Id returned by requestGame function
     * return GameResolve struct
     *  struct GameResolve {
        bytes32 gameId;
        uint8 homeScore;
        uint8 awayScore;
        uint8 statusId;
        }
     */
    function getGameResult(bytes32 _requestId, uint256 _idx)  public view returns (GameResolve memory) {
        GameResolve memory game = abi.decode(requestIdGames[_requestId][_idx], (GameResolve));
        return game;
    }

}