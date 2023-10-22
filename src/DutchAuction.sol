// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract DutchAuction {
    uint256 public MAX_SUPPLY = 1000000;
    uint256 public amountAuctioned;
    uint256 public currentSupply;
    uint256 public startingPrice;
    uint256 public discountRate;
    uint256 public minimumPrice;
    uint256 public auctionStartTime;
    uint256 public auctionDuration;

    function startAuction(uint256 startingPrice, uint256 discountRate, uint256 lowestPrice, uint256 amount, uint256 auctionTime) public {
        require(amountAuctioned + amount <= MAX_SUPPLY, "The number of tokens minted exceeds the maximum supply");
        currentSupply = amount;
        startingPrice = startingPrice;
        discountRate = discountRate;
        minimumPrice = lowestPrice;
        auctionDuration = auctionTime;
        auctionStartTime = block.timestamp;
    }

    function getPrice() public returns (uint256 price) {
        if (startingPrice < discountRate * (block.timestamp - auctionStartTime) + minimumPrice){
            return minimumPrice;
        }
        return startingPrice - discountRate * (block.timestamp - auctionStartTime);
    }

    function bid(uint256 amount) external {

    }
}