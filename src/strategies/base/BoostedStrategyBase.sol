// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./StrategyBase.sol";
import "../../interfaces/IBoostedStrategy.sol";

/// @title A strategy that uses Booster to increase rewards.
/// @dev The strategy's assets/liquidity located on the Booster contract, which has a boost.
/// @author Alien Deployer (https://github.com/a17)
abstract contract BoostedStrategyBase is StrategyBase, IBoostedStrategy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Version of BoostedStrategyBase implementation
    string public constant VERSION_BOOSTED_STRATEGY_BASE = "1.0.0";

    // todo set
    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.BoostedStrategyBase")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant BOOSTEDSTRATEGYBASE_STORAGE_LOCATION =
        0xe61f0a7b2953b9e28e48cc07562ad7979478dcaee972e68dcf3b10da2cba6000;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.BoostedStrategyBase
    struct BoostedStrategyBaseStorage {
        /// @inheritdoc IBoostedStrategy
        address booster;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    //slither-disable-next-line naming-convention
    function __BoostedStrategyBase_init(address booster_) internal onlyInitializing {
        BoostedStrategyBaseStorage storage $ = _getBoostedStrategyBaseStorage();
        $.booster = booster_;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBoostedStrategy
    function booster() external view returns (address) {
        return _getBoostedStrategyBaseStorage().booster;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getBoostedStrategyBaseStorage() internal pure returns (BoostedStrategyBaseStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := BOOSTEDSTRATEGYBASE_STORAGE_LOCATION
        }
    }
}
