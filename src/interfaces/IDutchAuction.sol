// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TulipToken} from "src/TulipToken.sol";
import {Commitment} from "src/lib/Structs.sol";
import {IAuctionableToken} from "./IAuctionableToken.sol";

interface IDutchAuction {
    ////////// Events //////////
    event StartAuction(
        address token,
        uint256 supply,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 duration,
        uint256 bidderPercentageLimit
    );

    event Bid(address bidder, uint256 amount);

    event BidLimitOrder(
        address bidder,
        uint256 amount,
        uint256 targetPrice,
        uint256 bidTime
    );

    event AuctionSettled();

    event Withdraw(address successfulBidder, uint256 amountWon);

    event SoldOut(uint256 clearingPrice);

    ////////////////////////////

    /////// Main auction ///////
    function startAuction(
        TulipToken _token,
        uint256 _initialTokenSupply,
        uint256 _startingPrice,
        uint256 _reservePrice,
        uint256 _duration, // in minutes
        uint256 _bidderPercentageLimit
    ) external;

    function clearAuction() external;

    function withdraw() external;

    function isAuctioning() external view returns (bool);

    function getCurrentTokenSupply() external view returns (uint256);

    ////////////////////////////

    ///////// Biddings /////////
    function bid() external payable;

    function bidAtPrice(uint256 desiredPrice) external payable;

    ////////////////////////////

    ///////// Pricing /////////
    function getBlockTimestampAtPrice(
        uint256 price
    ) external view returns (uint256);

    function getCurrentPrice() external view returns (uint256);

    ////////////////////////////
}
