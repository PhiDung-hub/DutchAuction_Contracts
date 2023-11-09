// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Token
error MintLimitExceeded(uint256 amount, uint256 limit);


// Auction state
error AuctionIsStarted();
error AuctionIsInactive();
error AuctionIsNotStarted();
error AuctionIsNotEnded();
error NotWithdrawableYet(uint256 timeRemaining);
error InvalidPrices(uint256 startingPrice, uint256 reservePrice);

// Futures error
error AuctionIsSettled();

// Biddings
error ZeroCommitted();
error BidLimitReached();
