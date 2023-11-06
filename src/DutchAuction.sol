// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {TulipToken} from "./TulipToken.sol";
import "src/lib/Errors.sol";
import {ReentrancyGuard} from "src/lib/ReentrancyGuard.sol";
import {IDutchAuction} from "src/interfaces/IDutchAuction.sol";
import {Commitment} from "src/lib/Structs.sol";

contract DutchAuction is IDutchAuction, Ownable, ReentrancyGuard {
    TulipToken public token;

    uint256 public initialTokenSupply;

    uint256 public startingPrice;
    uint256 public reservePrice;
    uint256 public discountRate;
    uint256 public clearingPrice;

    uint256 public startTime;
    uint256 public duration;
    uint256 public expectedEndTime;
    uint256 public actualEndTime;

    bool public auctionIsStarted;

    uint256 public bidderPercentageLimit;
    uint256 public maxWeiPerBidder;

    uint256 private totalWeiCommitted;
    Commitment[] private commitments;
    mapping(address => uint256) private bidderToWei;
    address[] bidders;

    constructor() Ownable(msg.sender) {
        auctionIsStarted = false;
    }

    function startAuction(address _tokenAddress,
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

        token = TulipToken(_tokenAddress);

        // @Phil: already checked at operatorMint
        // require(_token.totalSupply() + _initialTokenSupply <= _token.maxSupply(), 
        // "The number of tokens minted exceeds the maximum possible supply!");

        initialTokenSupply = _initialTokenSupply;
        // Minting the initial token supply to the DutchAuction contract
        token.operatorMint(initialTokenSupply);
        
        startTime = block.timestamp;
        duration = _duration;
        expectedEndTime = startTime + duration * 60;
        actualEndTime = expectedEndTime;

        startingPrice = _startingPrice;
        reservePrice = _reservePrice;
        discountRate = (_startingPrice - _reservePrice) / duration; // Wei per minute
        clearingPrice = _reservePrice;

        auctionIsStarted = true;

        bidderPercentageLimit = _bidderPercentageLimit;
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

        // If the bid causes totalNumberOfTokensCommitted to exceed initial token supply, need to do refund
        uint256 currentPrice = getCurrentPrice();
        if (totalWeiCommitted + committedAmount > initialTokenSupply * currentPrice) {
            uint256 unsatisfiedCommitmentAmount = totalWeiCommitted + committedAmount - initialTokenSupply * currentPrice;
            committedAmount -= unsatisfiedCommitmentAmount;

            // Refund the unsatisfied commitment amount
            _refund(msg.sender, unsatisfiedCommitmentAmount);
        }

        // Store the commitments (bidder, amount), and the total commitment per bidder
        Commitment memory newCommitment = Commitment(msg.sender, committedAmount);
        commitments.push(newCommitment);
        if (bidderToWei[msg.sender] == 0) {
            bidders.push(msg.sender);
        }
        bidderToWei[msg.sender] += committedAmount;
        totalWeiCommitted += committedAmount;

        if (getCurrentTokenSupply() == 0) {
            actualEndTime = block.timestamp;
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

        // If the bid makes the bidder's total commitment larger than maxWeiPerBidder, must refund the exceeded amount
        uint256 maxComAmt = maxWeiPerBidder - bidderToWei[bidder];
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

        if (block.timestamp <= expectedEndTime && getCurrentTokenSupply() > 0) {
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
        delete commitments;
        delete bidders;
    }

    function withdraw() external {
        // Can only withdraw when auction has started and ended for at least 10 mins
        if (!auctionIsStarted) {
          revert AuctionIsNotStarted();
        }

        // @Phil: actualEndTime is enough to check, consider removing expectedEndTime.
        if (block.timestamp < actualEndTime + 10 * 60) {
          uint256 timeRemaining = actualEndTime + 10 * 60 - block.timestamp;
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
        return auctionIsStarted && block.timestamp <= expectedEndTime && getCurrentTokenSupply() > 0;
    }

    function getCurrentTokenSupply() view public returns(uint256) {
        uint256 soldNumOfToken = totalWeiCommitted / getCurrentPrice();
        if (soldNumOfToken >= initialTokenSupply){
            return 0;
        }
        return initialTokenSupply - soldNumOfToken;
    }

    function getCurrentPrice() view public returns (uint256) {
        if (block.timestamp > expectedEndTime) {
            return reservePrice;
        }
        return startingPrice - discountRate * (block.timestamp - startTime) / 60;
    }
}
