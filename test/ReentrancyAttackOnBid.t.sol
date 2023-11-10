// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ReentrancyAttackOnBid} from "src/ReentrancyAttackOnBid.sol";
import {IDutchAuction} from "src/interfaces/IDutchAuction.sol";
import {DutchAuction} from "src/DutchAuction.sol";
import {IAuctionableToken} from "src/interfaces/IAuctionableToken.sol";
import {TulipToken} from "src/TulipToken.sol";

contract ReentrancyAttackOnBidTest is Test {
    ReentrancyAttackOnBid private attackContract;
    IDutchAuction private dutchAuction;
    IAuctionableToken private token;

    function setUp() public {
        dutchAuction = new DutchAuction();
        token = new TulipToken(1000 ether, address(dutchAuction));
        attackContract = new ReentrancyAttackOnBid(address(dutchAuction));
    }

    function test_Attack_ReentrancyAttackFailed() public {
        uint256 initialTokenSupply = 100 ether;
        uint256 startPrice = 0.02 ether;
        uint256 reservePrice = 0.001 ether;
        dutchAuction.startAuction(token, initialTokenSupply, startPrice, reservePrice, 20, 100000);

        uint256 bidAmt1 = 1 ether;
        dutchAuction.bid{value: bidAmt1}();

        uint256 attackContractInitBal = 10 ether;
        vm.deal(address(attackContract), attackContractInitBal);
        vm.expectRevert("ETH transfer failed");
        attackContract.attack{value: 1.5 ether}();

        assertEq(bidAmt1, address(dutchAuction).balance);
        assertEq(attackContractInitBal, address(attackContract).balance);
    }
}
