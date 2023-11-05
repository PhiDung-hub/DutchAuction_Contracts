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
        bytes4 errorSelector = bytes4(keccak256("AuctionIsStarted()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.startAuction(tulipToken, 100000, 100, 20, 20, 10);
    }

    function test_StartAuction_RevertWhen_ExceedMaxTokenSupply() public {
        bytes4 errorSelector = bytes4(keccak256("MintLimitExceeded(uint256,uint256)"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector, 1000001, 1000000));
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
        bytes4 errorSelector = bytes4(keccak256("ZeroCommitted()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.bid{value:0}();
    }

    function test_Bid_RevertWhen_NoAuctionIsHappening() public {
        bytes4 errorSelector = bytes4(keccak256("AuctionIsInactive()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.bid{value:50000}();
    }

    function test_Bid_RevertWhen_NoAuctionIsHappeningBecauseSoldOut() public {
        startValidDutchAuction();
        dutchAuction.bid{value:1 * 10 ** 12}();
        bytes4 errorSelector = bytes4(keccak256("AuctionIsInactive()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.bid{value:1}();
    }

    function test_Bid_RevertWhen_CurrentTotalCommitmentReachesMax() public {
        dutchAuction.startAuction(tulipToken, 100000, 100000, 10000, 20, 10);
        dutchAuction.bid{value:10000 * 10000}();
        bytes4 errorSelector = bytes4(keccak256("BidLimitReached()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
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

    function test_clearAuction_RevertWhen_TheresNoAuction() public {
        bytes4 errorSelector = bytes4(keccak256("AuctionIsNotStarted()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.clearAuction();
    }

    function test_clearAuction_RevertWhen_AuctionInProgress() public {
        dutchAuction.startAuction(tulipToken, 100000, 100000, 10000, 20, 10);
        bytes4 errorSelector = bytes4(keccak256("AuctionIsNotEnded()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.clearAuction();
    }

    function test_clearAuction_RevertWhen_CalledTwice() public {
        dutchAuction.startAuction(tulipToken, 100000, 100000, 10000, 20, 100000);
        dutchAuction.bid{value: 1 * 10 ** 12}();
        dutchAuction.clearAuction();
        bytes4 errorSelector = bytes4(keccak256("AuctionIsNotStarted()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.clearAuction();
    }

    function test_clearAuction() public {
        startValidDutchAuction();
        vm.warp(block.timestamp + 21 * 60);
        dutchAuction.clearAuction();
    }

    function test_withdraw_RevertWhen_NoAuction() public {
        bytes4 errorSelector = bytes4(keccak256("AuctionIsNotStarted()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.withdraw();
    }

    function test_withdraw_RevertWhen_AuctionInProgress() public {
        startValidDutchAuction();
        bytes4 errorSelector = bytes4(keccak256("NotWithdrawableYet(uint256)"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector, 30 * 60));
        dutchAuction.withdraw();
    }

    function test_withdraw_RevertWhen_Not10MinsYetFromAuctionTimeEnded() public {
        startValidDutchAuction();
        vm.warp(block.timestamp + 21 * 60);
        bytes4 errorSelector = bytes4(keccak256("NotWithdrawableYet(uint256)"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector, 9 * 60));
        dutchAuction.withdraw();
    }

    // Got bug. Check later
    function test_withdraw_RevertWhen_Not10MinsYetFromAuctionSoldOut() public {
        startValidDutchAuction();
        dutchAuction.bid{value: 1 * 10 ** 12}();
        vm.warp(block.timestamp + 9 * 60);
        bytes4 errorSelector = bytes4(keccak256("NotWithdrawableYet(uint256)"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector, 1 * 60));
        dutchAuction.withdraw();
    }

    function test_withdraw_RevertWhen_NoAmountToWithdraw() public {
        startValidDutchAuction();
        vm.warp(block.timestamp + 30 * 60 + 1);
        vm.expectRevert("No token to withdraw.");
        dutchAuction.withdraw();
    }

    function test_withdraw() public {
        startValidDutchAuction();
        dutchAuction.bid{value: 100000}();
        vm.warp(block.timestamp + 30 * 60 + 1);
        dutchAuction.withdraw();
    }

    function test_withdraw_SettleAuction() public {
        startValidDutchAuction();
        dutchAuction.bid{value: 100000}();
        vm.warp(block.timestamp + 30 * 60 + 1);
        dutchAuction.withdraw();
        assertTrue(dutchAuction.auctionIsSettled());
    }

    //Test for usability of isAuctioning function
    function test_IsAuctioning() public {
        startValidDutchAuction();
        bool isAuctioning = dutchAuction.isAuctioning();
        assertTrue(isAuctioning);
    }

    function test_IsAuctioning_NoAuction() public {
        bool isAuctioning = dutchAuction.isAuctioning();
        assertFalse(isAuctioning);
    }

    function test_isAuctioning_AuctionisClosed_WhenTimeoutButNotSoldOut() public {
        startValidDutchAuction();

        dutchAuction.bid{value: 1000}();

        vm.warp(block.timestamp + 21 * 60);

        bool isAuctioning = dutchAuction.isAuctioning();
        assertFalse(isAuctioning);
    }

    function test_isAuctioning_AuctionisClosed_WhenSoldOut() public {
        startValidDutchAuction();

        dutchAuction.bid{value: 1 * 10 ** 12}();
        bool isAuctioning = dutchAuction.isAuctioning();
        assertFalse(isAuctioning);
    }

    //Test for getCurrentTokenSupply function
    function test_getCurrentTokenSupply() public {
        uint256 initialSupply = 100000;
        dutchAuction.startAuction(tulipToken, initialSupply, 100000, 10000, 20, 100000);

        uint256 bidValue = 5000;
        dutchAuction.bid{value: bidValue}();
        
        uint256 price = dutchAuction.getCurrentPrice();
        uint256 expectedCurrentTokenSupply = initialSupply - (bidValue / price);

        assertEq(expectedCurrentTokenSupply, dutchAuction.getCurrentTokenSupply());
    }

    function test_getCurrentTokenSupply_WhenSoldOut() public {
        uint256 initialSupply = 100000;
        dutchAuction.startAuction(tulipToken, initialSupply, 100000, 10000, 20, 100000);

        uint256 bidValue = initialSupply * 100000;
        dutchAuction.bid{value: bidValue}();
        
        assertEq(100000, dutchAuction.getCurrentPrice());

        assertEq(0, dutchAuction.getCurrentTokenSupply());
    }

    //Test getBlockTimestampAtPrice
    function test_getBlockTimestampAtPrice() public {
        uint256 startingPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        startValidDutchAuction1(startingPrice, reservePrice, durationInMinutes);

        //Price is in the range
        uint256 correctPrice = 91000;
        uint256 blockTimestamp = dutchAuction.getBlockTimestampAtPrice(correctPrice);
        uint256 expectedBlockTimestamp = dutchAuction.startTime() + (startingPrice - correctPrice) / dutchAuction.discountRate() * 60;
        assertEq(expectedBlockTimestamp, blockTimestamp);
    }

    function test_getBlockTimestampAtPrice_RevertWhen_NotCorrectIncrement() public {
        uint256 startingPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        startValidDutchAuction1(startingPrice, reservePrice, durationInMinutes);

        uint256 wrongPrice = 90000;
        vm.expectRevert("Price must be in the appropriate increment.");
        dutchAuction.getBlockTimestampAtPrice(wrongPrice);
    }
    
    function test_getBlockTimestampAtPrice_RevertWhen_UnderReservePrice() public {
        uint256 startingPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        startValidDutchAuction1(startingPrice, reservePrice, durationInMinutes);

        uint256 wrongPrice = 1000;
        vm.expectRevert("Price not within range.");
        dutchAuction.getBlockTimestampAtPrice(wrongPrice);
    }

    function test_getBlockTimestampAtPrice_RevertWhen_OverStartingPrice() public {
        uint256 startingPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        startValidDutchAuction1(startingPrice, reservePrice, durationInMinutes);

        uint256 wrongPrice = 110000;
        vm.expectRevert("Price not within range.");
        dutchAuction.getBlockTimestampAtPrice(wrongPrice);
    }

    //Test getCurrentPrice function
    function test_getCurrentPrice_AtStart() public {
        uint256 startingPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        startValidDutchAuction1(startingPrice, reservePrice, durationInMinutes);

        uint256 originalPrice = dutchAuction.getCurrentPrice();
        assertEq(startingPrice, originalPrice);
    }

    function test_getCurrentPrice_After1MinFromStart() public {
        uint256 startingPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        startValidDutchAuction1(startingPrice, reservePrice, durationInMinutes);

        vm.warp(block.timestamp + 60);

        uint256 expectedCurrentPrice = startingPrice - dutchAuction.discountRate() * (block.timestamp - dutchAuction.startTime()) / 60;
        uint256 currentPrice = dutchAuction.getCurrentPrice();
        assertEq(expectedCurrentPrice, currentPrice);
    }

    function test_getCurrentPrice_AtAuctionEnd() public {
        startValidDutchAuction();

        vm.warp(block.timestamp + dutchAuction.duration() * 60);

        uint256 finalPrice = dutchAuction.getCurrentPrice();
        assertEq(dutchAuction.reservePrice(), finalPrice);
    }

    function startValidDutchAuction1(uint256 _startingPrice, uint256 _reservePrice, uint256 _durationInMinutes) private {
        dutchAuction.startAuction(tulipToken, 100000, _startingPrice, _reservePrice, _durationInMinutes, 100000);
    }

    receive() external payable {}
}
