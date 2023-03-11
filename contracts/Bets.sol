//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Bets is ReentrancyGuard {
    using SafeMath for uint256;

    address public usdc;

        // _orderOwner      //betIndex         //_orderIndex
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
        SafeERC20.safeTransferFrom(IERC20(usdc), msg.sender, address(this), _amount);
        emit StakeTransferred(msg.sender, address(this), usdc, _amount);
    }
    
    /**
     * @dev deposits the stake determined by the user.
     * @param _amount the amount of USDC that will be transferred.
     */
    function withdrawStake(
        uint256 _amount
    ) internal {
        SafeERC20.safeTransfer(IERC20(usdc), msg.sender, _amount);
        emit StakeTransferred(address(this), msg.sender, usdc, _amount);
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
        ) external payable nonReentrant {

        Order memory order = Order(
            msg.sender,
            _betIndex,
            _betPrice,
            _contractAmount,
            _side
        );
        uint256 _orderIndex = ordersIndex[msg.sender][_betIndex];
        _orderIndex.add(1);
        orders[msg.sender][_betIndex][_orderIndex] = order;

        depositStake(_betPrice * _contractAmount);

        emit OrderCreated(
            order.account,
            order.betIndex,
            order.betPrice,
            order.contractAmount,
            order.side
        );
    }

    function cancelOrder(
        uint256 _betIndex,
        uint256 _orderIndex
    ) external payable nonReentrant {
        Order memory order = orders[msg.sender][_betIndex][_orderIndex];
        require(msg.sender != address(0), "Order does not exist");

        uint256 stakedAmount = order.betPrice * order.contractAmount;

        delete orders[msg.sender][_betIndex][_orderIndex];
        withdrawStake(stakedAmount);

        emit OrderCanceled(
            msg.sender,
            order.betIndex,
            order.betPrice,
            order.contractAmount,
            order.side
        );
    }
}