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
        dutchAuction.startAuction(tulipToken, 100000, 100, 20, 20, 10);
        vm.expectRevert("Another Dutch auction is happening. Please wait...");
        dutchAuction.startAuction(tulipToken, 100000, 100, 20, 20, 10);
    }

    function test_StartAuction_RevertWhen_ExceedMaxTokenSupply() public {
        vm.expectRevert("The number of tokens minted exceeds the maximum possible supply!");
        dutchAuction.startAuction(tulipToken, 1000001, 100, 20, 20, 10);
    }

    function test_StartAuction() public {
        uint256 initialTokenSupply = 100000;
        uint256 startingPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        uint256 bidderPercentageLimit = 10;

        vm.expectCall(
            address(tulipToken), abi.encodeCall(tulipToken.operatorMint, initialTokenSupply)
        );
        dutchAuction.startAuction(tulipToken, initialTokenSupply, startingPrice, reservePrice, durationInMinutes, bidderPercentageLimit);
        
        assertEq(initialTokenSupply, dutchAuction.initialTokenSupply());
        assertEq(startingPrice, dutchAuction.startingPrice());
        assertEq(reservePrice, dutchAuction.reservePrice());
        assertEq((startingPrice - reservePrice) / durationInMinutes, dutchAuction.discountRate());
        assertEq(reservePrice, dutchAuction.clearingPrice());
        assertEq(block.timestamp, dutchAuction.startTime());
        assertEq(durationInMinutes, dutchAuction.duration());
        assertEq(block.timestamp + durationInMinutes * 60, dutchAuction.expectedEndTime());
        assertEq(dutchAuction.actualEndTime(), dutchAuction.expectedEndTime());
        assertTrue(dutchAuction.auctionIsStarted());
        assertFalse(dutchAuction.auctionIsSettled());
        assertEq(bidderPercentageLimit, dutchAuction.bidderPercentageLimit());
        assertEq(initialTokenSupply * bidderPercentageLimit / 100 * reservePrice, dutchAuction.maxWeiPerBidder());
    }

    function startValidDutchAuction() private {
        uint256 initialTokenSupply = 100000;
        uint256 startingPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        uint256 bidderPercentageLimit = 100000;
        dutchAuction.startAuction(tulipToken, initialTokenSupply, startingPrice, reservePrice, durationInMinutes, bidderPercentageLimit);
    }

    function test_Bid_RevertWhen_NoWeiIsCommitted() public {
        startValidDutchAuction();
        vm.expectRevert("No amount of Wei has been committed.");
        dutchAuction.bid{value:0}();
    }

    function test_Bid_RevertWhen_NoAuctionIsHappening() public {
        vm.expectRevert("No auction happening at the moment. Please wait for the next auction.");
        dutchAuction.bid{value:50000}();
    }

    function test_Bid_RevertWhen_NoAuctionIsHappeningBecauseSoldOut() public {
        startValidDutchAuction();
        dutchAuction.bid{value:100000 * 100000}();
        vm.expectRevert("No auction happening at the moment. Please wait for the next auction.");
        dutchAuction.bid{value:1}();
    }

    function test_Bid_RevertWhen_CurrentTotalCommitmentReachesMax() public {
        dutchAuction.startAuction(tulipToken, 100000, 100000, 10000, 20, 10);
        dutchAuction.bid{value:10000 * 10000}();
        vm.expectRevert("Already reach the maximum total Wei committed.");
        dutchAuction.bid{value:1}();
    }

    function test_Bid_RefundBidAmountExceedingMax() public {
        dutchAuction.startAuction(tulipToken, 100000, 100000, 10000, 20, 10);
        vm.expectCall(
            address(this), 5, ""
        );
        dutchAuction.bid{value:10000 * 10000 + 5}();
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
        assertEq(dutchAuction.getCurrentPrice(), dutchAuction.clearingPrice());
        assertEq(block.timestamp, dutchAuction.actualEndTime());
    }

    //Test for getCurrentTokenSupply function
    function test_GetCurrentTokenSupply() public {
        dutchAuction.startAuction(tulipToken, 100000, 100000, 10000, 20, 100000);
        uint256 bidValue = 50000;
        dutchAuction.bid{value: bidValue}();
        uint256 currentTokenSupply = dutchAuction.getCurrentTokenSupply();
        uint256 initialSupply = 100000;
        uint256 price = dutchAuction.getCurrentPrice();
        uint256 calculatedCurrentTokenSupply = initialSupply - (bidValue / price);

        assertEq(currentTokenSupply, calculatedCurrentTokenSupply);
    }


    //Test for no settle auction if there's no auction happening
    function test_clearAuction_WhenTheresNoAuction() public {
        vm.expectRevert("No auction has started.");
        dutchAuction.clearAuction();
    }

    //Test for settle Auction when auction is still in progress
    function test_settleAuction_AuctionInProgress() public {
        dutchAuction.startAuction(tulipToken, 100000, 100000, 10000, 20, 100000);
        vm.expectRevert("Auction has not ended.");
        dutchAuction.clearAuction();
    }

    //Test for usability of isAuctioning function
    function test_IsAuctioning() public {
        dutchAuction.startAuction(tulipToken, 100000, 100000, 10000, 20, 100000);
        bool success = dutchAuction.isAuctioning();
        assertTrue(success);

        dutchAuction.bid{value: 1 * 10 ** 12}();
        bool fail = dutchAuction.isAuctioning();
        assertTrue(!fail);
    }

    receive() external payable {}
}