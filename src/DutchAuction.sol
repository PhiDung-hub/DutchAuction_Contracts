// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TulipToken} from "./TulipToken.sol";

contract DutchAuction {
    // Auction's properties
    TulipToken public token;

    uint256 public currentTokenSupply;

    uint256 public startingPrice;
    uint256 public reservePrice;
    uint256 private discountRate;

    uint256 public startTime;
    uint256 public duration;
    uint256 private endTime;

    // Auction's states
    enum AuctionState {OPENED, CLOSED}
    AuctionState public currentState;

    mapping(address => uint256) bidderToAmount;
    mapping(address => uint256) bidderToEther;

    function startAuction(TulipToken _token,
    uint256 initialTokenSupply,
    uint256 _startingPrice,
    uint256 _reservePrice,
    uint256 _duration) public
    {
        // Check if there's another Dutch auction happening
        require(currentState == AuctionState.CLOSED,
        "Another Dutch auction is happening. Please wait...");

        token = _token;

        require(_token.totalSupply() + initialTokenSupply <= _token.maxSupply(), 
        "The number of tokens minted exceeds the maximum possible supply!");
        currentTokenSupply = initialTokenSupply;

        startingPrice = _startingPrice;
        reservePrice = _reservePrice;
        discountRate = (_startingPrice - _reservePrice) / _duration;
        
        startTime = block.timestamp;
        duration = _duration;
        endTime = startTime + duration;

        currentState = AuctionState.OPENED;

        // Minting the initial token supply to the DutchAuction contract
        _token.operatorMint(initialTokenSupply);
    }

    function getPrice() view private returns (uint256 price) {
        return startingPrice - discountRate * (block.timestamp - startTime);
    }

    function isAuctioning() view private returns (bool _isAuctioning) {
        if (currentState == AuctionState.OPENED && block.timestamp <= endTime){
            return true;
        }
        return false;
    }

    function bid(uint256 amount) external payable {
        // Check if currentTokenSupply >= amount
        require(amount <= currentTokenSupply, "Not enough tokens left to service the bid.");
        
        // Bidder to transfer the amount they have to commit for the bid
        uint256 cost = amount * getPrice();
        require(msg.value >= cost, "Bidder needs to commit enough ether for their bid!");
        bidderToAmount[msg.sender] += amount;
        bidderToEther[msg.sender] += msg.value;
    }
}