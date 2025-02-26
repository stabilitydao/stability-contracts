// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title Stability Platform native token
contract STBL is ERC20, ERC20Burnable, ERC20Permit {
    constructor(address allocator) ERC20("Stability", "STBL") ERC20Permit("Stability") {
        _mint(allocator, 100_000_000 * 10 ** decimals());
    }
}
