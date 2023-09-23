// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/*
* @title Correlation Swaps
* @author Correlatzia team
* @notice This contract can be use to perform correlation swaps on chain
*/
contract Orders {// TBD set the right name
    struct Order {
        address seller;
        address buyer;
        uint256 amount;
        uint256 fixesP;
        uint256 maturity;
    }
    // Unalocated balance, can be use to set an order
    mapping(address => uint256) public balance;

    //ERC20 constant USDC;

    constructor() {

    }

    function deposit() external {

    }

    function buy() external {

    }

    function withdraw() external {

    }
}