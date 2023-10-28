// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract TulipToken is ERC20, ERC20Burnable {
    uint256 public immutable maxSupply;
    address public operator;

    // by default, ERC20 uses a value of 18 for decimals
    constructor(uint256 _maxSupply, address _operator) ERC20("Tulip", "TL") {
        maxSupply = _maxSupply;
        operator = _operator; // DutchAuction contract
    }

    function operatorMint(uint256 amount) public {
        _mint(operator, amount);
    }
}