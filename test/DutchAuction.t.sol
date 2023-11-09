// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {DutchAuction} from "src/DutchAuction.sol";
import {TulipToken} from "src/TulipToken.sol";
import {IAuctionableToken} from "src/interfaces/IAuctionableToken.sol";

contract DutchAuctionTest is Test {
    DutchAuction private dutchAuction;
    IAuctionableToken private token;

    function setUp() public {
        dutchAuction = new DutchAuction();
        token = new TulipToken(1000000, address(dutchAuction));
    }

    function test_OwnerIsDeployer() public {
        assertEq(address(this), dutchAuction.owner());
    }

    function test_StartAuction_RevertWhen_AnotherAuctionIsHappening() public {
        dutchAuction.startAuction(token, 100000, 100, 20, 20, 10);
        bytes4 errorSelector = bytes4(keccak256("AuctionIsStarted()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.startAuction(token, 100000, 100, 20, 20, 10);
    }

    function test_StartAuction_RevertWhen_PricesInvalid() public {
        bytes4 errorSelector = bytes4(keccak256("InvalidPrices(uint256,uint256)"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector, 100, 101));
        dutchAuction.startAuction(token, 1000001, 100, 101, 20, 10);
    }

    function test_StartAuction_RevertWhen_ExceedMaxTokenSupply() public {
        bytes4 errorSelector = bytes4(keccak256("MintLimitExceeded(uint256,uint256)"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector, 1000001, 1000000));
        dutchAuction.startAuction(token, 1000001, 100, 20, 20, 10);
    }

    function test_StartAuction() public {
        uint256 initialTokenSupply = 100000;
        uint256 startPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        uint256 bidderPercentageLimit = 10;

        vm.expectCall(
            address(token), abi.encodeCall(token.operatorMint, initialTokenSupply)
        );
        dutchAuction.startAuction(token, initialTokenSupply, startPrice, reservePrice, durationInMinutes, bidderPercentageLimit);
        
        assertEq(initialTokenSupply, dutchAuction.initialTokenSupply());
        assertEq(initialTokenSupply, token.balanceOf(address(dutchAuction)));
        assertEq(startPrice, dutchAuction.startPrice());
        assertEq(reservePrice, dutchAuction.reservePrice());
        assertEq((startPrice - reservePrice) / durationInMinutes, dutchAuction.discountRate());
        assertEq(reservePrice, dutchAuction.clearingPrice());
        assertEq(block.timestamp, dutchAuction.startTime());
        assertEq(durationInMinutes, dutchAuction.duration());
        assertEq(block.timestamp + durationInMinutes * 60, dutchAuction.endTime());
        assertTrue(dutchAuction.auctionIsStarted());
        assertEq(initialTokenSupply * bidderPercentageLimit / 100 * reservePrice, dutchAuction.maxWeiPerBidder());
    }

    function _startValidDutchAuction() private {
        uint256 initialTokenSupply = 100000;
        uint256 startPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        uint256 bidderPercentageLimit = 100000;
        dutchAuction.startAuction(token, initialTokenSupply, startPrice, reservePrice, durationInMinutes, bidderPercentageLimit);
    }

    function test_Bid_RevertWhen_NoWeiIsCommitted() public {
        _startValidDutchAuction();
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
        _startValidDutchAuction();
        dutchAuction.bid{value:1 * 10 ** 12}();
        bytes4 errorSelector = bytes4(keccak256("AuctionIsInactive()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.bid{value:1}();
    }

    function test_Bid_RevertWhen_CurrentTotalCommitmentReachesMax() public {
        dutchAuction.startAuction(token, 100000, 100000, 10000, 20, 10);
        dutchAuction.bid{value:10000 * 10000}();
        bytes4 errorSelector = bytes4(keccak256("BidLimitReached()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.bid{value:1}();
    }

    function test_Bid_RefundBidAmountExceedingMax() public {
        dutchAuction.startAuction(token, 100000, 100000, 10000, 20, 10);
        address thisAddress = address(this);
        uint256 balanceBefore = thisAddress.balance;
        vm.expectCall(thisAddress, 5, "");
        dutchAuction.bid{value:10000 * 10000 + 5}();
        uint256 balanceAfter = thisAddress.balance;
        assertEq(10000 * 10000, balanceBefore - balanceAfter);
    }

    function test_Bid_RefundBidAmountExceedingValueOfRemainingTokens() public {
        _startValidDutchAuction();
        address[] memory users = _setUp_Users();

        vm.prank(users[0]);
        uint256 user1ComAmt = 5 * 10 ** 9;
        dutchAuction.bid{value: user1ComAmt}();

        uint256 user2BalanceBefore = users[1].balance;
        vm.prank(users[1]);
        uint256 user2ComAmt = 6 * 10 ** 9;
        vm.expectCall(users[1], 1 * 10 ** 9, "");
        dutchAuction.bid{value: user2ComAmt}();
        uint256 user2BalanceAfter = users[1].balance;
        assertEq(5 * 10 ** 9, user2BalanceBefore - user2BalanceAfter);
    }

    function test_Bid_RefundBidAmountExceedingMaxAndValueOfRemainingTokens() public {
        dutchAuction.startAuction(token, 100000, 100000, 100000, 20, 60);
        address[] memory users = _setUp_Users();

        vm.prank(users[0]);
        uint256 user1ComAmt = 5 * 10 ** 9;
        dutchAuction.bid{value: user1ComAmt}();

        uint256 user2BalanceBefore = users[1].balance;
        vm.prank(users[1]);
        uint256 user2ComAmt = 7 * 10 ** 9;
        vm.expectCall(users[1], 2 * 10 ** 9, "");
        dutchAuction.bid{value: user2ComAmt}();
        uint256 user2BalanceAfter = users[1].balance;
        assertEq(5 * 10 ** 9, user2BalanceBefore - user2BalanceAfter);
    }

    function test_Bid() public {
        _startValidDutchAuction();
        uint256 committedAmount = 50000000;
        dutchAuction.bid{value:committedAmount}();
    }

    function test_Bid_SoldOutAuction() public {
        _startValidDutchAuction();
        dutchAuction.bid{value:5 * 10 ** 9}();
        vm.warp(block.timestamp + 1 * 60);
        dutchAuction.bid{value:6 * 10 ** 9}();
        assertEq(dutchAuction.getCurrentPrice(), dutchAuction.clearingPrice());
        assertEq(block.timestamp, dutchAuction.endTime());
    }

    function test_clearAuction_RevertWhen_TheresNoAuction() public {
        bytes4 errorSelector = bytes4(keccak256("AuctionIsNotStarted()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.clearAuction();
    }

    function test_clearAuction_RevertWhen_AuctionInProgress() public {
        _startValidDutchAuction();
        bytes4 errorSelector = bytes4(keccak256("AuctionIsNotEnded()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.clearAuction();
    }

    function test_clearAuction_RevertWhen_CalledTwice() public {
        _startValidDutchAuction();
        dutchAuction.bid{value: 1 * 10 ** 12}();
        dutchAuction.clearAuction();
        bytes4 errorSelector = bytes4(keccak256("AuctionIsNotStarted()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.clearAuction();
    }

    function test_clearAuction_WhenNoBid() public {
        _startValidDutchAuction();
        vm.warp(block.timestamp + 21 * 60);
        dutchAuction.clearAuction();
        assertFalse(dutchAuction.auctionIsStarted());
    }

    function _setUp_Users() private returns(address[] memory) {
        address[] memory users = new address[](3);
        users[0] = vm.addr(1);
        users[1] = vm.addr(2);
        users[2] = vm.addr(3);
        for (uint256 i = 0; i < users.length; i++) {
            vm.deal(users[i], 10000 ether);
        }
        return users;
    }

    function test_clearAuction_WhenNotSoldOut() public {
        _startValidDutchAuction();
        address[] memory users = _setUp_Users();

        // User1 commit 10000000 wei at the start of the auction
        vm.prank(users[0]);
        uint256 user1ComAmt = 10000000;
        dutchAuction.bid{value: user1ComAmt}();

        // User2 commit 20000000 wei 5 minutes into the auction
        vm.warp(block.timestamp + 5 * 60);
        vm.prank(users[1]);
        uint256 user2ComAmt = 20000000;
        dutchAuction.bid{value: user2ComAmt}();

        // User3 commit 50000000 wei 7 minutes into the auction
        vm.warp(block.timestamp + 2 * 60);
        vm.prank(users[2]);
        uint256 user3ComAmt = 50000000;
        dutchAuction.bid{value: user3ComAmt}();

        // Auction ends after 20 minutes, tokens not sold out
        vm.warp(block.timestamp + 13 * 60 + 1);
        dutchAuction.clearAuction();
        
        // Assert on the settlement logic
        uint256 clearingPrice = dutchAuction.clearingPrice();
        assertEq(dutchAuction.reservePrice(), clearingPrice);
        assertEq(user1ComAmt / clearingPrice, token.balanceOf(users[0]));
        assertEq(user2ComAmt / clearingPrice, token.balanceOf(users[1]));
        assertEq(user3ComAmt / clearingPrice, token.balanceOf(users[2]));
        assertEq(0, token.balanceOf(address(dutchAuction))); // remaining left-over tokens must be burnt
        assertFalse(dutchAuction.auctionIsStarted());
    }

    function test_clearAuction_WhenSoldOut() public {
        _startValidDutchAuction();
        address[] memory users = _setUp_Users();

        // User1 commits 10000000 wei at the start of the auction
        vm.prank(users[0]);
        uint256 user1ComAmt = 10000000;
        dutchAuction.bid{value: user1ComAmt}();

        // User2 commits 20000000 wei 5 minutes into the auction
        vm.warp(block.timestamp + 5 * 60);
        vm.prank(users[1]);
        uint256 user2ComAmt = 20000000;
        dutchAuction.bid{value: user2ComAmt}();

        // User3 commits 500 wei more than the value of the remaining supply at 10 minutes into the auction
        // sold out the auction
        vm.warp(block.timestamp + 5 * 60);
        uint256 expectedClearingPrice = dutchAuction.getCurrentPrice();
        uint256 user3UnsatisfiedComAmt = 500;
        uint256 user3SatisfiedComAmt = expectedClearingPrice * dutchAuction.initialTokenSupply() - user1ComAmt - user2ComAmt;
        uint256 user3ComAmt = user3SatisfiedComAmt + user3UnsatisfiedComAmt;
        vm.prank(users[2]);
        dutchAuction.bid{value: user3ComAmt}();

        dutchAuction.clearAuction();
        
        // Assert on the settlement logic
        uint256 clearingPrice = dutchAuction.clearingPrice();
        assertEq(expectedClearingPrice, clearingPrice);
        assertEq(user1ComAmt / clearingPrice, token.balanceOf(users[0]));
        assertEq(user2ComAmt / clearingPrice, token.balanceOf(users[1]));
        assertEq(user3SatisfiedComAmt / clearingPrice, token.balanceOf(users[2]));
        assertGt(10 ** 12, token.balanceOf(address(dutchAuction)));
        assertFalse(dutchAuction.auctionIsStarted());
    }

    function test_withdraw_RevertWhen_NoAuction() public {
        bytes4 errorSelector = bytes4(keccak256("AuctionIsNotStarted()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.withdraw();
    }

    function test_withdraw_RevertWhen_AuctionInProgress() public {
        _startValidDutchAuction();
        bytes4 errorSelector = bytes4(keccak256("NotWithdrawableYet(uint256)"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector, 30 * 60));
        dutchAuction.withdraw();
    }

    function test_withdraw_RevertWhen_Not10MinsYetFromAuctionTimeEnded() public {
        _startValidDutchAuction();
        vm.warp(block.timestamp + 21 * 60);
        bytes4 errorSelector = bytes4(keccak256("NotWithdrawableYet(uint256)"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector, 9 * 60));
        dutchAuction.withdraw();
    }

    function test_withdraw_RevertWhen_Not10MinsYetFromAuctionSoldOut() public {
        _startValidDutchAuction();
        dutchAuction.bid{value: 1 * 10 ** 12}();
        vm.warp(block.timestamp + 9 * 60);
        bytes4 errorSelector = bytes4(keccak256("NotWithdrawableYet(uint256)"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector, 1 * 60));
        dutchAuction.withdraw();
    }

    function test_withdraw_RevertWhen_NoAmountToWithdraw() public {
        _startValidDutchAuction();
        vm.warp(block.timestamp + 30 * 60 + 1);
        vm.expectRevert("No token to withdraw.");
        dutchAuction.withdraw();
    }

    function test_withdraw() public {
        _startValidDutchAuction();
        uint256 commitAmt = 100000;
        dutchAuction.bid{value: commitAmt}();
        
        vm.warp(block.timestamp + 30 * 60 + 1);
        dutchAuction.withdraw();
        assertEq(commitAmt / dutchAuction.clearingPrice(), token.balanceOf(address(this)));
    }

    function test_IsAuctioning() public {
        _startValidDutchAuction();
        bool isAuctioning = dutchAuction.isAuctioning();
        assertTrue(isAuctioning);
    }

    function test_IsAuctioning_NoAuction() public {
        bool isAuctioning = dutchAuction.isAuctioning();
        assertFalse(isAuctioning);
    }

    function test_isAuctioning_AuctionisClosed_WhenTimeoutButNotSoldOut() public {
        _startValidDutchAuction();

        dutchAuction.bid{value: 1000}();

        vm.warp(block.timestamp + 21 * 60);

        bool isAuctioning = dutchAuction.isAuctioning();
        assertFalse(isAuctioning);
    }

    function test_isAuctioning_AuctionisClosed_WhenSoldOut() public {
        _startValidDutchAuction();

        dutchAuction.bid{value: 1 * 10 ** 12}();
        bool isAuctioning = dutchAuction.isAuctioning();
        assertFalse(isAuctioning);
    }

    function test_getCurrentTokenSupply() public {
        uint256 initialSupply = 100000;
        dutchAuction.startAuction(token, initialSupply, 100000, 10000, 20, 100000);

        uint256 bidValue = 5000;
        dutchAuction.bid{value: bidValue}();
        
        uint256 price = dutchAuction.getCurrentPrice();
        uint256 expectedCurrentTokenSupply = initialSupply - (bidValue / price);

        assertEq(expectedCurrentTokenSupply, dutchAuction.getCurrentTokenSupply());
    }

    function test_getCurrentTokenSupply_WhenSoldOut() public {
        uint256 initialSupply = 100000;
        dutchAuction.startAuction(token, initialSupply, 100000, 10000, 20, 100000);

        uint256 bidValue = initialSupply * 100000;
        dutchAuction.bid{value: bidValue}();

        assertEq(0, dutchAuction.getCurrentTokenSupply());
    }

    function test_getCurrentPrice_AtStart() public {
        uint256 startPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        _startValidDutchAuction1(startPrice, reservePrice, durationInMinutes);

        uint256 originalPrice = dutchAuction.getCurrentPrice();
        assertEq(startPrice, originalPrice);
    }

    function test_getCurrentPrice_After1MinFromStart() public {
        uint256 startPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        _startValidDutchAuction1(startPrice, reservePrice, durationInMinutes);

        vm.warp(block.timestamp + 60);

        uint256 expectedCurrentPrice = startPrice - dutchAuction.discountRate() * (block.timestamp - dutchAuction.startTime()) / 60;
        uint256 currentPrice = dutchAuction.getCurrentPrice();
        assertEq(expectedCurrentPrice, currentPrice);
    }

    function test_getCurrentPrice_After5MinsFromStart() public {
        uint256 startPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        _startValidDutchAuction1(startPrice, reservePrice, durationInMinutes);

        vm.warp(block.timestamp + 60 * 5);

        uint256 expectedCurrentPrice = startPrice - dutchAuction.discountRate() * (block.timestamp - dutchAuction.startTime()) / 60;
        uint256 currentPrice = dutchAuction.getCurrentPrice();
        assertEq(expectedCurrentPrice, currentPrice);
    }

    function test_getCurrentPrice_AtAuctionEnd() public {
        _startValidDutchAuction();

        vm.warp(block.timestamp + dutchAuction.duration() * 60);

        uint256 finalPrice = dutchAuction.getCurrentPrice();
        assertEq(dutchAuction.reservePrice(), finalPrice);
    }

    function _startValidDutchAuction1(uint256 _startPrice, uint256 _reservePrice, uint256 _durationInMinutes) private {
        dutchAuction.startAuction(token, 100000, _startPrice, _reservePrice, _durationInMinutes, 100000);
    }

    receive() external payable {}
}
