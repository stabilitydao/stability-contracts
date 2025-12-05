// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Mock to check XTokenBridge.send bad paths
contract MockXToken {
    using SafeERC20 for IERC20;

    address internal _token;
    uint internal _amountToSend;

    constructor(address token_, uint amountToSend) {
        _token = token_;
        _amountToSend = amountToSend;
    }

    function token() external view returns (address) {
        return _token;
    }

    function sendToBridge(
        address user,
        uint /*amount*/
    ) external {
        IERC20(_token).safeTransfer(user, _amountToSend);
    }
}
