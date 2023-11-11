// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {TulipToken} from "src/TulipToken.sol";

contract TulipTokenDeployerScript is Script {
    function setUp() public {}

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address operator = 0xB22c6547A98d70D8A55Dc6bA03d450780dAe0D58;

        new TulipToken(1e21, operator);
        vm.stopBroadcast();
    }
}
