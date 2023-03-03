//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Collateral {
    using SafeMath for uint256;

    address public usdc;

    mapping(address => mapping(address => uint256)) public collateral;

    event Deposit(address token, address user, uint256 amount, uint256 balance);
    event Withdraw(address token, address user, uint256 amount, uint256 balance);

    constructor(
        address _usdc
    ) {
        usdc = _usdc;
    }

    /**
     * @dev Deposits USDC collateral from user to contract
     * @param _amount the amount deposited in USDC
     */
    function depositCollateral(uint256 _amount) public {
        SafeERC20.safeTransferFrom(IERC20(usdc), msg.sender, address(this), _amount);
        collateral[usdc][msg.sender] = collateral[usdc][msg.sender].add(_amount);
        
        emit Deposit(usdc, msg.sender, _amount, collateral[usdc][msg.sender]);
    }

    /**
     * @dev Withdraws USDC collateral from contract to user
     * @param _amount the amount withdrawn in USDC
     */
    function withdrawCollateral(uint256 _amount) public {
        require(collateral[usdc][msg.sender] >= _amount, 
        "Requested withdrawal amount larger than collateral balance");

        SafeERC20.safeTransfer(IERC20(usdc), msg.sender, _amount);
        collateral[usdc][msg.sender] = collateral[usdc][msg.sender].sub(_amount);

        emit Withdraw(usdc, msg.sender, _amount, collateral[usdc][msg.sender]);
    }
}