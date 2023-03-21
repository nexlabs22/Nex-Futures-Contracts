//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {GameOracle} from "./GameOracle.sol";

contract Bets is ReentrancyGuard, GameOracle {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public usdc;
    address public owner;
    address public admin;
    uint256 public executionFee = 10; //=> 10/10000 = 0.1%

    mapping(uint256 => mapping(uint256 => Order)) public ordersSideA;
    mapping(uint256 => mapping(uint256 => Order)) public ordersSideB;

    mapping(address => mapping(uint256 => uint256)) public ordersIndex;

    struct Order {
        address account;
        uint256 gameId;
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

    event OrderCreatedSideA(
        address indexed account,
        uint256 indexed orderIndex,
        uint256 indexed gameId,
        uint256 betPrice,
        uint256 contractAmount
    );

    event OrderCreatedSideB(
        address indexed account,
        uint256 indexed orderIndex,
        uint256 indexed gameId,
        uint256 betPrice,
        uint256 contractAmount
    );

    event OrderCanceled(
        address indexed account,
        uint256 indexed orderIndex,
        uint256 indexed gameId,
        uint256 betPrice,
        uint256 contractAmount
    );

    event OrderExecuted(
        address indexed accountSideA,
        address indexed accountSideB,
        uint256 indexed gameId,
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
        require(_newFee <= 500 && _newFee >= 1, "New fee out of range");
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

    /**
     * @notice creates a side A order
     * @param _gameId the id of the game of interest 
     * @param _contractAmount the amount of bet contracts set by the user.
     */
    function createOrderSideA(
        uint256 _gameId,
        uint256 _betPrice, 
        uint256 _contractAmount
        ) external nonReentrant {

        Order memory order = Order(
            msg.sender,
            _gameId,
            _betPrice,
            _contractAmount
        );

        ordersIndex[msg.sender][_gameId] += 1;
        uint256 _orderIndex = ordersIndex[msg.sender][_gameId];

        ordersSideA[_gameId][_orderIndex] = order;

        uint256 _stakedAmount = order.betPrice * order.contractAmount;

        depositStake(_stakedAmount);

        emit OrderCreatedSideA(
            msg.sender,
            _orderIndex,
            order.gameId,
            order.betPrice,
            order.contractAmount
        );
    }

    /**
     * @notice creates a side B order
     * @param _gameId the id of the game of interest 
     * @param _contractAmount the amount of bet contracts set by the user.
     */
    function createOrderSideB(
        uint256 _gameId,
        uint256 _betPrice, 
        uint256 _contractAmount
        ) external nonReentrant {

        Order memory order = Order(
            msg.sender,
            _gameId,
            _betPrice,
            _contractAmount
        );

        ordersIndex[msg.sender][_gameId] += 1;
        uint256 _orderIndex = ordersIndex[msg.sender][_gameId];

        ordersSideB[_gameId][_orderIndex] = order;

        uint256 _stakedAmount = order.betPrice * order.contractAmount;

        depositStake(_stakedAmount);

        emit OrderCreatedSideB(
            msg.sender,
            _orderIndex,
            order.gameId,
            order.betPrice,
            order.contractAmount
        );
    }

    /**
     * @notice Allows users to cancel side A orders
     * @param _gameId the id of the game of interest 
     * @param _orderIndex the index of the order for the _betIndex chosen by the user.
     */
    function cancelOrderSideA(
        uint256 _gameId,
        uint256 _orderIndex
    ) external nonReentrant {
        require(
            msg.sender != address(0)
            || _orderIndex != 0, 
            "Order does not exist");

        Order memory order = ordersSideA[_gameId][_orderIndex];

        require(msg.sender == order.account, "Not your order");

        uint256 _stakedAmount = order.betPrice * order.contractAmount;

        delete ordersSideB[_gameId][_orderIndex];

        transferStake(msg.sender, _stakedAmount);

        emit OrderCanceled(
            msg.sender,
            _orderIndex,
            order.gameId,
            order.betPrice,
            order.contractAmount
        );
    }

    /**
     * @notice Allows users to cancel side B orders
     * @param _gameId the id of the game of interest 
     * @param _orderIndex the index of the order for the _betIndex chosen by the user.
     */
    function cancelOrderSideB(
        uint256 _gameId,
        uint256 _orderIndex
    ) external nonReentrant {
        require(
            msg.sender != address(0)
            || _orderIndex != 0, 
            "Order does not exist");

        Order memory order = ordersSideB[_gameId][_orderIndex];

        require(msg.sender == order.account, "Not your order");

        uint256 _stakedAmount = order.betPrice * order.contractAmount;

        delete ordersSideB[_gameId][_orderIndex];

        transferStake(msg.sender, _stakedAmount);

        emit OrderCanceled(
            msg.sender,
            _orderIndex,
            order.gameId,
            order.betPrice,
            order.contractAmount
        );
    }


    /**
     * @notice Executes the winning order/bet
     * @param _requestId the requestId returned by requestGame function
     * @param _idx match Id returned by requestGame function 
     * @param _sideA the address of the winner of the bet
     * @param _sideB the address of the loser of the bet
     * @param _orderIndexSideA the index of the order for the _betIndex chosen by the user.
     * @param _orderIndexSideB the index of the order for the _betIndex chosen by the loser.
     */
    function executeOrder(        
        bytes32 _requestId, 
        uint256 _idx,
        address _sideA,
        address _sideB,
        uint256 _orderIndexSideA,
        uint256 _orderIndexSideB
        ) external nonReentrant {

        require(
            _sideA != address(0)
            || _sideB != address(0) 
            || _orderIndexSideA != 0
            || _orderIndexSideB != 0, 
            "Order does not exist");
        
        GameResolve memory game = getGameResult(_requestId, _idx);
        uint256 _gameId = uint256(game.gameId);

        Order memory orderSideA = ordersSideA[_gameId][_orderIndexSideA];
        Order memory orderSideB = ordersSideB[_gameId][_orderIndexSideB];

        require(orderSideA.betPrice == (10**18 - orderSideB.betPrice), "Bet prices do not match");

        uint256 _transferAmountSideA = orderSideA.betPrice.mul(orderSideA.contractAmount);
        uint256 _transferAmountSideB = orderSideB.betPrice.mul(orderSideB.contractAmount);
        uint256 _totalTransfer = _transferAmountSideA.add(_transferAmountSideB);

        //if home wins --> bet won by side A
        if (game.homeScore > game.awayScore) {
            require(msg.sender == orderSideA.account, "You are not the winner");
            uint256 _feeAdjustedTransfer = _totalTransfer - sendFeeToOwner(_totalTransfer);
            transferStake(orderSideA.account, _feeAdjustedTransfer); 
        //if away wins --> bet won by side B
        } else if (game.awayScore > game.homeScore) {
            require(msg.sender == orderSideB.account, "You are not the winner");
            uint256 _feeAdjustedTransfer = _totalTransfer - sendFeeToOwner(_totalTransfer);
            transferStake(orderSideB.account, _feeAdjustedTransfer);
        //if draw --> return funds back to users
        } else {
            returnFunds(orderSideA.account, orderSideB.account, _transferAmountSideA, _transferAmountSideB);
        }

        delete ordersSideA[_gameId][_orderIndexSideA];
        delete ordersSideB[_gameId][_orderIndexSideB];

        emit OrderExecuted(
            orderSideA.account,
            orderSideB.account,
            orderSideA.gameId,
            orderSideA.betPrice,
            orderSideB.betPrice,
            orderSideA.contractAmount
        );

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