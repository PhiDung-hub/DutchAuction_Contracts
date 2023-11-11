// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {DutchAuction} from "src/DutchAuction.sol";
import {TulipToken} from "src/TulipToken.sol";
import {IAuctionableToken} from "src/interfaces/IAuctionableToken.sol";

contract DutchAuctionTest is Test {
    DutchAuction private dutchAuction;
    IAuctionableToken private token;

    uint256 private constant TOKEN_SUPPLY = 1e21; // 1 million tokens

    function setUp() public {
        dutchAuction = new DutchAuction();
        token = new TulipToken(TOKEN_SUPPLY, address(dutchAuction));
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
        dutchAuction.startAuction(token, TOKEN_SUPPLY + 1, 100, 101, 20, 10);
    }

    function test_StartAuction_RevertWhen_ExceedMaxTokenSupply() public {
        bytes4 errorSelector = bytes4(keccak256("MintLimitExceeded(uint256,uint256)"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector, TOKEN_SUPPLY + 1, TOKEN_SUPPLY));
        dutchAuction.startAuction(token, TOKEN_SUPPLY + 1, 100, 20, 20, 10);
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
        assertEq((startPrice - reservePrice) / (durationInMinutes - 1), dutchAuction.discountRate());
        assertEq(reservePrice, dutchAuction.clearingPrice());
        assertEq(block.timestamp, dutchAuction.startTime());
        assertEq(durationInMinutes, dutchAuction.duration());
        assertEq(block.timestamp + durationInMinutes * 60, dutchAuction.endTime());
        assertTrue(dutchAuction.auctionIsStarted());
        assertEq(initialTokenSupply * reservePrice / 1e18 * bidderPercentageLimit / 100, dutchAuction.maxWeiPerBidder());
    }

    function _startValidDutchAuction() private {
        uint256 initialTokenSupply = 1e20;
        uint256 startPrice = 0.02 ether;
        uint256 reservePrice = 0.001 ether;
        uint256 durationInMinutes = 20;
        uint256 bidderPercentageLimit = 10000;
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
        dutchAuction.bid{value:2e18}();
        bytes4 errorSelector = bytes4(keccak256("AuctionIsInactive()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.bid{value:1}();
    }

    function test_Bid_RevertWhen_CurrentTotalCommitmentReachesMax() public {
        dutchAuction.startAuction(token, 1e20, 1e5, 1e4, 20, 10);
        dutchAuction.bid{value:10 * 1e4}();
        bytes4 errorSelector = bytes4(keccak256("BidLimitReached()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.bid{value:1}();
    }

    function test_Bid_RefundBidAmountExceedingMax() public {
        dutchAuction.startAuction(token, 1e20, 100000, 10000, 20, 10);
        address thisAddress = address(this);
        uint256 balanceBefore = thisAddress.balance;
        vm.expectCall(thisAddress, 5, "");
        dutchAuction.bid{value:1e5 + 5}();
        uint256 balanceAfter = thisAddress.balance;
        assertEq(1e5, balanceBefore - balanceAfter);
    }

    function test_Bid_RefundBidAmountExceedingValueOfRemainingTokens() public {
        _startValidDutchAuction();
        address[] memory users = _setUp_Users();

        vm.prank(users[0]);
        uint256 user1ComAmt = 1e18;
        dutchAuction.bid{value: user1ComAmt}();

        uint256 user2BalanceBefore = users[1].balance;
        vm.prank(users[1]);
        uint256 user2ComAmt = 2e18;
        vm.expectCall(users[1], 1e18, "");
        dutchAuction.bid{value: user2ComAmt}();
        uint256 user2BalanceAfter = users[1].balance;
        assertEq(1e18, user2BalanceBefore - user2BalanceAfter);
    }

    function test_Bid_RefundBidAmountExceedingMaxAndValueOfRemainingTokens() public {
        dutchAuction.startAuction(token, 1e20, 100000, 100000, 20, 60);
        address[] memory users = _setUp_Users();

        vm.prank(users[0]);
        uint256 user1ComAmt = 50e5;
        dutchAuction.bid{value: user1ComAmt}();

        uint256 user2BalanceBefore = users[1].balance;
        vm.prank(users[1]);
        uint256 user2ComAmt = 70e5;
        vm.expectCall(users[1], 20e5, "");
        dutchAuction.bid{value: user2ComAmt}();
        uint256 user2BalanceAfter = users[1].balance;
        assertEq(50e5, user2BalanceBefore - user2BalanceAfter);
    }

    function test_Bid() public {
        _startValidDutchAuction();
        uint256 committedAmount = 5e17; // 0.5 ETH
        dutchAuction.bid{value:committedAmount}();
        assertEq(dutchAuction.getRemainingAllowance(address(this)), 95 * 1e17); // 9.5ETH left
    }

    function test_Bid_SoldOutAuction() public {
        _startValidDutchAuction();
        dutchAuction.bid{value:1e18}();
        vm.warp(block.timestamp + 1 * 60);
        dutchAuction.bid{value:1e18}();
        assertEq(dutchAuction.getCurrentPrice(), dutchAuction.clearingPrice());
        assertEq(block.timestamp, dutchAuction.endTime());
    }

    function test_ClearAuction_RevertWhen_TheresNoAuction() public {
        bytes4 errorSelector = bytes4(keccak256("AuctionIsNotStarted()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.clearAuction();
    }

    function test_ClearAuction_RevertWhen_AuctionInProgress() public {
        _startValidDutchAuction();
        bytes4 errorSelector = bytes4(keccak256("AuctionIsNotEnded()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.clearAuction();
    }

    function test_ClearAuction_RevertWhen_CalledTwice() public {
        _startValidDutchAuction();
        vm.warp(block.timestamp + 20 * 60 + 12);
        dutchAuction.clearAuction();
        bytes4 errorSelector = bytes4(keccak256("AuctionIsNotStarted()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.clearAuction();
    }

    function test_ClearAuction_WhenNoBid() public {
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

    function test_ClearAuction_WhenNotSoldOut() public {
        _startValidDutchAuction();
        address[] memory users = _setUp_Users();

        // User1 commit 0.02 ETH at the start of the auction
        vm.prank(users[0]);
        uint256 user1ComAmt = 2e16;
        dutchAuction.bid{value: user1ComAmt}();

        // User2 commit 0.02 ETH 5 minutes into the auction
        vm.warp(block.timestamp + 5 * 60);
        vm.prank(users[1]);
        uint256 user2ComAmt = 2e16;
        dutchAuction.bid{value: user2ComAmt}();

        // User3 commit 0.02 ETH 7 minutes into the auction
        vm.warp(block.timestamp + 2 * 60);
        vm.prank(users[2]);
        uint256 user3ComAmt = 2e16;
        dutchAuction.bid{value: user3ComAmt}();

        // Auction ends after 20 minutes, tokens not sold out
        vm.warp(block.timestamp + 13 * 60 + 1);
        dutchAuction.clearAuction();
        
        // Assert on the settlement logic
        uint256 clearingPrice = dutchAuction.clearingPrice();
        assertEq(dutchAuction.reservePrice(), clearingPrice);
        assertEq(user1ComAmt * 1e18 / clearingPrice, token.balanceOf(users[0]));
        assertEq(user2ComAmt * 1e18 / clearingPrice, token.balanceOf(users[1]));
        assertEq(user3ComAmt * 1e18/ clearingPrice, token.balanceOf(users[2]));
        assertEq(0, token.balanceOf(address(dutchAuction))); // remaining left-over tokens must be burnt
        assertFalse(dutchAuction.auctionIsStarted());
    }

    function test_ClearAuction_WhenSoldOut() public {
        _startValidDutchAuction();
        address[] memory users = _setUp_Users();

        // User1 commits 0.02 ETH at the start of the auction
        vm.prank(users[0]);
        uint256 user1ComAmt = 2e16;
        dutchAuction.bid{value: user1ComAmt}();

        // User2 commits 0.03 ETH 5 minutes into the auction
        vm.warp(block.timestamp + 5 * 60);
        vm.prank(users[1]);
        uint256 user2ComAmt = 3e16;
        dutchAuction.bid{value: user2ComAmt}();

        // User3 commits 500 wei more than the value of the remaining supply at 10 minutes into the auction
        // sold out the auction
        vm.warp(block.timestamp + 5 * 60);
        uint256 expectedClearingPrice = dutchAuction.getCurrentPrice();
        uint256 user3UnsatisfiedComAmt = 500;
        uint256 user3SatisfiedComAmt = (expectedClearingPrice * dutchAuction.initialTokenSupply()) / 1e18 - user1ComAmt - user2ComAmt;
        uint256 user3ComAmt = user3SatisfiedComAmt + user3UnsatisfiedComAmt;
        vm.prank(users[2]);
        dutchAuction.bid{value: user3ComAmt}();

        dutchAuction.clearAuction();
        
        // Assert on the settlement logic
        uint256 clearingPrice = dutchAuction.clearingPrice();
        assertEq(expectedClearingPrice, clearingPrice);
        assertEq(user1ComAmt * 1e18 / clearingPrice, token.balanceOf(users[0]));
        assertEq(user2ComAmt * 1e18 / clearingPrice, token.balanceOf(users[1]));
        assertEq(user3SatisfiedComAmt * 1e18 / clearingPrice, token.balanceOf(users[2]));
        assertGt(1e6, token.balanceOf(address(dutchAuction)));
        assertFalse(dutchAuction.auctionIsStarted());
    }

    function test_ClearAuction_WhenNotSoldOut_But_RequireRefund() public {
        _startValidDutchAuction();
        address[] memory users = _setUp_Users();

        // User1 commits 0.5 ETH at the start of the auction
        vm.prank(users[0]);
        uint256 user1ComAmt = 0.5 ether;
        dutchAuction.bid{value: user1ComAmt}();

        // User2 commits 0.5 ETH at the start of the auction
        vm.prank(users[1]);
        uint256 user2ComAmt = 0.5 ether;
        dutchAuction.bid{value: user2ComAmt}();

        // Auction ends after 20 minutes, tokens not sold out
        vm.warp(block.timestamp + 13 * 60 + 1);
        dutchAuction.clearAuction();
        
        // Assert on the settlement logic
        uint256 clearingPrice = dutchAuction.clearingPrice();
        assertEq(dutchAuction.reservePrice(), clearingPrice);
        assertEq(dutchAuction.initialTokenSupply(), token.balanceOf(users[0]));
        assertEq(0, token.balanceOf(users[1]));
        assertEq(0, token.balanceOf(address(dutchAuction)));
        assertFalse(dutchAuction.auctionIsStarted());
    }

    function test_Withdraw_RevertWhen_NoAuction() public {
        bytes4 errorSelector = bytes4(keccak256("AuctionIsNotStarted()"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector));
        dutchAuction.withdraw();
    }

    function test_Withdraw_RevertWhen_AuctionInProgress() public {
        _startValidDutchAuction();
        bytes4 errorSelector = bytes4(keccak256("NotWithdrawableYet(uint256)"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector, 30 * 60));
        dutchAuction.withdraw();
    }

    function test_Withdraw_RevertWhen_Not10MinsYetFromAuctionTimeEnded() public {
        _startValidDutchAuction();
        vm.warp(block.timestamp + 21 * 60);
        bytes4 errorSelector = bytes4(keccak256("NotWithdrawableYet(uint256)"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector, 9 * 60));
        dutchAuction.withdraw();
    }

    function test_Withdraw_RevertWhen_Not10MinsYetFromAuctionSoldOut() public {
        _startValidDutchAuction();
        dutchAuction.bid{value: 1e20}();
        vm.warp(block.timestamp + 9 * 60);
        bytes4 errorSelector = bytes4(keccak256("NotWithdrawableYet(uint256)"));
        vm.expectRevert(abi.encodeWithSelector(errorSelector, 1 * 60));
        dutchAuction.withdraw();
    }

    function test_Withdraw() public {
        _startValidDutchAuction();
        uint256 commitAmt = 1e5;
        dutchAuction.bid{value: commitAmt}();

        vm.warp(block.timestamp + 30 * 60 + 1);
        uint256 initialBalance = address(this).balance;
        dutchAuction.withdraw();
        assertEq(commitAmt, address(this).balance - initialBalance);
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

    function test_IsAuctioning_AuctionisClosed_WhenTimeoutButNotSoldOut() public {
        _startValidDutchAuction();

        dutchAuction.bid{value: 1000}();

        vm.warp(block.timestamp + 21 * 60);

        bool isAuctioning = dutchAuction.isAuctioning();
        assertFalse(isAuctioning);
    }

    function test_IsAuctioning_AuctionisClosed_WhenSoldOut() public {
        _startValidDutchAuction();

        dutchAuction.bid{value: 10 ether}();
        bool isAuctioning = dutchAuction.isAuctioning();
        assertFalse(isAuctioning);
    }

    function test_GetCurrentTokenSupply() public {
        uint256 initialSupply = 1e20;
        dutchAuction.startAuction(token, initialSupply, 2e16, 1e15, 20, 100000);

        uint256 bidValue = 1e17;
        dutchAuction.bid{value: bidValue}();
        
        uint256 price = dutchAuction.getCurrentPrice();
        uint256 expectedCurrentTokenSupply = initialSupply - (bidValue * 1e18 / price);

        assertEq(expectedCurrentTokenSupply, dutchAuction.getCurrentTokenSupply());
    }

    function test_GetCurrentTokenSupply_WhenSoldOut() public {
        uint256 initialSupply = 1e20;
        dutchAuction.startAuction(token, initialSupply, 100000, 10000, 20, 100000);

        uint256 bidValue = 100 ether;
        dutchAuction.bid{value: bidValue}();

        assertEq(0, dutchAuction.getCurrentTokenSupply());
    }

    function test_GetRemainingAllowance() public {
        dutchAuction.startAuction(token, 1e20, 100000, 10000, 20, 10);
        uint256 bidValue1 = 10000;
        dutchAuction.bid{value: bidValue1}();
        uint256 bidValue2 = 20000;
        dutchAuction.bid{value: bidValue2}();

        assertEq(dutchAuction.maxWeiPerBidder() - bidValue1 - bidValue2, dutchAuction.getRemainingAllowance(address(this)));
    }

    function test_GetCurrentPrice_AtStart() public {
        uint256 startPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        _startValidDutchAuction1(startPrice, reservePrice, durationInMinutes);

        uint256 originalPrice = dutchAuction.getCurrentPrice();
        assertEq(startPrice, originalPrice);
    }

    function test_GetCurrentPrice_After1MinFromStart() public {
        uint256 startPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        _startValidDutchAuction1(startPrice, reservePrice, durationInMinutes);

        vm.warp(block.timestamp + 60);

        uint256 expectedCurrentPrice = startPrice - dutchAuction.discountRate() * (block.timestamp - dutchAuction.startTime()) / 60;
        uint256 currentPrice = dutchAuction.getCurrentPrice();
        assertEq(expectedCurrentPrice, currentPrice);
    }

    function test_GetCurrentPrice_After5MinsFromStart() public {
        uint256 startPrice = 100000;
        uint256 reservePrice = 10000;
        uint256 durationInMinutes = 20;
        _startValidDutchAuction1(startPrice, reservePrice, durationInMinutes);

        vm.warp(block.timestamp + 60 * 5);

        uint256 expectedCurrentPrice = startPrice - dutchAuction.discountRate() * (block.timestamp - dutchAuction.startTime()) / 60;
        uint256 currentPrice = dutchAuction.getCurrentPrice();
        assertEq(expectedCurrentPrice, currentPrice);
    }

    function test_GetCurrentPrice_AtAuctionEnd() public {
        _startValidDutchAuction();

        vm.warp(block.timestamp + dutchAuction.duration() * 60 + 1);

        uint256 finalPrice = dutchAuction.getCurrentPrice();
        assertEq(dutchAuction.reservePrice(), finalPrice);
    }

    function _startValidDutchAuction1(uint256 _startPrice, uint256 _reservePrice, uint256 _durationInMinutes) private {
        dutchAuction.startAuction(token, 100000, _startPrice, _reservePrice, _durationInMinutes, 100000);
    }

    receive() external payable {}
}
