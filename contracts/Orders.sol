// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import "hardhat/console.sol";


/// @title Correlation Swaps
/// @author Correlatzia team
/// @notice This contract can be use to perform correlation swaps on chain
contract Orders {// TBD set the right name
    struct Deposit {
        uint256 balance;
        uint256 strike;
    }

    struct Order {
        address seller;
        uint256 amount;
        uint256 fixedP;
        uint256 maturity;
        bool active;
    }
    // Unalocated balance, can be use to set an order
    mapping(address => Deposit) public balances;
    // saves the orders for a buyer
    mapping(address => Order[]) public orders; //TBD can i avoid using an array here?

    IERC20 public usdc;

    uint256 immutable maturity = 30 days;

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
    }

    /// @notice Returns amount and seller for specific order
    function getOrder(uint256 index) view external returns(uint256 amount, address seller) {
        Order memory order = orders[msg.sender][index];
        amount = order.amount;
        seller = order.seller;
    }

    /// @notice Returns amount and seller for specific order
    function getBalance(address seller) view external returns(uint256 amount) {
        Deposit memory info = balances[seller];
        amount = info.balance;
    }

    /// @notice Allows users to deposit USDC for a buyer to buy. Uses the allowance to get the deposit amount
    /// @param strike the sellers accepted future strike calculation
    function deposit(uint256 strike) external {
        uint256 amount = usdc.allowance(msg.sender, address(this));
        require(amount > 0);
        require(usdc.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        // TBD protect from overflow
        balances[msg.sender].balance += amount;
        balances[msg.sender].strike = strike;
    }

    /// @notice Allows buyer to buy a position from available balances
    /// @param amount amount to be transfer at maturity
    /// @param seller address of seller with enough liquidity
    function buy(uint256 amount, address seller) external payable {
        require(amount > 0, "Invalid amount");
        Deposit memory _deposit = balances[seller];
        require(_deposit.balance >= amount, "Invalid seller amount");
        require(msg.value >= _deposit.strike, "Not enough funds send");
        Order memory order = Order(seller, amount, _deposit.strike, block.timestamp + maturity, true);
        
        balances[seller].balance = _deposit.balance - amount;
        orders[msg.sender].push(order);
    }

    /// @notice Allows user to withdraw from their unlocked balance
    /// @param amount amount of usdc tokens to withdraw
    function withdrawFunds(uint256 amount) external {
        uint256 balanceAmount = balances[msg.sender].balance;
        require(balanceAmount >= amount, "Not enough ablance");

        balances[msg.sender].balance = balanceAmount - amount;
        usdc.transfer(msg.sender, amount);
    }

    /// @notice allows a buyer to withdraw their order at maturity
    /// @param index specifies the index of the order to redeem inside the order array for the buyer
    function withdrawAtMaturity(uint256 index) external {
        Order memory order = orders[msg.sender][index];
        //TBD where do we compute the realized P?
        require(order.maturity <= block.timestamp, "Maturity not reached yet");
        require(order.active, "Order already redeemed");
        orders[msg.sender][index].active = false;
        // transfer usdc to buyer
        usdc.transfer(msg.sender, order.amount);
        // transfer eth to seller
        require(payable(order.seller).send(order.fixedP), "Eth trasnfer failed");
        
    }

    /// @notice computes the expected strike based on the historical correlation data
    function getRate() internal returns (uint256 value) {
        //TBD when this is ready add msg.value test for buy function
    }
}