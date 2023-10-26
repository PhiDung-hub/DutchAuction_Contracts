// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";

contract TulipToken is ERC20, ERC20Detailed, ERC20Burnable {
    uint256 public immutable maxSupply;
    address public operator;

    constructor(unit256 _maxSupply, address _operator) ERC20Detailed("Tulip", "TL", 18) public {
        maxSupply = _maxSupply;
        operator = _operator;
    }

    function operatorMint(unit256 amount) public {
        _mint(operator, amount);
    }

    function operatorBurn(unit256 amount) public {
        _burn(operator, amount);
    }
}