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
    bool public auctionIsSettled;

    uint256 public bidderPercentageLimit;
    uint256 public maxWeiPerBidder;

    Commitment[] private commitments;
    mapping(address => uint256) private bidderToWei;
    address[] bidders;
    mapping(address => uint256) private successfulBidderToTokens;
    address[] successfulBidders;
    mapping(address => uint256) private failedBidderToRefund;
    address[] failedBidders;
    uint256 private toBurn;


    constructor() Ownable(msg.sender) {
        auctionIsStarted = false;
        auctionIsSettled = false;
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
        _token.operatorMint(initialTokenSupply);
        
        startTime = block.timestamp;
        duration = _duration;
        expectedEndTime = startTime + duration * 60;
        actualEndTime = expectedEndTime;

        startingPrice = _startingPrice;
        reservePrice = _reservePrice;
        discountRate = (_startingPrice - _reservePrice) / duration; // Wei per minute
        clearingPrice = _reservePrice;

        auctionIsStarted = true;
        auctionIsSettled = false;

        bidderPercentageLimit = _bidderPercentageLimit;
        maxWeiPerBidder = _initialTokenSupply * _bidderPercentageLimit / 100 * reservePrice;

        emit StartAuction(
            address(_token), 
            _initialTokenSupply, 
            _startingPrice, 
            _reservePrice, 
            _duration, 
            _bidderPercentageLimit
        );
    }

    // Bidder commits ether
    function bid() external payable {
        _bidAtTimestamp(msg.sender, msg.value, block.timestamp);

        emit Bid(msg.sender, msg.value);
    }

    function bidAtPrice(uint256 targetPrice) external payable {
        if (targetPrice > getCurrentPrice()) {
            revert PriceTooHigh();
        }

        uint256 timeCommitted = getBlockTimestampAtPrice(targetPrice);
        _bidAtTimestamp(msg.sender, msg.value, timeCommitted);

        emit BidLimitOrder(msg.sender, msg.value, targetPrice, block.timestamp);
    }

    // @Phil: this function is vulnerable to re-entrancy attack, added `nonReentrant` fix
    // Bidder commits ether at a particular time
    function _bidAtTimestamp(address _bidder, uint256 _amount, uint256 _timeCommitted) internal nonReentrant {
        uint256 committedAmount = _validateBid(_bidder, _amount);

        // Store the commitments (bidder, amount, timeCommitted, timeBidded), and the total commitment per bidder
        Commitment memory newCommitment = Commitment(_bidder, committedAmount, _timeCommitted, block.timestamp);
        _insertSorted(newCommitment);
        if (bidderToWei[_bidder] == 0) {
            bidders.push(_bidder);
        }
        bidderToWei[_bidder] += committedAmount;

        if (getCurrentTokenSupply() == 0) {
            actualEndTime = block.timestamp;
            clearingPrice = getCurrentPrice();
            emit SoldOut(clearingPrice);
        }
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

    function _insertSorted(Commitment memory newCommitment) internal {
        // Binary search to find the index to insert newCommitment
        uint256 indexToInsert = _binarySearchCommitments(newCommitment, _compareCommitmentsByTimeCommAndBid);
        if (commitments.length == indexToInsert) { // insert after the last element
            commitments.push(newCommitment);
            return;
        }

        // Shift elements to the right to make space for the new commitment
        commitments.push(commitments[commitments.length - 1]); // Expand the array by one
        for (uint256 i = commitments.length - 2; i > indexToInsert; i--) {
            commitments[i] = commitments[i - 1];
        }
        commitments[indexToInsert] = newCommitment; // Insert the new commitment
    }

    // Binary search to find the index to insert newCommitment
    function _binarySearchCommitments(
        Commitment memory newCommitment, 
        function(Commitment memory, Commitment storage) internal view returns(int256) comparator
    ) internal view returns(uint256) {
        // If no commitment, or if newCommitment is larger than or equal to the last element
        // Index to insert is commitments.length
        if (commitments.length == 0 || comparator(newCommitment, commitments[commitments.length - 1]) >= 0) {
            return commitments.length;
        }

        uint256 left = 0;
        uint256 right = commitments.length - 1;
        uint256 mid = 0;

        while (left <= right) {
            mid = (left + right) / 2;
            int256 comparison = comparator(newCommitment, commitments[mid]);
            if (comparison < 0) {
                right = mid - 1;
            } else {
                left = mid + 1;
                mid = left;
            }
        }
        return mid;
    }

    // Compare commitments by timeCommitted and timeBidded
    function _compareCommitmentsByTimeCommAndBid(Commitment memory commitment1, Commitment storage commitment2) internal view returns (int256) {
        if (commitment1.timeCommitted < commitment2.timeCommitted) {
            return -1;
        } else if (commitment1.timeCommitted > commitment2.timeCommitted) {
            return 1;
        } else {
            // If timeCommitted are equal, compare based on timeBidded
            if (commitment1.timeBidded < commitment2.timeBidded) {
                return -1;
            } else if (commitment1.timeBidded > commitment2.timeBidded) {
                return 1;
            } else {
                // If timeCommitted and timeBidded are equal, the commitments are equal
                return 0;
            }
        }
    }

    // Tally tokens and refunds per bidder, and tally remaining tokens to burn
    function _settleAuction() internal {
        // Check if auction has started and ended
        if (!auctionIsStarted) {
          revert AuctionIsNotStarted();
        }

        if (block.timestamp <= expectedEndTime && getCurrentTokenSupply() > 0) {
            revert AuctionIsNotEnded();
        }

        // @Phil: should revert.
        if (auctionIsSettled) {
            return;
        }

        // Tally up tokens per successful bidder
        uint256 numberOfCommitments = commitments.length;
        uint256 i = 0;
        uint256 totalNumTokensSold = 0;
        while (i < numberOfCommitments && totalNumTokensSold < initialTokenSupply) {
            uint256 numTokensSold = commitments[i].amount / clearingPrice;
            // If the commitment exceeds initialTokenSupply, partially fulfill it and refund remaining
            if (totalNumTokensSold + numTokensSold > initialTokenSupply) {
                uint256 numTokensRefund = totalNumTokensSold + numTokensSold - initialTokenSupply;
                numTokensSold = initialTokenSupply - totalNumTokensSold;
                if (failedBidderToRefund[commitments[i].bidder] == 0) {
                    failedBidders.push(commitments[i].bidder);
                }
                failedBidderToRefund[commitments[i].bidder] += (numTokensRefund * clearingPrice);
            }
            totalNumTokensSold += numTokensSold;
            if (successfulBidderToTokens[commitments[i].bidder] == 0) {
                successfulBidders.push(commitments[i].bidder);
            }
            successfulBidderToTokens[commitments[i].bidder] += numTokensSold;
            i += 1;
        }

        // Tally up refund per unfulfilled bidder
        if (i < numberOfCommitments && totalNumTokensSold == initialTokenSupply) {
            for (uint256 j = i; j < numberOfCommitments; j++) {
                if (failedBidderToRefund[commitments[j].bidder] == 0) {
                    failedBidders.push(commitments[j].bidder);
                }
                failedBidderToRefund[commitments[j].bidder] += commitments[j].amount;
            }
        }

        // Tally up the remaining tokens to burn
        if (i >= numberOfCommitments && totalNumTokensSold < initialTokenSupply) {
            toBurn = initialTokenSupply - totalNumTokensSold;
        }

        // Settled
        auctionIsSettled = true;
    }

    // Distribute tokens, refund (partially) exceeding bid/burn remaining tokens, and reset
    function clearAuction() external onlyOwner {
        if (!auctionIsSettled) {
            _settleAuction();
        }

        // Distribute tokens to successful bidders
        for (uint256 i = 0; i < successfulBidders.length; i++) {
            address bidder = successfulBidders[i];
            if (successfulBidderToTokens[bidder] > 0) {
                token.transfer(bidder, successfulBidderToTokens[bidder]);
                delete successfulBidderToTokens[bidder];
            }
        }
        delete successfulBidders;

        // Refund failed bidders
        for (uint256 i = 0; i < failedBidders.length; i++) {
            address bidder = failedBidders[i];
            if (failedBidderToRefund[bidder] > 0) {
                _refund(bidder, failedBidderToRefund[bidder]);
                delete failedBidderToRefund[bidder];
            }
        }
        delete failedBidders;

        // Burn the remaining tokens
        if (toBurn > 0) {
            token.burn(toBurn);
        }
        toBurn = 0;

        // Reset
        _resetTracking();

        // Close the auction
        auctionIsStarted = false;
        auctionIsSettled = false;

        emit AuctionSettled();
    }

    function _resetTracking() internal {
        delete commitments;

        for (uint256 i = 0; i < bidders.length; i++) {
            address bidder = bidders[i];
            delete bidderToWei[bidder];
        }
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

        // @Phil: This is really expensive for normal bidder, consider being done by operator only.
        //
        // Settle the auction if haven't
        if (!auctionIsSettled) {
            _settleAuction();
        }

        uint256 tokensWon = successfulBidderToTokens[msg.sender];
        require(tokensWon > 0, "No token to withdraw.");
        delete successfulBidderToTokens[msg.sender];
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
        uint256 soldNumOfToken = _getCurrentTotalWeiCommitted() / getCurrentPrice();
        if (soldNumOfToken >= initialTokenSupply){
            return 0;
        }
        return initialTokenSupply - soldNumOfToken;
    }

    function _getCurrentTotalWeiCommitted() view internal returns(uint256) {
        return _getTotalWeiCommitted(block.timestamp);
    }

    function _getTotalWeiCommitted(uint256 blockTimestamp) view internal returns(uint256) {
        Commitment memory newCommitment = Commitment(address(123), 0, blockTimestamp, blockTimestamp);
        uint256 rightBound = _binarySearchCommitments(newCommitment, _compareCommitmentsByTimeComm);
        uint256 totalWeiCommitted = 0;
        for (uint256 i = 0; i < rightBound; i++) {
            totalWeiCommitted += commitments[i].amount;
        }
        return totalWeiCommitted;
    }

    // Compare commitments by timeCommitted
    function _compareCommitmentsByTimeComm(Commitment memory commitment1, Commitment storage commitment2) internal view returns (int256) {
        if (commitment1.timeCommitted < commitment2.timeCommitted) {
            return -1;
        } else if (commitment1.timeCommitted > commitment2.timeCommitted) {
            return 1;
        } else {
            return 0;
        }
    }
    
    function getBlockTimestampAtPrice(uint256 price) view public returns (uint256) {
        require(price >= reservePrice && price <= startingPrice, "Price not within range.");
        require((startingPrice - price) % discountRate == 0, "Price must be in the appropriate increment.");
        return startTime + (startingPrice - price) / discountRate * 60;
    }

    function getCurrentPrice() view public returns (uint256) {
        if (block.timestamp > expectedEndTime) {
            return reservePrice;
        }
        return startingPrice - discountRate * (block.timestamp - startTime) / 60;
    }
}
