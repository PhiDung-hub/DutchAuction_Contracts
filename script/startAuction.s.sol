// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {DutchAuction} from "src/DutchAuction.sol";
import {IAuctionableToken} from "src/interfaces/IAuctionableToken.sol";

contract StartAuctionCase1 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        DutchAuction auction = DutchAuction(0xc24C29e9e71E03447b7FdfAd37198201d6722211);
        IAuctionableToken token = IAuctionableToken(0x9bfCB9C2BC2A2BF3145A7DfABc7a7b52d4A089E3);
        auction.startAuction(token, 1e20, 2e15, 1e15, 20, 10);
        vm.stopBroadcast();
    }
}

contract StartAuctionCase2 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        DutchAuction auction = DutchAuction(0xc24C29e9e71E03447b7FdfAd37198201d6722211);
        IAuctionableToken token = IAuctionableToken(0x9bfCB9C2BC2A2BF3145A7DfABc7a7b52d4A089E3);
        auction.startAuction(token, 1e20, 2e15, 1e15, 20, 10000);
        vm.stopBroadcast();
    }
}
