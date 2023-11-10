// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {DutchAuction} from "src/DutchAuction.sol";
import {IAuctionableToken} from "src/interfaces/IAuctionableToken.sol";

contract StartAuctionScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        DutchAuction auction = DutchAuction(0x34c203E63A5915ebdfEA9D5aebb1F626C94a9C7C);
        IAuctionableToken token = IAuctionableToken(0x8B385317376fd22fA8f700C56424399D7c20C7B4);
        auction.startAuction(token, 100, 2e16, 1e15, 20, 10);
        vm.stopBroadcast();
    }
}
