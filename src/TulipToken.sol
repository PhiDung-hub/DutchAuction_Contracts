// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAuctionableToken} from "src/interfaces/IAuctionableToken.sol";
import {MintLimitExceeded} from "src/lib/Errors.sol";

contract TulipToken is IAuctionableToken, ERC20Burnable, Ownable {
    uint256 public immutable maxSupply;

    // by default, ERC20 uses a value of 18 for decimals
    constructor(
        uint256 _maxSupply,
        address _operator
    ) ERC20("Tulip", "TL") Ownable(_operator) {
        maxSupply = _maxSupply;
    }

    function operatorMint(uint256 _amount) external onlyOwner {
        uint256 _mintLimit = maxSupply - totalSupply();
        if (_amount > _mintLimit) {
            revert MintLimitExceeded(_amount, _mintLimit);
        }
        _mint(owner(), _amount);

        emit OperatorMint(_amount);
    }

    function burn(uint256 _value) public override (IAuctionableToken, ERC20Burnable) {
        super.burn(_value);
    }
}
