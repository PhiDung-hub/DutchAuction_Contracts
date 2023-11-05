// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAuctionableToken} from "src/interfaces/IAuctionableToken.sol";
import {MintLimitExceeded} from "src/lib/Errors.sol";

contract TulipToken is IAuctionableToken, ERC20Burnable, Ownable {
    uint256 public immutable maxSupply;
    address public operator;

    // by default, ERC20 uses a value of 18 for decimals
    constructor(
        uint256 _maxSupply,
        address _operator
    ) ERC20("Tulip", "TL") Ownable(_operator) {
        maxSupply = _maxSupply;
        operator = _operator; // DutchAuction contract
    }

    function operatorMint(uint256 amount) external onlyOwner {
        uint256 _mintLimit = maxSupply - totalSupply();
        if (amount > _mintLimit) {
            revert MintLimitExceeded(amount, _mintLimit);
        }
        _mint(operator, amount);

        emit OperatorMint(amount);
    }
}
