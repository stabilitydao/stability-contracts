// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./base/FarmingStrategyBase.sol";
import "./libs/StrategyIdLib.sol";
import "./libs/FarmMechanicsLib.sol";

/// @title Earning wS by supplying assets to Silo V2
/// @author 0xhokugava (https://github.com/0xhokugava)
contract SiloFarmStrategy is FarmingStrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        // if (addresses.length != 2 || nums.length != 1 || ticks.length != 0) {
        //     revert IControllable.IncorrectInitParams();
        // }

        // IFactory.Farm memory farm = _getFarm(addresses[0], nums[0]);
        // if (farm.addresses.length != 2 || farm.nums.length != 0 || farm.ticks.length != 0) {
        //     revert IFarmingStrategy.BadFarm();
        // }

        // // CompoundFarmStrategyStorage storage $ = _getCompoundFarmStrategyStorage();
        // // $.comet = IComet(farm.addresses[0]);
        // // $.cometRewards = ICometRewards(farm.addresses[1]);
        // address[] memory _assets = new address[](1);
        // // _assets[0] = IComet(farm.addresses[0]).baseToken();

        // __StrategyBase_init(addresses[0], StrategyIdLib.SILO_FARM, addresses[1], _assets, address(0), 0);

        // __FarmingStrategyBase_init(addresses[0], nums[0]);

        // IERC20(_assets[0]).forceApprove(farm.addresses[0], type(uint).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.SILO_FARM;
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x00d395), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {}

    /// @inheritdoc IStrategy
    function getAssetsProportions() external pure returns (uint[] memory proportions) {
        proportions = new uint[](1);
        proportions[0] = 1e18;
    }

    /// @inheritdoc IStrategy
    function getRevenue() external view returns (address[] memory __assets, uint[] memory amounts) {}

    /// @inheritdoc IStrategy
    function getSpecificName() external pure override returns (string memory, bool) {
        return ("", false);
    }

    /// @inheritdoc IStrategy
    function supportedVaultTypes() external pure override returns (string[] memory types) {
        types = new string[](1);
        types[0] = VaultTypeLib.COMPOUNDING;
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_)
        public
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        // addresses = new address[](0);
        // ticks = new int24[](0);
        // IFactory.Farm[] memory farms = IFactory(IPlatform(platform_).factory()).farms();
        // uint len = farms.length;
        // variants = new string[](1);
        // nums = new uint[](1);
        // uint total;
        // // nosemgrep
        // for (uint i; i < len; ++i) {
        //     // nosemgrep
        //     IFactory.Farm memory farm = farms[i];
        //     // nosemgrep
        //     if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, StrategyIdLib.SILO_FARM)) {
        //         ++total;
        //     }
        // }
        // variants = new string[](total);
        // nums = new uint[](total);
        // total = 0;
        // // nosemgrep
        // for (uint i; i < len; ++i) {
        //     // nosemgrep
        //     IFactory.Farm memory farm = farms[i];
        //     // nosemgrep
        //     if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, StrategyIdLib.SILO_FARM)) {
        //         nums[total] = i;
        //         variants[total] = _genDesc(farm.addresses[0]);
        //         ++total;
        //     }
        // }
    }

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external pure returns (bool isReady) {
        isReady = true;
    }

    /// @inheritdoc IFarmingStrategy
    function farmMechanics() external pure returns (string memory) {
        return FarmMechanicsLib.CLASSIC;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   FARMING STRATEGY BASE                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IFarmingStrategy
    function canFarm() external pure override returns (bool) {
        return true;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _depositAssets(uint[] memory amounts, bool /*claimRevenue*/ ) internal override returns (uint value) {}

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        StrategyBaseStorage storage _$_ = _getStrategyBaseStorage();
        return _withdrawAssets(_$_._assets, value, receiver);
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(
        address[] memory assets_,
        uint value,
        address receiver
    ) internal override returns (uint[] memory amountsOut) {}

    /// @inheritdoc StrategyBase
    function _claimRevenue()
        internal
        override
        returns (
            address[] memory __assets,
            uint[] memory __amounts,
            address[] memory __rewardAssets,
            uint[] memory __rewardAmounts
        )
    {}

    /// @inheritdoc StrategyBase
    function _compound() internal override {}

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        pure
        override(StrategyBase)
        returns (uint[] memory amountsConsumed, uint value)
    {
        amountsConsumed = new uint[](1);
        amountsConsumed[0] = amountsMax[0];
        value = amountsConsumed[0];
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(
        address[] memory, /*assets_*/
        uint[] memory amountsMax
    ) internal pure override(StrategyBase) returns (uint[] memory amountsConsumed, uint value) {
        return _previewDepositAssets(amountsMax);
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        StrategyBaseStorage storage _$_ = _getStrategyBaseStorage();
        assets_ = _$_._assets;
        amounts_ = new uint[](1);
        amounts_[0] = _$_.total;
    }

    /// @inheritdoc StrategyBase
    function _processRevenue(
        address[] memory, /*assets_*/
        uint[] memory /*amountsRemaining*/
    ) internal pure override returns (bool needCompound) {
        needCompound = true;
    }


    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _genDesc(address comet) internal view returns (string memory) {
        return string.concat(
            // "Earn COMP by supplying ", IERC20Metadata(IComet(comet).baseToken()).symbol(), " to Compound III"
        );
    }
}