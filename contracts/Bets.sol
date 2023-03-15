//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Bets is ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public usdc;

    mapping(address => mapping(uint256 => mapping(uint256 => Order))) public orders;
    mapping(address => mapping(uint256 => uint256)) public ordersIndex;

    struct Order {
        address account;
        uint256 betIndex;
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

    event OrderCreated (
        address indexed account,
        uint256 indexed betIndex,
        uint256 betPrice,
        uint256 contractAmount,
        bool indexed side
    );

    event OrderCanceled (
        address indexed account,
        uint256 indexed betIndex,
        uint256 betPrice,
        uint256 contractAmount,
        bool indexed side
    );

    event OrderExecuted (
        address indexed winner,
        address indexed loser,
        uint256 indexed betIndex,
        uint256 winnerBetPrice,
        uint256 loserBetPrice,
        uint256 contractAmount
    );

    constructor(
        address _usdc
    ) {
        usdc = _usdc;
    }

    /**
     * @dev deposits the stake determined by the user.
     * @param _amount the amount of USDC that will be transferred.
     */
    function depositStake(
        uint256 _amount
    ) internal {

        IERC20(usdc).safeTransferFrom(msg.sender, address(this), _amount);

        emit StakeTransferred(msg.sender, address(this), usdc, _amount);
    }
    
    /**
     * @dev transfer the stake set by the user
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
     * @dev retrieves a specific order for the user using _betIndex and _orderIndex.
     * @param _betIndex the index of the bet, e.g. football game: index 1, boxing game: index 2, etc.
     * @param _orderIndex the index of the order for the _betIndex chosen by the user.
     */
    function getOrder(
        uint256 _betIndex, 
        uint256 _orderIndex
        ) 
        external view 
        returns (
            address account,
            uint256 betIndex,
            uint256 betPrice,
            uint256 contractAmount,
            bool side
        )
    {
        require(
            msg.sender != address(0) 
            || _betIndex != 0  
            || _orderIndex != 0, 
            "Order does not exist");
            
        Order memory order = orders[msg.sender][_betIndex][_orderIndex];

        return (
            order.account,
            order.betIndex,
            order.betPrice,
            order.contractAmount,
            order.side
        );
    }

    /**
     * @dev create an order
     * @param _betIndex the index of the bet, e.g. football game: index 1, boxing game: index 2, etc.
     * @param _betPrice the price of the bet set by the user between 0 and 1 USD
     * @param _contractAmount the amount of bet contracts set by the user.
     * @param _side the side chosen by the user
     */
    function createOrder(
        uint256 _betIndex, 
        uint256 _betPrice, 
        uint256 _contractAmount, 
        bool _side
        ) external nonReentrant {

        Order memory order = Order(
            msg.sender,
            _betIndex,
            _betPrice,
            _contractAmount,
            _side
        );

        ordersIndex[msg.sender][_betIndex] += 1;
        uint256 _orderIndex = ordersIndex[msg.sender][_betIndex];

        orders[msg.sender][_betIndex][_orderIndex] = order;

        uint256 _stakedAmount = order.betPrice * order.contractAmount;

        depositStake(_stakedAmount);

        emit OrderCreated(
            order.account,
            order.betIndex,
            order.betPrice,
            order.contractAmount,
            order.side
        );
    }

    /**
     * @dev Allows users to cancel orders
     * @param _betIndex the index of the bet, e.g. football game: index 1, boxing game: index 2, etc.
     * @param _orderIndex the index of the order for the _betIndex chosen by the user.
     */
    function cancelOrder(
        uint256 _betIndex,
        uint256 _orderIndex
    ) external nonReentrant {
        require(
            msg.sender != address(0) 
            || _betIndex != 0  
            || _orderIndex != 0, 
            "Order does not exist");

        Order memory order = orders[msg.sender][_betIndex][_orderIndex];

        uint256 _stakedAmount = order.betPrice * order.contractAmount;

        delete orders[msg.sender][_betIndex][_orderIndex];
        transferStake(msg.sender, _stakedAmount);

        emit OrderCanceled(
            msg.sender,
            order.betIndex,
            order.betPrice,
            order.contractAmount,
            order.side
        );
    }


    /**
     * @dev Executes the matching order of a predetermined winner or loser
     * @param _winner the address of the winner of the bet
     * @param _loser the address of the loser of the bet
     * @param _betIndex the index of the bet, e.g. football game: index 1, boxing game: index 2, etc.
     * @param _orderIndexWinner the index of the order for the _betIndex chosen by the user.
     * @param _orderIndexLoser the index of the order for the _betIndex chosen by the loser.
     */
    function executeOrder(
        address _winner,
        address _loser,
        uint256 _betIndex,
        uint256 _orderIndexWinner,
        uint256 _orderIndexLoser
    ) external {
        require(
            _winner != address(0)
            || _loser != address(0) 
            || _betIndex != 0  
            || _orderIndexWinner != 0
            || _orderIndexLoser != 0, 
            "Order does not exist");

        Order memory orderWinner = orders[_winner][_betIndex][_orderIndexWinner];
        Order memory orderLoser = orders[_loser][_betIndex][_orderIndexLoser];

        require(orderWinner.betPrice == (1*10**18 - orderLoser.betPrice), "Bet prices do not match");
        
        uint256 _transferAmountLoser = orderLoser.betPrice.mul(orderLoser.contractAmount);
        uint256 _transferAmountWinner = orderLoser.betPrice.mul(orderWinner.contractAmount);
        uint256 _totalTransfer = _transferAmountLoser + _transferAmountWinner;

        transferStake(_winner, _totalTransfer);       

        delete orders[_winner][_betIndex][_orderIndexWinner];
        delete orders[_loser][_betIndex][_orderIndexLoser];

        emit OrderExecuted(
            orderWinner.account,
            orderLoser.account,
            orderWinner.betIndex,
            orderWinner.betPrice,
            orderLoser.betPrice,
            orderWinner.contractAmount
        );
    }
}