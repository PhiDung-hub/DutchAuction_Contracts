// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

struct Commitment {
    address bidder;
    uint256 amount;
    uint256 timeCommitted;
    uint256 timeBidded;
}
