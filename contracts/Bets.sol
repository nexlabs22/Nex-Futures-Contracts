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
    uint256 public executionFee = 10; //=> 10/10000 = 0.1%
    Counters.Counter public betCounter;

    mapping(uint256 => Bet) public bets;
    mapping(address => mapping(uint256 => Bet)) public userBets;
    mapping(address => uint256) public betsIndex;

    struct Bet {
        address accountA; 
        address accountB; 
        uint256 betPriceA;
        uint256 betPriceB;
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
        uint256 winnerBetPrice,
        uint256 loserBetPrice,
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
                bet.betPriceA,
                bet.betPriceB,
                bet.contractAmount
            );

            betsIndex[msg.sender] += 1;
            userBets[msg.sender][_betIndex] = filledBet;

            bets[_betIndex] = filledBet;

            uint256 complimentaryStake = bet.betPriceB.mul(bet.contractAmount);
            depositStake(complimentaryStake);

            emit BetTaken(
                bet.accountA,
                msg.sender,
                _betIndex,
                bet.betPriceA,
                bet.betPriceB,
                bet.contractAmount
            );

        } else if(bet.accountA == address(0)) {
            Bet memory filledBet = Bet(
                msg.sender,
                bet.accountB,
                bet.betPriceA,
                bet.betPriceB,
                bet.contractAmount
            );

            betsIndex[msg.sender] += 1;
            uint256 _betIndexA = betsIndex[msg.sender];

            bets[_betIndexA] = filledBet;
            bets[_betIndex] = filledBet;

            uint256 complimentaryStake = bet.betPriceA.mul(bet.contractAmount);
            depositStake(complimentaryStake);

            emit BetTaken(
                msg.sender,
                bet.accountB,
                _betIndex,
                bet.betPriceA,
                bet.betPriceB,
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
     * @notice sets the fee paid by the winner on execution of the order
     * @param _newFee the new fee that needs to be paid per order execution
     */
    function setExecutionFee(uint256 _newFee) external onlyAdmin {
        require(_newFee <= 100 && _newFee >= 1, "New fee out of range");
        executionFee = _newFee;
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
     * @notice changes the admin address
     * @param newAdmin the address of the new admin
     */
    function setAdmin(address newAdmin) external onlyOwner {
        admin = newAdmin;
    }
    
    function createBetA(        
        uint256 _betPrice, 
        uint256 _contractAmount
        ) external nonReentrant {
        _createBetA(_betPrice, _contractAmount);
    }

    /**
     * @notice creates a side A order
     * @param _contractAmount the amount of bet contracts set by the user.
     */
    function _createBetA(
        uint256 _betPrice, 
        uint256 _contractAmount
        ) internal {

        Bet memory bet = Bet(
            msg.sender,
            address(0),
            _betPrice,
            (10**18 - _betPrice),
            _contractAmount
        );

        betsIndex[msg.sender] += 1;
        uint256 _userBetIndex = betsIndex[msg.sender];
        userBets[msg.sender][_userBetIndex] = bet; //this or use events index?

        betCounter.increment();
        uint256 _betIndex = betCounter.current();

        bets[_betIndex] = bet;

        uint256 _stakedAmount = bet.betPriceA * bet.contractAmount;

        depositStake(_stakedAmount);

        emit BetACreated(
            msg.sender,
            address(0),
            _betIndex,
            bet.betPriceA,
            bet.betPriceB,
            bet.contractAmount
        );
    }

    function createBetB(        
        uint256 _betPrice, 
        uint256 _contractAmount
        ) external nonReentrant {
        _createBetB(_betPrice, _contractAmount);
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
            (10**18 - _betPrice),
            _betPrice,
            _contractAmount
        );

        betsIndex[msg.sender] += 1;
        uint256 _userBetIndex = betsIndex[msg.sender];
        userBets[msg.sender][_userBetIndex] = bet; //this or use events index?

        betCounter.increment();
        uint256 _betIndex = betCounter.current();

        bets[_betIndex] = bet;

        uint256 _stakedAmount = bet.betPriceB * bet.contractAmount;

        depositStake(_stakedAmount);

        emit BetBCreated(
            address(0),
            msg.sender,
            _betIndex,
            bet.betPriceA,
            bet.betPriceB,
            bet.contractAmount
        );
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

        uint256 _stakedAmount = bet.betPriceA * bet.contractAmount;

        bool beforeGame = _statusId == 10 || _statusId == 13;
        bool betMatch = bet.accountA != address(0) && bet.accountB != address(0);
        bool noMatch = bet.accountB == address(0);

        if (beforeGame) {
            if (betMatch) {
                delete bets[_betIndex];
                _createBetB(bet.betPriceB, bet.contractAmount);
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
            bet.betPriceA,
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

        uint256 _stakedAmount = bet.betPriceB * bet.contractAmount;

        bool beforeGame = _statusId == 10 || _statusId == 13;
        bool betMatch = bet.accountA != address(0) && bet.accountB != address(0);
        bool noMatch = bet.accountA == address(0);

        if (beforeGame) {
            if (betMatch) {
                delete bets[_betIndex];
                _createBetA(bet.betPriceA, bet.contractAmount);
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
            bet.betPriceB,
            bet.contractAmount
        );
    }


    /**
     * @notice Executes the winning order/bet
     * @param _requestId the requestId returned by requestGame function
     * @param _idx match Id returned by requestGame function 
     * @param _betIndex the index of the bet that will be executed
     */
    function executeBet(   //--> execute based on info in Bet struct   
        bytes32 _requestId, 
        uint256 _idx,
        uint256 _betIndex
        ) external nonReentrant {

        require(_betIndex != 0, "Order does not exist");
        
        GameResolve memory game = getGameResult(_requestId, _idx);

        Bet memory bet = bets[_betIndex];

        require(bet.accountA != address(0) && bet.accountB != address(0), "Bet has not been filled");

        uint256 _totalStake = bet.betPriceA.add(bet.betPriceB).mul(bet.contractAmount);

        //if home wins --> bet won by side A
        if (game.homeScore > game.awayScore) {
            require(msg.sender == bet.accountA, "You are not the winner");
            uint256 _feeAdjustedStake = _totalStake - sendFeeToOwner(_totalStake);
            transferStake(bet.accountA, _feeAdjustedStake);

            emit BetExecuted(
                bet.accountA,
                bet.accountB,
                bet.betPriceA,
                bet.betPriceB,
                bet.contractAmount
            );
        //if away wins --> bet won by side B
        } else if (game.awayScore > game.homeScore) {
            require(msg.sender == bet.accountB, "You are not the winner");
            uint256 _feeAdjustedStake = _totalStake - sendFeeToOwner(_totalStake);
            transferStake(bet.accountB, _feeAdjustedStake);

            emit BetExecuted(
                bet.accountB,
                bet.accountA,
                bet.betPriceB,
                bet.betPriceA,
                bet.contractAmount
            );
        //if draw --> return funds back to users
        } else {
            returnFunds(bet.accountA, bet.accountB, 
            (bet.betPriceA.mul(bet.contractAmount)), 
            (bet.betPriceB.mul(bet.contractAmount)));
        }

        delete bets[_betIndex];

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