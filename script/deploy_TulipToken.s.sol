// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {TulipToken} from "src/TulipToken.sol";

contract TulipTokenDeployerScript is Script {
    function setUp() public {}

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address operator = vm.envAddress("AUCTION_CONTRACT");

        new TulipToken(1000, operator);
        vm.stopBroadcast();
    }
}
