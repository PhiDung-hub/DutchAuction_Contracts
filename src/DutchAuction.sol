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
    uint256 private totalWeiCommitted;
    struct commitment {
        address bidder;
        uint256 amount;
        uint256 price;
    }
    commitment[] private commitments;
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
        uint256 committedAmount = validateBid(msg.sender, msg.value);
        
        uint256 currentPrice = getPrice();

        // Store the commitments (bidder, amount, price), and the total commitment per bidder
        commitments.push(commitment(msg.sender, committedAmount, currentPrice));
        bidderToWei[msg.sender] = bidderToWei[msg.sender] + committedAmount;
        totalWeiCommitted += committedAmount;

        uint256 desiredNumOfTokens = committedAmount / currentPrice;
        if(desiredNumOfTokens >= getCurrentTokenSupplyAtPrice(currentPrice)) {
            actualEndTime = block.timestamp;
            clearingPrice = currentPrice;
        }
    }

    // function bidAtPrice(uint256 desiredPrice) external payable {
    //     uint256 committedAmount = validateBid(msg.sender, msg.value);

    //     require(startingPrice >= desiredPrice >= reservePrice, "Desired price not within starting price and reserve price.");
    //     require(desiredPrice % discountRate == 0, 
    //     string(abi.encodePacked("Desired price must be in the unit of the discount rate: ",
    //     Strings.toString(discountRate), ".")));

    //     uint256 currentPrice = getPrice();
    //     require(desiredPrice < currentPrice, 
    //     string(abi.encodePacked("Sorry, you have missed the chance to bid at ", 
    //     Strings.toString(desiredPrice), ".")));
        
    //     uint256 desiredNumOfTokens = committedAmount / desiredPrice;
    //     commitments.push(commitment(msg.sender, committedAmount, currentPrice));
    //     bidderToWei[msg.sender] = bidderToWei[msg.sender] + committedAmount;
    //     totalWeiCommitted += committedAmount;
    // }

    function validateBid(address bidder, uint256 committedAmount) private returns (uint256 actualCommittedAmount) {
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
        uint256 currentPrice = getPrice();
        if (totalWeiCommitted / currentPrice >= initialTokenSupply){
            return 0;
        }
        return initialTokenSupply - totalWeiCommitted / currentPrice;
    }

    function getCurrentTokenSupplyAtPrice(uint256 _currentPrice) view public returns(uint256) {
        if (totalWeiCommitted / _currentPrice >= initialTokenSupply){
            return 0;
        }
        return initialTokenSupply - totalWeiCommitted / _currentPrice;
    }

    function getPrice() view public returns (uint256) {
        if (block.timestamp > expectedEndTime) {
            return reservePrice;
        }
        return startingPrice - discountRate * (block.timestamp - startTime) / 60;
    }
}