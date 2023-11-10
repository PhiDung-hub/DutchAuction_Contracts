// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {TulipToken} from "src/TulipToken.sol";

contract TulipTokenDeployerScript is Script {
    function setUp() public {}

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address operator = 0xe9B3340e6f8D7Cc15FB66a143c0d3DC4b6733FBB;

        new TulipToken(1e24, operator);
        vm.stopBroadcast();
    }
}
