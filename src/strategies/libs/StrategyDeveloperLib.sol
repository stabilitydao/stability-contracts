// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./StrategyIdLib.sol";
import "../../core/libs/CommonLib.sol";

/// @dev Strategy developer addresses used when strategy implementation was deployed at a network.
///      StrategyLogic NFT is minted to the address of a strategy developer.
library StrategyDeveloperLib {
    function getDeveloper(string memory strategyId) external pure returns (address) {
        if (CommonLib.eq(strategyId, StrategyIdLib.GAMMA_QUICKSWAP_FARM)) {
            return 0x88888887C3ebD4a33E34a15Db4254C74C75E5D4A;
        }
        if (CommonLib.eq(strategyId, StrategyIdLib.QUICKSWAPV3_STATIC_FARM)) {
            return 0x88888887C3ebD4a33E34a15Db4254C74C75E5D4A;
        }

        return address(0);
    }
}
