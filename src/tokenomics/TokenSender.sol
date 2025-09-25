// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";

contract TokenSender {
    /// forge-lint: disable-next-line(screaming-snake-case-immutable)
    address public immutable platform;

    constructor(address platform_) {
        platform = platform_;
    }

    function send(address token, address[] calldata receivers, uint[] calldata amounts) external {
        require(IPlatform(platform).isOperator(msg.sender), "denied");
        uint len = receivers.length;
        /// @dev it is a deployed non-upgradeable contract, we can only disable warnings instead of using `safeTransferFrom`
        /// forge-lint: disable-start(erc20-unchecked-transfer)
        for (uint i; i < len; ++i) {
            // slither-disable-next-line unchecked-transfer
            IERC20(token).transferFrom(msg.sender, receivers[i], amounts[i]);
        }
        /// forge-lint: disable-end(erc20-unchecked-transfer)
    }
}
