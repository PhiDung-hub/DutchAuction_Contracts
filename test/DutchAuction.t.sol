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

    function test_OwnerIsDeployer() public {
        assertEq(address(this), dutchAuction.owner());
    }

    function test_StartAuction_RevertWhen_AnotherAuctionIsHappening() public {
        dutchAuction.startAuction(tulipToken, 100000, 100, 20, 20);
        vm.expectRevert("Another Dutch auction is happening. Please wait...");
        dutchAuction.startAuction(tulipToken, 100000, 100, 20, 20);
    }

    function test_StartAuction_RevertWhen_ExceedMaxTokenSupply() public {
        vm.expectRevert("The number of tokens minted exceeds the maximum possible supply!");
        dutchAuction.startAuction(tulipToken, 1000001, 100, 20, 20);
    }

    function test_StartAuction() public {
        uint256 initialTokenSupply = 100000;
        uint256 startingPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        uint256 durationInSeconds = durationInMinutes * 60;

        vm.expectCall(
            address(tulipToken), abi.encodeCall(tulipToken.operatorMint, initialTokenSupply)
        );
        dutchAuction.startAuction(tulipToken, initialTokenSupply, startingPrice, reservePrice, durationInMinutes);
        
        assertEq(initialTokenSupply, dutchAuction.initialTokenSupply());
        assertEq(startingPrice, dutchAuction.startingPrice());
        assertEq(reservePrice, dutchAuction.reservePrice());
        assertEq((startingPrice - reservePrice) / durationInSeconds, dutchAuction.discountRate());
        assertEq(reservePrice, dutchAuction.clearingPrice());
        assertEq(block.timestamp, dutchAuction.startTime());
        assertEq(durationInSeconds, dutchAuction.duration());
        assertEq(block.timestamp + durationInSeconds, dutchAuction.expectedEndTime());
        assertEq(dutchAuction.actualEndTime(), dutchAuction.expectedEndTime());
        assertTrue(dutchAuction.auctionIsStarted());
    }

    function startValidDutchAuction() private {
        uint256 initialTokenSupply = 100000;
        uint256 startingPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        dutchAuction.startAuction(tulipToken, initialTokenSupply, startingPrice, reservePrice, durationInMinutes);
    }

    function test_Bid_RevertWhen_NoWeiIsCommitted() public {
        startValidDutchAuction();
        vm.expectRevert("No amount of Wei has been committed.");
        dutchAuction.bid{value:0}();
    }

    function test_Bid_RefundAndRevertWhen_NoAuctionIsHappening() public {
        uint256 committedAmount = 50000;
        vm.expectCall(
            address(this), committedAmount, ""
        );
        vm.expectRevert("No auction happening at the moment. Please wait for the next auction.");
        dutchAuction.bid{value:committedAmount}();
    }

    function test_Bid() public {
        startValidDutchAuction();
        uint256 committedAmount = 50000000;
        dutchAuction.bid{value:committedAmount}();
    }

    function test_Bid_SoldOutAuction() public {
        startValidDutchAuction();
        dutchAuction.bid{value:5 * 10 ** 9}();
        dutchAuction.bid{value:6 * 10 ** 9}();  // how to simulate this bid coming quite significantly later than the first bid?
        assertEq(dutchAuction.getPrice(), dutchAuction.clearingPrice());
        assertEq(block.timestamp, dutchAuction.actualEndTime());
    }

    receive() external payable {}
}