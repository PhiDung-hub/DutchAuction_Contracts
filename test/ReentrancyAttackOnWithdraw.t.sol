// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ReentrancyAttackOnWithdraw} from "src/ReentrancyAttackOnWithdraw.sol";
import {IDutchAuction} from "src/interfaces/IDutchAuction.sol";
import {DutchAuction} from "src/DutchAuction.sol";
import {IAuctionableToken} from "src/interfaces/IAuctionableToken.sol";
import {TulipToken} from "src/TulipToken.sol";

contract ReentrancyAttackOnWithdrawTest is Test {
    ReentrancyAttackOnWithdraw private attackContract;
    IDutchAuction private dutchAuction;
    IAuctionableToken private token;

    function setUp() public {
        dutchAuction = new DutchAuction();
        token = new TulipToken(1000 ether, address(dutchAuction));
        attackContract = new ReentrancyAttackOnWithdraw(address(dutchAuction));
    }

    function test_Attack_ReentrancyAttackFailed() public {
        uint256 initialTokenSupply = 100 ether;
        uint256 startPrice = 0.02 ether;
        uint256 reservePrice = 0.001 ether;
        dutchAuction.startAuction(token, initialTokenSupply, startPrice, reservePrice, 20, 100000);

        attackContract.bid{value: 1 ether}();

        vm.warp(block.timestamp + 31 * 60);
        vm.expectRevert("ETH transfer failed");
        attackContract.attack();

        assertEq(1 ether, address(dutchAuction).balance);
        assertEq(0, address(attackContract).balance);
    }
}
