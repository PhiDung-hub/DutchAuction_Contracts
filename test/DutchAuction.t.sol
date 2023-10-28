// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {DutchAuction} from "src/DutchAuction.sol";
import {TulipToken} from "src/TulipToken.sol";

contract DutchAuctionTest is Test {
    DutchAuction private dutchAuction;
    TulipToken private tulipToken;

    function setUp() public {
        dutchAuction = new DutchAuction();
        tulipToken = new TulipToken(1000000, address(dutchAuction));
    }

    function test_StartAuction_OwnerIsDeployer() public {
        assertEq(address(this), dutchAuction.owner());
    }

    function test_StartAuction_RevertWhen_AnotherAuctionIsHappening() public {
        dutchAuction.startAuction(tulipToken, 100000, 100, 20, 20);
        vm.expectRevert("Another Dutch auction is happening. Please wait...");
        dutchAuction.startAuction(tulipToken, 100000, 100, 20, 20);
    }
}