// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMintedERC20} from "../interfaces/IMintedERC20.sol";

contract Token is ERC20, ERC20Burnable, Ownable, ERC20Permit, IMintedERC20 {
    constructor(
        address distributor,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) Ownable(distributor) ERC20Permit(symbol_) {}

    /// @inheritdoc IMintedERC20
    function mint(address to, uint amount) public onlyOwner {
        _mint(to, amount);
    }
}
