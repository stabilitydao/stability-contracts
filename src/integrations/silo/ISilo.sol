// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

interface ISilo is IERC20, IERC4626, IERC3156FlashLender {
    enum ActionType {
        Deposit,
        Mint,
        Repay,
        RepayShares
    }

    struct Action {
        ActionType actionType;
        ISilo silo;
        IERC20 asset;
        bytes options;
    }

    enum CollateralType {
        Protected,
        Collateral
    }

    function execute(Action[] calldata _actions) external;

    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner,
        CollateralType _collateralType
    ) external returns (uint256 assets);
}
