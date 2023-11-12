// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {DutchAuction} from "src/DutchAuction.sol";
import {IAuctionableToken} from "src/interfaces/IAuctionableToken.sol";

contract StartAuctionCase1 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        DutchAuction auction = DutchAuction(0x7Af467D962eFc7a6D3a107DE2CcE6c9312f1f884);
        IAuctionableToken token = IAuctionableToken(0x6252cf1805c19F53578a3F47AC4D8AE9398701dc);
        auction.startAuction(token, 1e20, 2e15, 1e15, 20, 10);
        vm.stopBroadcast();
    }
}

contract StartAuctionCase2 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        DutchAuction auction = DutchAuction(0x7Af467D962eFc7a6D3a107DE2CcE6c9312f1f884);
        IAuctionableToken token = IAuctionableToken(0x6252cf1805c19F53578a3F47AC4D8AE9398701dc);
        auction.startAuction(token, 1e20, 2e15, 1e15, 20, 10000);
        vm.stopBroadcast();
    }
}
