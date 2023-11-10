// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {DutchAuction} from "src/DutchAuction.sol";
import {IAuctionableToken} from "src/interfaces/IAuctionableToken.sol";

contract ClearAuctionScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        DutchAuction auction = DutchAuction(0xe9B3340e6f8D7Cc15FB66a143c0d3DC4b6733FBB);
        auction.clearAuction();
        vm.stopBroadcast();
    }
}
