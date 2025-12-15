// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library RecoveryRelayerLib {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.RecoveryRelayer")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant _RECOVERY_RELAYER_STORAGE_LOCATION =
        0xdd1a9ce3728ddab87b43e5829ea263572add34ec16b3c991bb693f66c8715d00;

    //region -------------------------------------- Data types

    error NotWhitelisted();

    event RegisterTokens(address[] tokens);
    event SetThresholds(address[] tokens, uint[] thresholds);
    event Whitelist(address operator, bool add);

    /// @custom:storage-location erc7201:stability.RecoveryRelayer
    struct RecoveryRelayerStorage {
        /// @notice Minimum thresholds for tokens to trigger a swap
        mapping(address token => uint threshold) tokenThresholds;
        /// @notice Whitelisted operators that can call main actions
        mapping(address operator => bool allowed) whitelistOperators;
        /// @notice All tokens with not zero amounts - possible swap sources
        EnumerableSet.AddressSet registeredTokens;
    }

    //endregion -------------------------------------- Data types

    //region -------------------------------------- View
    /// @notice Return list of registered tokens with amounts exceeding thresholds
    /// Meta vault tokens are excluded from the list
    function getListTokensToSwap(RecoveryRelayerStorage storage $) external view returns (address[] memory tokens) {
        uint len = $.registeredTokens.length();
        address[] memory tempTokens = new address[](len);
        uint countNotZero;
        for (uint i; i < len; ++i) {
            address token = $.registeredTokens.at(i);
            uint balance = IERC20(token).balanceOf(address(this));
            if (balance > $.tokenThresholds[token]) {
                tempTokens[countNotZero] = token;
                countNotZero++;
            }
        }

        return _removeEmpty(tempTokens, countNotZero);
    }

    function getListRegisteredTokens(RecoveryRelayerStorage storage $) external view returns (address[] memory tokens) {
        return $.registeredTokens.values();
    }

    //endregion -------------------------------------- View

    //region -------------------------------------- Governance actions
    function setThresholds(address[] memory tokens, uint[] memory thresholds) internal {
        RecoveryRelayerStorage storage $ = getRecoveryRelayerStorage();
        uint len = tokens.length;
        for (uint i; i < len; ++i) {
            $.tokenThresholds[tokens[i]] = thresholds[i];
        }
        emit SetThresholds(tokens, thresholds);
    }

    function changeWhitelist(address operator_, bool add_) internal {
        RecoveryRelayerStorage storage $ = getRecoveryRelayerStorage();
        $.whitelistOperators[operator_] = add_;

        emit Whitelist(operator_, add_);
    }

    //endregion -------------------------------------- Governance actions

    //region -------------------------------------- Actions

    /// @notice Register income. Select a pool with minimum price and detect its token 1.
    /// Swap all {tokens} to the token1. Buy recovery tokens using token 1.
    function registerAssets(address[] memory tokens_) internal {
        RecoveryRelayerStorage storage $ = getRecoveryRelayerStorage();

        emit RegisterTokens(tokens_);
        uint len = tokens_.length;
        for (uint i; i < len; ++i) {
            $.registeredTokens.add(tokens_[i]);
        }
    }

    //endregion -------------------------------------- Actions

    //region -------------------------------------- Utils

    function getRecoveryRelayerStorage() internal pure returns (RecoveryRelayerStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _RECOVERY_RELAYER_STORAGE_LOCATION
        }
    }

    /// @notice Remove zero items from the given array
    function _removeEmpty(address[] memory items, uint countNotZero) internal pure returns (address[] memory dest) {
        uint len = items.length;
        dest = new address[](countNotZero);

        uint index = 0;
        for (uint i; i < len; ++i) {
            if (items[i] != address(0)) {
                dest[index] = items[i];
                index++;
            }
        }
    }

    //endregion -------------------------------------- Utils
}
