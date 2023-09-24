// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@redstone-finance/evm-connector/contracts/data-services/MainDemoConsumerBase.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./CircularBufferLib.sol";
import "hardhat/console.sol";

/// @title Correlation Swaps
/// @author Correlatzia team
/// @notice This contract can be use to perform correlation swaps on chain
contract Orders is MainDemoConsumerBase {
    using CircularBufferLib for CircularBufferLib.Buffer;

    struct PriceDiff {
        uint128 tokenAPrice;
        uint128 tokenBPrice;
    }

    struct CorrelationData {
        uint256 lastCorrelation;
        uint256 nonce;
    }

    struct OpenOrdersMarket {
        uint256 totalNotionalUp;
        uint256 totalNotionalDown;
        Side[] upOffers;
        Side[] downOffers;
    }

    struct Side {
        uint256 notional;
        uint256 posted;
        uint256 updateNonce;
    }

    struct MatchedOrdersMarket {
        uint256 totalNotional;
        Side[] up;
        Side[] down;
        int256 rebalanceAmount;
        uint256 settlementDate;
    }

    struct MarginCallTracking {
        uint64[] marginCallUps;
        uint64[] marginCallDowns;
    }

    struct Order {
        address seller;
        uint256 amount;
        uint256 strike;
        uint256 maturity;
        bool active;
    }

    // keys are pair in bytes32
    mapping(bytes32 => CircularBufferLib.Buffer) private priceDifferences;
    mapping(bytes32 => CorrelationData) public correlationData;
    mapping(bytes32 => OpenOrdersMarket) public openOrders;
    mapping(bytes32 => MatchedOrdersMarket) public matchedOrders;
    mapping(bytes32 => MarginCallTracking) private marginCallTracking;
    // Unalocated balance, can be use to set an order
    mapping(address => uint256) public balances;
    // saves the orders for a buyer
    mapping(address => Order[]) public orders; //TBD can i avoid using an array here?

    IERC20 public usdc;

    uint256 immutable maturity = 30 days;

    event PlaceOrder(
        address indexed seller,
        address indexed buyer,
        uint256 amount
    );
    event NewDeposit(address indexed seller, uint256 amount, uint256 strike);
    event WithdrawFunds(address indexed seller, uint256 amount);

    constructor(address _usdc, address aggregatorBTC, address aggregatorETH) {
        usdc = IERC20(_usdc);
    }

    /// @notice Returns amount and seller for specific order
    function getOrder(
        uint256 index
    ) external view returns (uint256 amount, address seller) {
        Order memory order = orders[msg.sender][index];
        amount = order.amount;
        seller = order.seller;
    }

    /// @notice Returns amount and seller for specific order
    function getBalance(address seller) external view returns (uint256 amount) {
        amount = balances[seller];
    }

    /// @notice Allows users to deposit USDC for a buyer to buy. Uses the allowance to get the deposit amount
    /// @param strike the sellers accepted future strike calculation
    function deposit(uint256 strike) external {
        uint256 amount = usdc.allowance(msg.sender, address(this));
        require(amount > 0);
        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        // TBD protect from overflow
        balances[msg.sender] += amount;

        emit NewDeposit(msg.sender, amount, strike);
    }

    /// @notice Allows buyer to buy a position from available balances
    /// @param amount amount to be transfer at maturity
    /// @param seller address of seller with enough liquidity
    function buy(uint256 amount, address seller) external {
        require(amount > 0, "Invalid amount");
        uint256 _deposit = balances[seller];
        require(_deposit >= amount, "Invalid seller amount");

        require(
            usdc.allowance(msg.sender, address(this)) >= amount,
            "Not enough allowance"
        );
        require(usdc.transferFrom(msg.sender, address(this), amount));

        // Order memory order = Order(
        //     seller,
        //     amount,
        //     block.timestamp + maturity,
        //     true
        // );

        balances[seller] = _deposit - amount;
        // orders[msg.sender].push(order);

        emit PlaceOrder(seller, msg.sender, amount);
    }

    /// @notice Allows user to withdraw from their unlocked balance
    /// @param amount amount of usdc tokens to withdraw
    function withdrawFunds(uint256 amount) external {
        uint256 balanceAmount = balances[msg.sender];
        require(balanceAmount >= amount, "Not enough ablance");

        balances[msg.sender] = balanceAmount - amount;
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
        usdc.transfer(msg.sender, buyerPayoff);
    }

    /// @notice Returns current correlation
    function getCorrelationRate() public view returns (uint256 value) {
        // gets current correlation
        value = 12; // Not real code, just there for testing until we implement this function
    }

    /// @notice Update price difference for the day
    function updatePriceRing(bytes32[] calldata symbols) external {
        (uint256 a, uint256 b) = getLatestPrice(symbols);
        priceDifferences.push(uint128(a), uint128(b));
    }

    /// @notice Gets the USDC price for BTC and ETH
    function getLatestPrice(
        bytes32[] calldata symbols
    ) public view returns (uint256 a, uint256 b) {
        // bytes32[] memory dataFeedIds = new bytes32[](2);
        // dataFeedIds[0] = bytes32(aSymbol);
        // dataFeedIds[1] = bytes32(bSymbol);
        uint256[] memory values = getOracleNumericValuesFromTxMsg(symbols);
        a = values[0];
        b = values[1];
    }
}
