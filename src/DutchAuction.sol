// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TulipToken} from "./TulipToken.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DutchAuction is Ownable {
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
    struct Commitment {
        address bidder;
        uint256 amount;
        uint256 timeCommitted;
        uint256 timeBidded;
    }
    Commitment[] private commitments;
    mapping(address => uint256) private bidderToWei;


    constructor() Ownable(msg.sender) {
        auctionIsStarted = false;
    }

    function startAuction(TulipToken _token,
    uint256 _initialTokenSupply,
    uint256 _startingPrice,
    uint256 _reservePrice,
    uint256 _duration,  // in minutes
    uint256 _bidderPercentageLimit) external onlyOwner
    {
        // Check if there's another Dutch auction happening
        require(!auctionIsStarted, "Another Dutch auction is happening. Please wait...");

        token = _token;

        require(_token.totalSupply() + _initialTokenSupply <= _token.maxSupply(), 
        "The number of tokens minted exceeds the maximum possible supply!");
        initialTokenSupply = _initialTokenSupply;
        
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

        // Minting the initial token supply to the DutchAuction contract
        _token.operatorMint(initialTokenSupply);
    }

    // Bidder commits ether
    function bid() external payable {
        bidAtTimestamp(msg.sender, msg.value, block.timestamp);
    }

    function bidAtPrice(uint256 desiredPrice) external payable {
        require(desiredPrice <= getPrice(), 
        string(abi.encodePacked("Sorry, you have missed the chance to bid at ", 
        Strings.toString(desiredPrice), ".")));

        uint256 timeCommitted = getBlockTimestampAtPrice(desiredPrice);
        bidAtTimestamp(msg.sender, msg.value, timeCommitted);
    }

    // Bidder commits ether
    function bidAtTimestamp(address _bidder, uint256 _amount, uint256 _timeCommitted) internal {
        uint256 committedAmount = validateBid(_bidder, _amount);

        // Store the commitments (bidder, amount, timeCommitted, timeBidded), and the total commitment per bidder
        Commitment memory newCommitment = Commitment(_bidder, committedAmount, _timeCommitted, block.timestamp);
        insertSorted(newCommitment);
        bidderToWei[_bidder] = bidderToWei[_bidder] + committedAmount;

        if (getCurrentTokenSupply() == 0) {
            actualEndTime = block.timestamp;
            clearingPrice = getPrice();
        }
    }

    function validateBid(address bidder, uint256 committedAmount) internal returns (uint256 actualCommittedAmount) {
        require(committedAmount > 0, "No amount of Wei has been committed.");

        // Can only bid if the auction is still happening, else, refund
        require(isAuctioning(), "No auction happening at the moment. Please wait for the next auction.");

        // A bidder's total commitment must be smaller than maxWeiPerBidder.
        require(bidderToWei[bidder] < maxWeiPerBidder, "Already reach the maximum total Wei committed.");
        // If the bid makes the bidder's total commitment larger than maxWeiPerBidder, must refund the exceeded amount
        uint256 maxComAmt = maxWeiPerBidder - bidderToWei[bidder];
        if (committedAmount > maxComAmt) {
            uint256 refundAmt = committedAmount - maxComAmt;
            committedAmount = maxComAmt;
            refund(msg.sender, refundAmt);
        }

        return committedAmount;
    }

    function insertSorted(Commitment memory newCommitment) internal {
        // Binary search to find the index to insert newCommitment
        uint256 indexToInsert = binarySearchCommitments(newCommitment, compareCommitmentsByTimeCommAndBid);
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
    function binarySearchCommitments(Commitment memory newCommitment, 
    function(Commitment memory, Commitment storage) internal view returns(int256) comparator)
    internal view returns(uint256) {
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
    function compareCommitmentsByTimeCommAndBid(Commitment memory commitment1, Commitment storage commitment2) private view returns (int256) {
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

    // Compare commitments by timeCommitted
    function compareCommitmentsByTimeComm(Commitment memory commitment1, Commitment storage commitment2) private view returns (int256) {
        if (commitment1.timeCommitted < commitment2.timeCommitted) {
            return -1;
        } else if (commitment1.timeCommitted > commitment2.timeCommitted) {
            return 1;
        } else {
            return 0;
        }
    }

    // Distribute tokens, refund (partially) exceeding bid/burn remaining tokens
    function settleAuction() external onlyOwner {
        // Check if auction has started and ended
        require(auctionIsStarted, "No auction has started.");
        require(block.timestamp > expectedEndTime || getCurrentTokenSupply() == 0, "Auction has not ended.");

        // Distribute tokens to successful bidders
        // If we got bidAtPrice function, need to sort commitments by price then priority
        uint256 numberOfCommitments = commitments.length;
        for (uint256 i = 0; i < numberOfCommitments - 1; i++) {
            token.transfer(commitments[i].bidder, commitments[i].amount / clearingPrice);
        }

        uint256 totalWeiCommitted = getCurrentTotalWeiCommitted();
        uint256 totalNumberOfTokensCommitted = totalWeiCommitted / clearingPrice;
        if (totalNumberOfTokensCommitted >= initialTokenSupply){
            uint256 unsatisfiedCommitmentAmount = totalWeiCommitted - initialTokenSupply * clearingPrice;
            uint256 satisfiedCommitmentAmount = commitments[numberOfCommitments - 1].amount - unsatisfiedCommitmentAmount;

            // Refund the unsatisfied commitment amount
            if (unsatisfiedCommitmentAmount > 0){
                refund(commitments[numberOfCommitments - 1].bidder, unsatisfiedCommitmentAmount);
            }

            // Transfer the satisfied number of tokens
            token.transfer(commitments[numberOfCommitments - 1].bidder, satisfiedCommitmentAmount / clearingPrice);
        }
        else {
            // Burn the remaining tokens
            token.burn(initialTokenSupply - totalNumberOfTokensCommitted);
        }

        // Close the auction
        auctionIsStarted = false;
    }

    function withdraw() external {
        // Can only withdraw when auction has started and ended for at least 10 mins
        require(auctionIsStarted, "No auction has started.");
        require(block.timestamp > expectedEndTime + 10 * 60 || 
        (getCurrentTokenSupply() == 0 && block.timestamp > actualEndTime + 10 * 60 ), 
        "Auction has not ended.");

        // Todo
        // token.transfer(msg.sender, winningAmount);
    }

    function refund(address _to, uint256 amount) private {
        // Call returns a boolean value indicating success or failure.
        require(amount > 0, "No amount to refund");
        (bool sent, bytes memory data) = _to.call{value: amount}("");
        require(sent, "Failed to refund Ether");
    }

    function isAuctioning() view public returns (bool) {
        if (auctionIsStarted && block.timestamp <= expectedEndTime && getCurrentTokenSupply() > 0){
            return true;
        }
        return false;
    }

    function getCurrentTokenSupply() view public returns(uint256) {
        uint256 soldNumOfToken = getCurrentTotalWeiCommitted() / getPrice();
        if (soldNumOfToken >= initialTokenSupply){
            return 0;
        }
        return initialTokenSupply - soldNumOfToken;
    }

    function getCurrentTotalWeiCommitted() view internal returns(uint256) {
        return getTotalWeiCommitted(block.timestamp);
    }

    function getTotalWeiCommitted(uint256 blockTimestamp) view internal returns(uint256) {
        Commitment memory newCommitment = Commitment(address(123), 0, blockTimestamp, blockTimestamp);
        uint256 rightBound = binarySearchCommitments(newCommitment, compareCommitmentsByTimeComm);
        uint256 totalWeiCommitted = 0;
        for (uint256 i = 0; i < rightBound; i++) {
            totalWeiCommitted += commitments[i].amount;
        }
        return totalWeiCommitted;
    }
    
    function getBlockTimestampAtPrice(uint256 price) view public returns (uint256) {
        require((startingPrice - price) % discountRate == 0, "Price must be in the appropriate increment.");
        require(price >= reservePrice && price <= startingPrice, "Price not within range.");
        return startTime + (startingPrice - price) / discountRate * 60;
    }

    function getPrice() view public returns (uint256) {
        if (block.timestamp > expectedEndTime) {
            return reservePrice;
        }
        return startingPrice - discountRate * (block.timestamp - startTime) / 60;
    }
}