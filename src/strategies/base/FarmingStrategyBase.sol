// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./StrategyBase.sol";
import "../libs/StrategyLib.sol";
import "../../interfaces/IStrategy.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IFarmingStrategy.sol";
import "../../interfaces/ISwapper.sol";

/// @title Base farming strategy
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
abstract contract FarmingStrategyBase is StrategyBase, IFarmingStrategy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Version of FarmingStrategyBase implementation
    string public constant VERSION_FARMING_STRATEGY_BASE = "1.2.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.FarmingStrategyBase")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant FARMINGSTRATEGYBASE_STORAGE_LOCATION =
        0xe61f0a7b2953b9e28e48cc07562ad7979478dcaee972e68dcf3b10da2cba6000;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    //slither-disable-next-line naming-convention
    function __FarmingStrategyBase_init(address platform_, uint farmId_) internal onlyInitializing {
        StrategyLib.FarmingStrategyBase_init(
            _getFarmingStrategyBaseStorage(), _getStrategyBaseStorage()._id, platform_, farmId_
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IFarmingStrategy
    function refreshFarmingAssets() external onlyOperator {
        StrategyLib.updateFarmingAssets(_getFarmingStrategyBaseStorage(), platform());
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(StrategyBase) returns (bool) {
        return interfaceId == type(IFarmingStrategy).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IFarmingStrategy
    function farmId() public view returns (uint) {
        return _getFarmingStrategyBaseStorage().farmId;
    }

    /// @inheritdoc IFarmingStrategy
    function farmingAssets() external view returns (address[] memory) {
        return _getFarmingStrategyBaseStorage()._rewardAssets;
    }

    /// @inheritdoc IFarmingStrategy
    function stakingPool() external view virtual returns (address) {
        return address(0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*         Providing farm data to derived contracts           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getFarm() internal view returns (IFactory.Farm memory) {
        return _getFarm(platform(), farmId());
    }

    function _getFarm(address platform_, uint farmId_) internal view returns (IFactory.Farm memory) {
        return IFactory(IPlatform(platform_).factory()).farm(farmId_);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _liquidateRewards(
        address exchangeAsset,
        address[] memory rewardAssets_,
        uint[] memory rewardAmounts_
    ) internal override returns (uint earnedExchangeAsset) {
        return StrategyLib.liquidateRewards(platform(), exchangeAsset, rewardAssets_, rewardAmounts_);
    }

    function _getFarmingStrategyBaseStorage() internal pure returns (FarmingStrategyBaseStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := FARMINGSTRATEGYBASE_STORAGE_LOCATION
        }
    }
}
