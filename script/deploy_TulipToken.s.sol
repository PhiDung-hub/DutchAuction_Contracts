// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {TulipToken} from "src/TulipToken.sol";

contract TulipTokenDeployerScript is Script {
    function setUp() public {}

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address operator = 0xc24C29e9e71E03447b7FdfAd37198201d6722211;

        new TulipToken(1e23, operator);
        vm.stopBroadcast();
    }
}
