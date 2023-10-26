// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TulipToken} from "./TulipToken.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DutchAuction is Ownable {
    // Auction's properties
    TulipToken public token;

    uint256 public currentTokenSupply;
    uint256 public initialTokenSupply;

    uint256 public startingPrice;
    uint256 public reservePrice;
    uint256 public discountRate;

    uint256 public startTime;
    uint256 public duration;
    uint256 public expectedEndTime;
    uint256 public actualEndTime;

    uint256 public bidLimit; // Percentage point of total initial supply that a single bidder can bid

    bool public auctionIsStarted = false;

    address[] private bidders;
    mapping(address => uint256) bidderToAmount; // amount of tokens that bidder bids for
    mapping(address => uint256) bidderToEther; // amount of Ether that bidder has committed


    constructor(address initialOwner) Ownable(initialOwner) {}

    function startAuction(TulipToken _token,
    uint256 _initialTokenSupply,
    uint256 _startingPrice,
    uint256 _reservePrice,
    uint256 _duration,
    uint256 _bidLimit) public
    {
        // Check if there's another Dutch auction happening
        require(!auctionIsStarted, "Another Dutch auction is happening. Please wait...");

        token = _token;

        require(_token.totalSupply() + _initialTokenSupply <= _token.maxSupply(), 
        "The number of tokens minted exceeds the maximum possible supply!");
        currentTokenSupply = _initialTokenSupply;
        initialTokenSupply = _initialTokenSupply;

        startingPrice = _startingPrice;
        reservePrice = _reservePrice;
        discountRate = (_startingPrice - _reservePrice) / _duration;
        
        startTime = block.timestamp;
        duration = _duration;
        expectedEndTime = startTime + duration;

        bidLimit = _bidLimit;

        auctionIsStarted = true;

        // Minting the initial token supply to the DutchAuction contract
        _token.operatorMint(initialTokenSupply);
    }

    function getPrice() view public returns (uint256) {
        return startingPrice - discountRate * (block.timestamp - startTime);
    }

    function isAuctioning() view private returns (bool) {
        if (auctionIsStarted && block.timestamp <= expectedEndTime && currentTokenSupply > 0){
            return true;
        }
        return false;
    }

    function bid(uint256 amount) external payable {
        // Check if the auction is still happening
        require(isAuctioning(), "No auction happening at the moment. Please wait for the next auction.");

        // Check if currentTokenSupply >= amount
        require(amount <= currentTokenSupply, "Not enough tokens left to service the bid.");

        // Check if bid exceeds that person's threshold
        require(amount + bidderToAmount[msg.sender] <= bidLimit * initialTokenSupply,
        string(abi.encodePacked("Bidder cannot bid a total more than", 
        Strings.toString(bidLimit), 
        "% of the total number of tokens offered.")));
        
        // Bidder to transfer the amount they have to commit for the bid
        uint256 requiredCost = amount * getPrice();
        require(msg.value >= requiredCost, "Bidder needs to commit enough ether for their bid!");

        bidders.push(msg.sender);
        bidderToAmount[msg.sender] += amount;
        bidderToEther[msg.sender] += msg.value;
        currentTokenSupply -= amount;

        if (currentTokenSupply == 0){
            actualEndTime = block.timestamp;
        }
    }

    // block or price?
    // function bidAtPrice(uint256 amount, uint256 price) external payable {
    //     // // Check if currentTokenSupply >= amount
    //     // require(amount <= currentTokenSupply, "Not enough tokens left to service the bid.");
        
    //     // Bidder to transfer the amount they have to commit for the bid
    //     uint256 requiredCost = amount * getPrice();
    //     require(msg.value >= requiredCost, "Bidder needs to commit enough ether for their bid!");
    //     bidderToAmount[msg.sender] += amount;
    //     bidderToEther[msg.sender] += msg.value;
    //     currentTokenSupply -= amount;
    // }

    // Distribute tokens, refund 
    function clearAuction() external onlyOwner {
        // Check if auction has started and ended
        require(auctionIsStarted, "No auction has started.");
        require(block.timestamp > expectedEndTime || currentTokenSupply == 0, "Auction has not ended.");

        // Distribute tokens to successful bidders
        for (uint256 i; i < bidders.length; i++) {
            uint256 winningAmount = bidderToAmount[bidders[i]];
            bidderToAmount[bidders[i]] = 0;
            token.transfer(bidders[i], winningAmount);
        }

        // Burn the remaining tokens
        token.burn(currentTokenSupply);
        currentTokenSupply = 0;

        // Refund ether to unsuccessful bidders

        // Close the auction
        auctionIsStarted = false;
    }

    function withdraw() public {
        // Check if auction has started and ended for at least 10 mins
        require(auctionIsStarted, "No auction has started.");
        require(block.timestamp > expectedEndTime + 10 * 60 || 
        (currentTokenSupply == 0 && block.timestamp > actualEndTime + 10 * 60 ), 
        "Auction has not ended.");

        uint256 winningAmount = bidderToAmount[msg.sender];
        require(winningAmount > 0, "You have nothing to withdraw.");
        bidderToAmount[msg.sender] = 0;
        token.transfer(msg.sender, winningAmount);
    }
}