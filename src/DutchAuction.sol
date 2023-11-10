// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "src/lib/WadMath.sol";
import "src/lib/Errors.sol";
import {ReentrancyGuard} from "src/lib/ReentrancyGuard.sol";

import {IDutchAuction} from "src/interfaces/IDutchAuction.sol";
import {IAuctionableToken} from "src/interfaces/IAuctionableToken.sol";

contract DutchAuction is IDutchAuction, Ownable, ReentrancyGuard {
    IAuctionableToken public token;

    uint256 public initialTokenSupply;

    uint256 public startPrice;
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
    }

    function operatorWithdraw() external onlyOwner {
      payable(owner()).call{ value: address(this).balance }("");
    }

    function startAuction(IAuctionableToken _token,
    uint256 _initialTokenSupply,
    uint256 _startPrice,
    uint256 _reservePrice,
    uint256 _duration,  // in minutes
    uint256 _bidderPercentageLimit) external onlyOwner
    {
        // Check if there's another Dutch auction happening
        if (isAuctioning()) {
          revert AuctionIsStarted();
        }

        token = _token;

        if (_startPrice < _reservePrice) {
            revert InvalidPrices(_startPrice, _reservePrice);
        }

        initialTokenSupply = _initialTokenSupply;
        // Minting the initial token supply to the DutchAuction contract
        token.operatorMint(initialTokenSupply);
        
        startTime = block.timestamp;
        duration = _duration;
        endTime = startTime + duration * 60;

        startPrice = _startPrice;
        reservePrice = _reservePrice;
        discountRate = (_startPrice - _reservePrice) / (duration - 1); // Wei per minute
        clearingPrice = _reservePrice;

        auctionIsStarted = true;

        maxWeiPerBidder = WadMath.mulWadDown(_initialTokenSupply, reservePrice) * _bidderPercentageLimit / 100;

        emit StartAuction(
            address(token), 
            _initialTokenSupply, 
            _startPrice, 
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

        if (getCurrentTokenSupply() <= 1e3) {
            endTime = block.timestamp;
            clearingPrice = getCurrentPrice();
            emit SoldOut(clearingPrice);
        }

        emit Bid(msg.sender, msg.value);
    }

    function _validateBid(address _bidder, uint256 _committedAmount) internal returns (uint256 actualCommittedAmount) {
        if (!isAuctioning()) {
            revert AuctionIsInactive();
        }

        uint256 committedAmount = _committedAmount;
        if (committedAmount == 0) {
            revert ZeroCommitted();
        }

        // A bidder's total commitment must be smaller than maxWeiPerBidder.
        if (bidderToWei[_bidder] >= maxWeiPerBidder) {
            revert BidLimitReached();
        }

        // If the bid makes the bidder's total commitment larger than maxWeiPerBidder, or
        // if the bid causes totalNumberOfTokensCommitted to exceed initial token supply,
        // must refund the exceeded amount
        uint256 maxComAmt1 = maxWeiPerBidder - bidderToWei[_bidder];
        uint256 maxComAmt2 = WadMath.mulWadDown(initialTokenSupply, getCurrentPrice()) - totalWeiCommitted;
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

        if (block.timestamp <= endTime && getCurrentTokenSupply() > 1e3) {
            revert AuctionIsNotEnded();
        }

        // Distribute tokens to successful bidders
        for (uint256 i = 0; i < bidders.length; i++) {
            address bidder = bidders[i];
            uint256 tokenAmount = WadMath.divWadDown(bidderToWei[bidder], clearingPrice);
            delete bidderToWei[bidder];
            token.transfer(bidder, tokenAmount);
        }

        uint256 totalNumberOfTokensCommitted = WadMath.divWadDown(totalWeiCommitted, clearingPrice);
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

        uint256 tokensWon = WadMath.divWadDown(bidderToWei[msg.sender], clearingPrice);
        require(tokensWon > 0, "No token to withdraw.");
        delete bidderToWei[msg.sender];
        token.transfer(msg.sender, tokensWon);

        emit Withdraw(msg.sender, tokensWon);
    }

    // Phil: no need to check amount=0 for internal function -> save gas.
    function _refund(address _to, uint256 _amount) internal {
        require(_to != address(0), "Transfer to zero address");
        // Call returns a boolean value indicating success or failure.
        (bool sent, ) = payable(_to).call{ value: _amount }("");
        require(sent, "ETH transfer failed");
    }

    function isAuctioning() view public returns (bool) {
        return auctionIsStarted && block.timestamp <= endTime && getCurrentTokenSupply() > 1e3;
    }

    function getCurrentTokenSupply() view public returns(uint256) {
        uint256 vestedSupply = WadMath.divWadDown(totalWeiCommitted, getCurrentPrice());
        if (vestedSupply >= initialTokenSupply){
            return 0;
        }
        return initialTokenSupply - vestedSupply;
    }

    function getRemainingAllowance(address _caller) view public returns(uint256) {
        return maxWeiPerBidder - bidderToWei[_caller];
    }

    function getCurrentPrice() view public returns (uint256) {
        if (block.timestamp > startTime + duration * 60) {
            return reservePrice;
        }
        return startPrice - discountRate * ((block.timestamp - startTime) / 60);
    }
}
