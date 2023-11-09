// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "src/lib/Errors.sol";
import {ReentrancyGuard} from "src/lib/ReentrancyGuard.sol";
import {IDutchAuction} from "src/interfaces/IDutchAuction.sol";
import {IAuctionableToken} from "src/interfaces/IAuctionableToken.sol";

contract DutchAuction is IDutchAuction, Ownable, ReentrancyGuard {
    IAuctionableToken public token;

    uint256 public initialTokenSupply;

    uint256 public startingPrice;
    uint256 public reservePrice;
    uint256 public discountRate;
    uint256 public clearingPrice;

    uint256 public startTime;
    uint256 public duration;
    uint256 public endTime;

    bool public auctionIsStarted;

    uint256 public maxWeiPerBidder;

    uint256 private totalWeiCommitted;
    mapping(address => uint256) private bidderToWei;
    address[] bidders;

    constructor() Ownable(msg.sender) {
        auctionIsStarted = false;
    }

    function startAuction(IAuctionableToken _token,
    uint256 _initialTokenSupply,
    uint256 _startingPrice,
    uint256 _reservePrice,
    uint256 _duration,  // in minutes
    uint256 _bidderPercentageLimit) external onlyOwner
    {
        // Check if there's another Dutch auction happening
        if (isAuctioning()) {
          revert AuctionIsStarted();
        }

        token = _token;

        if (_startingPrice < _reservePrice) {
            revert InvalidPrices(_startingPrice, _reservePrice);
        }

        initialTokenSupply = _initialTokenSupply;
        // Minting the initial token supply to the DutchAuction contract
        token.operatorMint(initialTokenSupply);
        
        startTime = block.timestamp;
        duration = _duration;
        endTime = startTime + duration * 60;

        startingPrice = _startingPrice;
        reservePrice = _reservePrice;
        discountRate = (_startingPrice - _reservePrice) / duration; // Wei per minute
        clearingPrice = _reservePrice;

        auctionIsStarted = true;

        maxWeiPerBidder = _initialTokenSupply * _bidderPercentageLimit / 100 * reservePrice;

        emit StartAuction(
            address(token), 
            _initialTokenSupply, 
            _startingPrice, 
            _reservePrice, 
            _duration, 
            _bidderPercentageLimit
        );
    }

    // this function is vulnerable to re-entrancy attack, added `nonReentrant` fix
    // Bidder commits ether
    function bid() external payable nonReentrant {
        uint256 committedAmount = _validateBid(msg.sender, msg.value);

        if (bidderToWei[msg.sender] == 0) {
            bidders.push(msg.sender);
        }
        bidderToWei[msg.sender] += committedAmount;
        totalWeiCommitted += committedAmount;

        if (getCurrentTokenSupply() == 0) {
            endTime = block.timestamp;
            clearingPrice = getCurrentPrice();
            emit SoldOut(clearingPrice);
        }

        emit Bid(msg.sender, msg.value);
    }

    function _validateBid(address bidder, uint256 committedAmount) internal returns (uint256 actualCommittedAmount) {
        if (!isAuctioning()) {
            revert AuctionIsInactive();
        }

        if (committedAmount == 0) {
            revert ZeroCommitted();
        }

        // A bidder's total commitment must be smaller than maxWeiPerBidder.
        if (bidderToWei[bidder] >= maxWeiPerBidder) {
            revert BidLimitReached();
        }

        // If the bid makes the bidder's total commitment larger than maxWeiPerBidder, or
        // if the bid causes totalNumberOfTokensCommitted to exceed initial token supply,
        // must refund the exceeded amount
        uint256 maxComAmt1 = maxWeiPerBidder - bidderToWei[bidder];
        uint256 maxComAmt2 = initialTokenSupply * getCurrentPrice() - totalWeiCommitted;
        uint256 maxComAmt = maxComAmt1 < maxComAmt2 ? maxComAmt1 : maxComAmt2;
        if (committedAmount > maxComAmt) {
            uint256 refundAmt = committedAmount - maxComAmt;
            committedAmount = maxComAmt;
            _refund(msg.sender, refundAmt);
        }

        return committedAmount;
    }

    function clearAuction() external onlyOwner {
        // Check if auction has started and ended
        if (!auctionIsStarted) {
          revert AuctionIsNotStarted();
        }

        if (block.timestamp <= endTime && getCurrentTokenSupply() > 0) {
            revert AuctionIsNotEnded();
        }

        // Distribute tokens to successful bidders
        for (uint256 i = 0; i < bidders.length; i++) {
            address bidder = bidders[i];
            token.transfer(bidder, bidderToWei[bidder] / clearingPrice);
            delete bidderToWei[bidder];
        }

        uint256 totalNumberOfTokensCommitted = totalWeiCommitted / clearingPrice;
        if (totalNumberOfTokensCommitted < initialTokenSupply) {
            // Burn the remaining tokens
            token.burn(initialTokenSupply - totalNumberOfTokensCommitted);
        }

        // Reset
        _resetTracking();

        // Close the auction
        auctionIsStarted = false;

        emit AuctionSettled();
    }

    function _resetTracking() internal {
        delete bidders;
    }

    function withdraw() external {
        // Can only withdraw when auction has started and ended for at least 10 mins
        if (!auctionIsStarted) {
          revert AuctionIsNotStarted();
        }

        if (block.timestamp < endTime + 10 * 60) {
          uint256 timeRemaining = endTime + 10 * 60 - block.timestamp;
          revert NotWithdrawableYet(timeRemaining);
        }

        uint256 tokensWon = bidderToWei[msg.sender];
        require(tokensWon > 0, "No token to withdraw.");
        delete bidderToWei[msg.sender];
        token.transfer(msg.sender, tokensWon);

        emit Withdraw(msg.sender, tokensWon);
    }

    // Phil: no need to check amount=0 for internal function -> save gas.
    function _refund(address _to, uint256 amount) internal {
        require(_to != address(0), "Transfer to zero address");
        // Call returns a boolean value indicating success or failure.
        (bool sent, ) = payable(_to).call{ value: amount }("");
        require(sent, "ETH transfer failed");
    }

    function isAuctioning() view public returns (bool) {
        return auctionIsStarted && block.timestamp <= endTime && getCurrentTokenSupply() > 0;
    }

    function getCurrentTokenSupply() view public returns(uint256) {
        uint256 vestedSupply = totalWeiCommitted / getCurrentPrice();
        if (vestedSupply >= initialTokenSupply){
            return 0;
        }
        return initialTokenSupply - vestedSupply;
    }

    function getRemainingAllowance() view public returns(uint256) {
        return maxWeiPerBidder - bidderToWei[msg.sender];
    }

    function getCurrentPrice() view public returns (uint256) {
        if (block.timestamp > startTime + duration * 60) {
            return reservePrice;
        }
        return startingPrice - discountRate * ((block.timestamp - startTime) / 60);
    }
}
