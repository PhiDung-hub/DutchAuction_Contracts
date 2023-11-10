// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {DutchAuction} from "src/DutchAuction.sol";
import {IAuctionableToken} from "src/interfaces/IAuctionableToken.sol";

contract StartAuctionScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        DutchAuction auction = DutchAuction(0xe9B3340e6f8D7Cc15FB66a143c0d3DC4b6733FBB);
        IAuctionableToken token = IAuctionableToken(0x5cF62e82275550eE97f92f83cC5edA9885Cad0f7);
        auction.startAuction(token, 1e21, 2e16, 1e15, 20, 10);
        vm.stopBroadcast();
    }
}
