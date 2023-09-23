// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@redstone-finance/evm-connector/contracts/data-services/MainDemoConsumerBase.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./CircularBufferLib.sol";
import "hardhat/console.sol";


/// @title Correlation Swaps
/// @author Correlatzia team
/// @notice This contract can be use to perform correlation swaps on chain
contract Orders  is MainDemoConsumerBase {
    using CircularBufferLib for CircularBufferLib.Buffer;
    struct Deposit {
        uint256 balance;
        uint256 strike;
    }

    struct Order {
        address seller;
        uint256 amount;
        uint256 strike;
        uint256 maturity;
        bool active;
    }

    CircularBufferLib.Buffer private priceDifferences;
    // Unalocated balance, can be use to set an order
    mapping(address => Deposit) public balances;
    // saves the orders for a buyer
    mapping(address => Order[]) public orders; //TBD can i avoid using an array here?

    IERC20 public usdc;

    uint256 immutable maturity = 30 days;

    event PlaceOrder(address indexed seller, address indexed buyer, uint256 amount);
    event NewDeposit(address indexed seller, uint256 amount, uint256 strike);
    event WithdrawFunds(address indexed seller, uint256 amount);

    constructor(address _usdc, address aggregatorBTC, address aggregatorETH) {
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

        emit NewDeposit(msg.sender, amount, strike);
    }

    /// @notice Allows buyer to buy a position from available balances
    /// @param amount amount to be transfer at maturity
    /// @param seller address of seller with enough liquidity
    function buy(uint256 amount, address seller) external {
        require(amount > 0, "Invalid amount");
        Deposit memory _deposit = balances[seller];
        require(_deposit.balance >= amount, "Invalid seller amount");
        
        require(usdc.allowance(msg.sender, address(this)) >= amount, "Not enough allowance");
        require(usdc.transferFrom(msg.sender, address(this), amount));
        
        Order memory order = Order(seller, amount, _deposit.strike, block.timestamp + maturity, true);
        
        balances[seller].balance = _deposit.balance - amount;
        orders[msg.sender].push(order);

        emit PlaceOrder(seller, msg.sender, amount);
    }

    /// @notice Allows user to withdraw from their unlocked balance
    /// @param amount amount of usdc tokens to withdraw
    function withdrawFunds(uint256 amount) external {
        uint256 balanceAmount = balances[msg.sender].balance;
        require(balanceAmount >= amount, "Not enough ablance");

        balances[msg.sender].balance = balanceAmount - amount;
        usdc.transfer(msg.sender, amount);

        emit WithdrawFunds(msg.sender, amount);
    }

    /// @notice allows a buyer to withdraw their order at maturity
    /// @param index specifies the index of the order to redeem inside the order array for the buyer
    function withdrawAtMaturity(uint256 index) external {
        Order memory order = orders[msg.sender][index];
        
        require(order.maturity <= block.timestamp, "Maturity not reached yet");
        require(order.active, "Order already redeemed");
        orders[msg.sender][index].active = false;

        uint256 newStrike = getCorrelationRate();
        uint256 sellerPayoff;
        uint256 buyerPayoff; 
        console.log(newStrike, order.strike);
        uint256 payout = order.amount * (newStrike - order.strike);
        if (order.strike < newStrike) {
            // if correlation was stronger the payout goes to the seller + the amount
            sellerPayoff = order.amount + payout;
            buyerPayoff = order.amount - payout;
        } else {
            // if correlation was weaker the payout goes to the buyer + the amount he collateralized
            sellerPayoff = order.amount - payout;
            buyerPayoff = order.amount + payout;
        }
        // transfer payoff to seller
        usdc.transfer(order.seller, sellerPayoff);
        // transfer payoff to buyer
        usdc.transfer(msg.sender,  buyerPayoff);
        
    }

    /// @notice Returns current correlation
    function getCorrelationRate() public returns (uint256 value) {
        // gets current correlation
        value = 12; // Not real code, just there for testing until we implement this function
    }

    /// @notice Update price difference for the day
    function updatePriceRing() external {
        (uint256 btc, uint256 eth) = getLatestPrice();
        priceDifferences.push(btc - eth);//TBD
    }

    /// @notice Gets the USDC price for BTC and ETH
    function getLatestPrice(string aSymbol, string bSymbol) public view returns (uint256 a, uint256 b) {
        bytes32[] memory dataFeedIds = new bytes32[](2);
        dataFeedIds[0] = bytes32(aSymbol);
        dataFeedIds[1] = bytes32(bSymbol);
        uint256[] memory values = getOracleNumericValuesFromTxMsg(dataFeedIds);
        a = values[0];
        b = values[1];
    }
}