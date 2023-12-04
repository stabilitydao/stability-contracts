// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

contract MockERC721 is ERC721EnumerableUpgradeable {
    // add this to be excluded from coverage report
    function test() public {}

    function init(string memory name_, string memory symbol_) external initializer {
        __ERC721_init(name_, symbol_);
    }

    function mint() external {
        _mint(msg.sender, totalSupply());
    }
}
