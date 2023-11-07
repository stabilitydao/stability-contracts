// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./base/Controllable.sol";
import "./libs/ConstantsLib.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IPairStrategyBase.sol";

contract Zap is Controllable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    string internal constant _VERSION = '1.0.0';

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error StrategyNotSupported();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function init(address platform_) external {
        __Controllable_init(platform_);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function quoteDeposit(address vault, address tokenIn, uint amountIn) external view returns(uint[] memory swapAmounts) {
        address strategy = address(IVault(vault).strategy());
        address[] memory assets = IStrategy(strategy).assets();
        uint len = assets.length;

        if (len != 2) {
            revert StrategyNotSupported();
        }

        swapAmounts = new uint[](len);
        IDexAdapter dexAdapter = IPairStrategyBase(strategy).dexAdapter();
        uint[] memory proportions = dexAdapter.getProportions(IPairStrategyBase(strategy).pool());
        uint amountInUsed = 0;
        for (uint i; i < len; ++i) {
            bool isLast = i == len - 1;
            if (assets[i] != tokenIn) {
                if (!isLast) {
                    swapAmounts[i] = amountIn * proportions[i] / ConstantsLib.DENOMINATOR;
                    amountInUsed += swapAmounts[i];
                } else {
                    swapAmounts[i] = amountIn - amountInUsed;
                }
            } else if (!isLast) {
                amountInUsed = amountIn * proportions[i] / ConstantsLib.DENOMINATOR;
            }
        }
    }

    /// @inheritdoc IControllable
    function VERSION() external pure returns (string memory) {
        return _VERSION;
    }
}
