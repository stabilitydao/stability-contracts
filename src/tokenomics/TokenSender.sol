// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";

contract TokenSender {
    address public immutable platform;

    constructor(address platform_) {
        platform = platform_;
    }

    function send(address token, address[] calldata receivers, uint[] calldata amounts) external {
        require(IPlatform(platform).isOperator(msg.sender), "denied");
        uint len = receivers.length;
        for (uint i; i < len; ++i) {
            // slither-disable-next-line unchecked-transfer
            IERC20(token).transferFrom(msg.sender, receivers[i], amounts[i]);
        }
    }
}
