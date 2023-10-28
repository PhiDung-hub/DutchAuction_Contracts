// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {TulipToken} from "src/TulipToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TulipTokenTest is Test {
    TulipToken private token;
    uint256 private maxSupply;
    address private operatorAddress;

    function setUp() public {
        maxSupply = 1000000;
        operatorAddress = address(123);
        token = new TulipToken(maxSupply, operatorAddress);
    }

    function test_Constructor() public {
        assertEq(token.maxSupply(), maxSupply);
        assertEq(token.operator(), operatorAddress);
    }

    function test_operatorMintAsOperator() public {
        vm.prank(operatorAddress);
        token.operatorMint(300000);
        assertEq(token.totalSupply(), 300000);
    }

    function test_RevertWhen_operatorMintCallerIsNotOwner() public {
        address nonOperatorAddress = address(456);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOperatorAddress));
        vm.prank(nonOperatorAddress);
        token.operatorMint(50);
    }

    function test_RevertWhen_MintingMoreThanMaxSupply() public {
        vm.prank(operatorAddress);
        token.operatorMint(300000);

        vm.expectRevert("Minting the specified amount will cause number of tokens to exceed its max supply.");
        vm.prank(operatorAddress);
        token.operatorMint(800000);
    }
}