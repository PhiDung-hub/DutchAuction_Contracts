// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {TulipToken} from "src/TulipToken.sol";

contract TulipTokenDeployerScript is Script {
    function setUp() public {}

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address operator = 0x7Af467D962eFc7a6D3a107DE2CcE6c9312f1f884;

        new TulipToken(1e23, operator);
        vm.stopBroadcast();
    }
}
