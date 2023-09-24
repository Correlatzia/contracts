// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {MainDemoConsumerBase} from "@redstone-finance/evm-connector/contracts/data-services/MainDemoConsumerBase.sol";
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
        int128 lastCorrelation;
        uint128 nonce;
    }

    struct OpenOrder {
        address user;
        uint256 notional;
        uint256 margin;
    }

    struct MatchedOrder {
        address user;
        uint256 notional;
        uint256 posted;
        int128 lastCorrelation;
        uint128 updateNonce;
    }

    struct OpenOrdersMarket {
        uint256 notionalUpPool;
        uint256 notionalDownPool;
        mapping(address => uint256) upOfferIndex;
        mapping(address => uint256) downOfferIndex;
        OpenOrder[] upOffers;
        OpenOrder[] downOffers;
    }

    struct MatchedOrdersMarket {
        uint256 totalNotional;
        MatchedOrder[] upPositions;
        MatchedOrder[] downPositions;
        mapping(address => uint256) upPositionIndex;
        mapping(address => uint256) downPositionIndex;
        int256 rebalanceAmount;
        uint256 settlementDate;
    }

    struct MarginCallTracking {
        uint64[] marginCallUps;
        uint64[] marginCallDowns;
    }

    uint256 constant ARITH_FACTOR = 1e6;
    uint256 constant MARGIN_FACTOR = 30; // in "percent"
    uint256 constant maturity = 30 days;
    uint256 public lastCorrelationUpdate = block.timestamp;

    // keys are pair in bytes32
    mapping(bytes32 => CircularBufferLib.Buffer) private priceDifferences;
    mapping(bytes32 => CorrelationData) public correlationData; // corr is in basis points
    mapping(bytes32 => OpenOrdersMarket) public openOrders;
    mapping(bytes32 => MatchedOrdersMarket) public matchedOrders;
    mapping(bytes32 => MarginCallTracking) private marginCallTracking;
    // Unalocated balance, can be use to set an order
    mapping(address => uint256) public balances;
    // saves the orders for a buyer

    IERC20 public usdc;

    event MakeOffer(
        address indexed user,
        bool isUp,
        uint256 notional,
        uint256 margin
    );
    event NewDeposit(address indexed seller, uint256 amount);
    event WithdrawFunds(address indexed seller, uint256 amount);

    // takeOffer(notional, marginAmount) -> getLatestCorrelation, update lastCorrelation and pairNonce
    // updateCorr(pair) -> correlationData[pair] latest correlations and ++correlationNonce
    // notifyMarginCall(pair, isUp, idx) -> marginList[pair] push to marginCallUps or marginCallDowns

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
    }

    function getOrder(
        address user,
        bytes32 pair,
        bool isUp
    ) external view returns (uint256 notional, uint256 posted) {
        OpenOrder memory order;

        if (isUp) {
            order = openOrders[pair].upOffers[
                openOrders[pair].upOfferIndex[user]
            ];
        } else {
            order = openOrders[pair].upOffers[
                openOrders[pair].upOfferIndex[user]
            ];
        }
        notional = order.notional;
        posted = order.margin;
    }

    function deposit(uint256 amount) external {
        require(amount > 0);
        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        // TBD protect from overflow
        balances[msg.sender] += amount;

        emit NewDeposit(msg.sender, amount);
    }

    // note: there is no bool check for order if user index is 0
    function modifyOrder(
        bytes32 pair,
        bool isUp,
        OpenOrder calldata updatedOrder
    ) external {
        OpenOrder storage order;
        if (isUp) {
            order = openOrders[pair].upOffers[
                openOrders[pair].upOfferIndex[msg.sender]
            ];
        } else {
            order = openOrders[pair].upOffers[
                openOrders[pair].upOfferIndex[msg.sender]
            ];
        }
        order.notional = updatedOrder.notional;
        order.margin = updatedOrder.margin;
    }

    function addMargin(
        bytes32 pair,
        bool isUp,
        uint256 additionalMargin
    ) external {
        MatchedOrder storage order;
        //     struct MatchedOrder {
        //     address user;
        //     uint256 notional;
        //     uint256 posted;
        //     int128 lastCorrelation;
        //     uint128 updateNonce;
        // }
        // TODO: nice to have - check if positoin already settled or liquidated

        if (isUp) {
            order = matchedOrders[pair].upPositions[
                matchedOrders[pair].upPositionIndex[msg.sender]
            ];
        } else {
            order = matchedOrders[pair].downPositions[
                matchedOrders[pair].downPositionIndex[msg.sender]
            ];
        }

        uint256 notionalToMarginDiff = order.notional - order.posted;
        require(
            additionalMargin <= notionalToMarginDiff,
            "margin exceeds notional"
        );

        order.posted += additionalMargin;

        // TODO: check what events you need
    }

    function make(
        bytes32 pair,
        bool isUp,
        uint256 notional,
        uint256 margin
    ) external {
        require(notional > 0, "notional must be gt 0");
        require(margin > 0, "margin must be gt 0");
        require(margin <= notional, "margin gt notional");

        uint256 _deposit = balances[msg.sender];
        require(_deposit >= margin, "insufficient balance");

        balances[msg.sender] -= margin;

        require(
            (margin * 100 * ARITH_FACTOR) / notional > margin * ARITH_FACTOR,
            "must be above margin level"
        );

        OpenOrdersMarket storage oo = openOrders[pair];
        if (isUp) {
            require(oo.upOfferIndex[msg.sender] == 0, "use modifyOrder");
            oo.notionalUpPool += notional;
            oo.upOffers.push(OpenOrder(msg.sender, notional, margin));
            oo.upOfferIndex[msg.sender] = oo.upOffers.length - 1;
        } else {
            require(oo.downOfferIndex[msg.sender] == 0, "use modifyOrder");
            oo.notionalUpPool += notional;
            oo.downOffers.push(OpenOrder(msg.sender, notional, margin));
            oo.downOfferIndex[msg.sender] = oo.downOffers.length - 1;
        }

        emit MakeOffer(msg.sender, isUp, notional, margin);
    }

    function take(
        bytes32[] calldata symbols, // can use pair key, but in future use to calculate uptodate corr
        bool isUp,
        uint256 notional,
        uint256 margin
    ) external {
        require(notional > 0, "notional must be gt 0");
        require(margin > 0, "margin must be gt 0");
        require(margin <= notional, "margin gt notional");

        uint256 _deposit = balances[msg.sender];
        require(_deposit >= margin, "insufficient balance");

        balances[msg.sender] -= margin;

        //   struct OpenOrdersMarket {
        //     uint256 notionalUpPool;
        //     uint256 notionalDownPool;
        //     mapping(address => uint256) upOfferIndex;
        //     mapping(address => uint256) downOfferIndex;
        //     OpenOrder[] upOffers;
        //     OpenOrder[] downOffers;
        // }

        require(
            (margin * 100 * ARITH_FACTOR) / notional > margin * ARITH_FACTOR,
            "must be above margin level"
        );

        bytes32 key = keccak256(abi.encodePacked(symbols[0], "/", symbols[1]));

        OpenOrdersMarket storage oo = openOrders[key];

        MatchedOrdersMarket storage mm = matchedOrders[key];
        if (mm.settlementDate == 0) {
            // refine this later
            mm.settlementDate = block.timestamp + 30 days;
        }
        mm.totalNotional += notional;
        uint256 idx = 0;

        if (!isUp) {
            uint256 upPool = oo.notionalUpPool;
            require(upPool > 0, "up pool is zero");
            bool isFullyMatched = notional < upPool;

            if (isFullyMatched) {
                oo.notionalUpPool -= notional;
            } else {
                oo.notionalUpPool = 0;
            }

            OpenOrder[] storage upOffers = oo.upOffers;
            uint256 upOffersLength = oo.upOffers.length;

            // struct MatchedOrdersMarket {
            //         uint256 totalNotional;
            //         MatchedOrder[] upPositions;
            //         MatchedOrder[] downPositions;
            // mapping(address => uint256) upPositionIndex;
            // mapping(address => uint256) downPositionIndex;
            //         int256 rebalanceAmount;
            //         uint256 settlementDate;
            // }

            (int128 corr, uint128 nonce) = executeLatestCorrelation(key);

            uint256 notionalRemaining = notional;
            while (true) {
                OpenOrder memory upOffer = upOffers[idx];

                uint256 upOfferNotional = upOffer.notional;

                if (upOfferNotional < notionalRemaining) {
                    mm.upPositions.push(
                        MatchedOrder(
                            upOffer.user,
                            upOfferNotional,
                            upOffer.margin,
                            corr,
                            nonce
                        )
                    );
                    mm.upPositionIndex[upOffer.user] =
                        mm.upPositions.length -
                        1;
                    notionalRemaining -= upOfferNotional;

                    delete upOffers[idx];
                    oo.upOfferIndex[upOffer.user] = 0;
                } else {
                    // note: this case needs to be handled, as margin ratio is different than expected
                    upOffers[idx].notional -= notionalRemaining;
                    notionalRemaining = 0;

                    mm.upPositions.push(
                        MatchedOrder(
                            upOffer.user,
                            notionalRemaining,
                            upOffer.margin,
                            corr,
                            nonce
                        )
                    );
                    mm.upPositionIndex[upOffer.user] =
                        mm.upPositions.length -
                        1;

                    break;
                }

                if (++idx > upOffersLength) {
                    break;
                }
            }

            MatchedOrder memory dPos;

            if (isFullyMatched) {
                oo.notionalDownPool -= notional;
                delete oo.downOffers[oo.downOfferIndex[msg.sender]];
                oo.downOfferIndex[msg.sender] = 0;
                dPos = MatchedOrder(msg.sender, notional, margin, corr, nonce);
            } else {
                uint256 notionalFilled = notional - notionalRemaining;

                oo
                    .downOffers[oo.downOfferIndex[msg.sender]]
                    .notional -= notionalFilled;
                oo.notionalDownPool -= notionalFilled;
                dPos = MatchedOrder(
                    msg.sender,
                    notionalFilled,
                    margin,
                    corr,
                    nonce
                );
            }
            mm.downPositions.push(dPos);
            mm.downPositionIndex[msg.sender] = mm.upPositions.length - 1;
        } else {
            // TODO: do up taker as inverse of above
        }

        // emit PlaceOrder(seller, msg.sender, amount);
    }

    /// @notice Allows user to withdraw from their unlocked balance
    /// @param amount amount of usdc tokens to withdraw
    function withdrawFunds(uint256 amount) external {
        uint256 balanceAmount = balances[msg.sender];
        require(balanceAmount >= amount, "not enough balance");

        balances[msg.sender] = balanceAmount - amount;
        usdc.transfer(msg.sender, amount);

        emit WithdrawFunds(msg.sender, amount);
    }

    function notifyMarginCall(
        bytes32 pair,
        bool isUp,
        address marginedUser
    ) external {
        if (isUp) {
            // TODO: should check a mapping to see if push was already made for user - can likely skip for hackathon
            marginCallTracking[pair].marginCallUps.push(
                uint64(openOrders[pair].upOfferIndex[marginedUser])
            );
        } else {
            // TODO: should check a mapping to see if push was already made for user
            marginCallTracking[pair].marginCallDowns.push(
                uint64(openOrders[pair].downOfferIndex[marginedUser])
            );
        }
    }

    function dailyCorrelationUpdate(
        bytes32 pair,
        bytes32[] calldata symbols
    ) external {
        // TODO: update only after 24hrs is passed check var
        // update correlation
        // calculate rebalance value
        // marginCallTracking just check if it's below margin ratio, then liquidate which means add to rebalance
        // if it liquidates ->
        // delete upOffers[idx];
        // oo.upOfferIndex[upOffer.user] = 0;
        // add to rebalance
    }

    // /// @notice allows a buyer to withdraw their order at maturity
    // /// @param index specifies the index of the order to redeem inside the order array for the buyer
    // function withdrawAtMaturity(uint256 index) external {
    //     OpenOrdersMarket memory order = openOrders[msg.sender][index];

    //     require(order.maturity <= block.timestamp, "Maturity not reached yet");
    //     require(order.active, "Order already redeemed");
    //     openOrders[msg.sender][index].active = false;

    //     uint256 newStrike = getCorrelationRate();
    //     uint256 sellerPayoff;
    //     uint256 buyerPayoff;
    //     console.log(newStrike, order.strike);
    //     uint256 payout = order.amount * (newStrike - order.strike);
    //     if (order.strike < newStrike) {
    //         // if correlation was stronger the payout goes to the seller + the amount
    //         sellerPayoff = order.amount + payout;
    //         buyerPayoff = order.amount - payout;
    //     } else {
    //         // if correlation was weaker the payout goes to the buyer + the amount he collateralized
    //         sellerPayoff = order.amount - payout;
    //         buyerPayoff = order.amount + payout;
    //     }
    //     // transfer payoff to seller
    //     usdc.transfer(order.seller, sellerPayoff);
    //     // transfer payoff to buyer
    //     usdc.transfer(msg.sender, buyerPayoff);
    // }

    /// @notice Returns current correlation
    function getCorrelationRate(
        bytes32 key
    ) public view returns (int128 value) {
        // gets current correlation
        value = 8000; // Not real code, just there for testing until we implement this function
    }

    /// @notice Update price difference for the day
    function updatePriceRing(
        bytes32 pairKey,
        bytes32[] calldata symbols
    ) external {
        (uint256 a, uint256 b) = getLatestPrice(symbols);
        priceDifferences[pairKey].push(uint128(a), uint128(b));
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

    function executeLatestCorrelation(
        bytes32 key
    ) private returns (int128 corr, uint128 nonce) {
        // TODO: calc correlation in basis points
        corr = getCorrelationRate(key);
        correlationData[key].lastCorrelation = corr;
        nonce = ++correlationData[key].nonce;
    }
}
