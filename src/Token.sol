// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract Token is ERC20 {
    address public operator;

    constructor(address operator){
        operator = operator;
    }

    function operatorMint(unit256 amount) public {
        _mint(operator, amount);
    }

    function operatorBurn(unit256 amount) public {
        _burn(operator, amount);
    }
}