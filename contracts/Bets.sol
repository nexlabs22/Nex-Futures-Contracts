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
    address public admin;

    mapping(address => mapping(uint256 => mapping(uint256 => Order))) public orders;
    mapping(address => mapping(uint256 => uint256)) public ordersIndex;

    struct Order {
        address account;
        uint256 gameId;
        uint256 betPrice;
        uint256 contractAmount;
        bool side;
    }

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

    event OrderCreated (
        address indexed account,
        uint256 indexed gameId,
        uint256 betPrice,
        uint256 contractAmount,
        bool indexed side
    );

    event OrderCanceled (
        address indexed account,
        uint256 indexed gameId,
        uint256 betPrice,
        uint256 contractAmount,
        bool indexed side
    );

    event OrderExecuted (
        address indexed winner,
        address indexed loser,
        uint256 indexed gameId,
        uint256 winnerBetPrice,
        uint256 loserBetPrice,
        uint256 contractAmount
    );

    modifier onlyAdmin() {
        require(msg.sender == admin, "Forbidden");
        _;
    }

    constructor(
        address _usdc,
        address _link,
        address _oracle
    ) GameOracle(_link, _oracle) {
        usdc = _usdc;
        admin = msg.sender;
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

    /**
     * @notice changes the admin address
     * @param newAdmin the address of the new admin
     */
    function changeAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
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
    ) public {

        IERC20(usdc).safeTransfer(_account1, _amountAcc1);
        IERC20(usdc).safeTransfer(_account2, _amountAcc2);

        emit StakeReturned(address(this), _account1, _account2, usdc, _amountAcc1, _amountAcc2);
    }

    /**
     * @notice retrieves a specific order for the user using _betIndex and _orderIndex.
     * @param _gameId the id of the game of interest    
     * @param _orderIndex the index of the order for the _betIndex chosen by the user.
     */
    function getOrder(
        uint256 _gameId,
        uint256 _orderIndex
        ) 
        external view 
        returns (
            address account,
            uint256 gameId,
            uint256 betPrice,
            uint256 contractAmount,
            bool side
        )
    {
        require(
            msg.sender != address(0) 
            || _orderIndex != 0, 
            "Order does not exist");
            
        Order memory order = orders[msg.sender][_gameId][_orderIndex];

        return (
            order.account,
            order.gameId,
            order.betPrice,
            order.contractAmount,
            order.side
        );
    }

    /**
     * @notice creates an order
     * @param _gameId the id of the game of interest 
     * @param _contractAmount the amount of bet contracts set by the user.
     * @param _side the side chosen by the user. If true => expect homeTeam win, false => expect awayTeam win
     */
    function createOrder(
        uint256 _gameId,
        uint256 _betPrice, 
        uint256 _contractAmount, 
        bool _side
        ) external nonReentrant {

        Order memory order = Order(
            msg.sender,
            _gameId,
            _betPrice,
            _contractAmount,
            _side
        );

        ordersIndex[msg.sender][_gameId] += 1;
        uint256 _orderIndex = ordersIndex[msg.sender][_gameId];

        orders[msg.sender][_gameId][_orderIndex] = order;

        uint256 _stakedAmount = order.betPrice * order.contractAmount;

        depositStake(_stakedAmount);

        emit OrderCreated(
            order.account,
            order.gameId,
            order.betPrice,
            order.contractAmount,
            order.side
        );
    }

    /**
     * @notice Allows users to cancel orders
     * @param _gameId the id of the game of interest 
     * @param _orderIndex the index of the order for the _betIndex chosen by the user.
     */
    function cancelOrder(
        uint256 _gameId,
        uint256 _orderIndex
    ) external nonReentrant {
        require(
            msg.sender != address(0)
            || _orderIndex != 0, 
            "Order does not exist");

        Order memory order = orders[msg.sender][_gameId][_orderIndex];

        uint256 _stakedAmount = order.betPrice * order.contractAmount;

        delete orders[msg.sender][_gameId][_orderIndex];
        transferStake(msg.sender, _stakedAmount);

        emit OrderCanceled(
            msg.sender,
            order.gameId,
            order.betPrice,
            order.contractAmount,
            order.side
        );
    }

    /**
     * @notice Executes the winning order/bet
     * @param _requestId the requestId returned by requestGame function
     * @param _idx match Id returned by requestGame function 
     * @param _account1 the address of the winner of the bet
     * @param _account2 the address of the loser of the bet
     * @param _orderIndexAccount1 the index of the order for the _betIndex chosen by the user.
     * @param _orderIndexAccount2 the index of the order for the _betIndex chosen by the loser.
     */
    function executeWinner(        
        bytes32 _requestId, 
        uint256 _idx,
        address _account1,
        address _account2,
        uint256 _orderIndexAccount1,
        uint256 _orderIndexAccount2
        ) external onlyAdmin {
        
        GameResolve memory game = getGameResult(_requestId, _idx);
        uint256 _gameId = uint256(game.gameId);

        Order memory orderAccount1 = orders[_account1][_gameId][_orderIndexAccount1];
        Order memory orderAccount2 = orders[_account2][_gameId][_orderIndexAccount2];

        require(orderAccount1.side == !orderAccount2.side, "Similar sides were chosen");

        uint256 _transferAmountAcc1 = orderAccount1.betPrice.mul(orderAccount1.contractAmount);
        uint256 _transferAmountAcc2 = orderAccount2.betPrice.mul(orderAccount2.contractAmount);

        //if home wins & side of account 1 == true --> bet won by account 1
        if (game.homeScore > game.awayScore && orderAccount1.side) {
            _executeOrder(_gameId, orderAccount1.account, orderAccount2.account, _orderIndexAccount1, _orderIndexAccount2);
        //if away wins & side of account 1 == false --> bet won by account 1
        } else if (game.awayScore > game.homeScore && !orderAccount1.side) {
            _executeOrder(_gameId, orderAccount1.account, orderAccount2.account, _orderIndexAccount1, _orderIndexAccount2);
        //if home wins & side of account 2 == true --> bet won by account 2
        } else if (game.homeScore > game.awayScore && orderAccount2.side) {
            _executeOrder(_gameId, orderAccount2.account, orderAccount1.account, _orderIndexAccount2, _orderIndexAccount1);
        //if away wins & side of account 2 == false --> bet won by account 2
        } else if (game.awayScore > game.homeScore && !orderAccount2.side) {
            _executeOrder(_gameId, orderAccount2.account, orderAccount1.account, _orderIndexAccount2, _orderIndexAccount1);

        } else {
            returnFunds(orderAccount1.account, orderAccount2.account, _transferAmountAcc1, _transferAmountAcc2);
        }

    }

    /**
     * @notice Executes the matching order of a predetermined winner or loser
     * @param _gameId the id of the game of interest 
     * @param _winner the address of the winner of the bet
     * @param _loser the address of the loser of the bet
     * @param _orderIndexWinner the index of the order for the _betIndex chosen by the user.
     * @param _orderIndexLoser the index of the order for the _betIndex chosen by the loser.
     */
    function _executeOrder(
        uint256 _gameId,
        address _winner,
        address _loser,
        uint256 _orderIndexWinner,
        uint256 _orderIndexLoser
    ) internal  {
        require(
            _winner != address(0)
            || _loser != address(0) 
            || _orderIndexWinner != 0
            || _orderIndexLoser != 0, 
            "Order does not exist");

        Order memory orderWinner = orders[_winner][_gameId][_orderIndexWinner];
        Order memory orderLoser = orders[_loser][_gameId][_orderIndexLoser];

        require(orderWinner.betPrice == (1*10**18 - orderLoser.betPrice), "Bet prices do not match");
        
        uint256 _transferAmountLoser = orderLoser.betPrice.mul(orderLoser.contractAmount);
        uint256 _transferAmountWinner = orderLoser.betPrice.mul(orderWinner.contractAmount);
        uint256 _totalTransfer = _transferAmountLoser + _transferAmountWinner;

        transferStake(_winner, _totalTransfer);       

        delete orders[_winner][_gameId][_orderIndexWinner];
        delete orders[_loser][_gameId][_orderIndexLoser];

        emit OrderExecuted(
            orderWinner.account,
            orderLoser.account,
            orderWinner.gameId,
            orderWinner.betPrice,
            orderLoser.betPrice,
            orderWinner.contractAmount
        );
    }
}