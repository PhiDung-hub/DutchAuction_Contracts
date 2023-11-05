// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface IAuctionableToken {
    event OperatorMint(uint256 amount);

    function operatorMint(uint256 amount) external;
}
