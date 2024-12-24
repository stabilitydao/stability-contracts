// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./base/FarmingStrategyBase.sol";
import "./libs/StrategyIdLib.sol";
import "./libs/FarmMechanicsLib.sol";
import "../integrations/compound/IComet.sol";
import "../integrations/compound/ICometRewards.sol";

/// @title Earning COMP by supplying asset to Compound III
/// @author Alien Deployer (https://github.com/a17)
contract CompoundFarmStrategy is FarmingStrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.3.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.CompoundFarmStrategy")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant COMPOUNDFARMSTRATEGY_STORAGE_LOCATION =
        0xcf326bd898cddf877383e6d48244157ff5c39e4a9d4ff3e4f37136d40eb50000;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.CompoundFarmStrategy
    struct CompoundFarmStrategyStorage {
        IComet comet;
        ICometRewards cometRewards;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 2 || nums.length != 1 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }

        IFactory.Farm memory farm = _getFarm(addresses[0], nums[0]);
        if (farm.addresses.length != 2 || farm.nums.length != 0 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }

        CompoundFarmStrategyStorage storage $ = _getCompoundFarmStrategyStorage();
        $.comet = IComet(farm.addresses[0]);
        $.cometRewards = ICometRewards(farm.addresses[1]);
        address[] memory _assets = new address[](1);
        _assets[0] = IComet(farm.addresses[0]).baseToken();

        __StrategyBase_init(addresses[0], StrategyIdLib.COMPOUND_FARM, addresses[1], _assets, address(0), 0);

        __FarmingStrategyBase_init(addresses[0], nums[0]);

        IERC20(_assets[0]).forceApprove(farm.addresses[0], type(uint).max);

        // console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.CompoundFarmStrategy")) - 1)) & ~bytes32(uint256(0xff)));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.COMPOUND_FARM;
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x00d395), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        CompoundFarmStrategyStorage storage $ = _getCompoundFarmStrategyStorage();
        return _genDesc(address($.comet));
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() external pure returns (uint[] memory proportions) {
        proportions = new uint[](1);
        proportions[0] = 1e18;
    }

    /// @inheritdoc IStrategy
    function getRevenue() external view returns (address[] memory __assets, uint[] memory amounts) {
        // here we calculate only baseAsset revenue, because COMP rewards cant be calculated in view function
        CompoundFarmStrategyStorage storage $ = _getCompoundFarmStrategyStorage();
        StrategyBaseStorage storage _$_ = _getStrategyBaseStorage();
        __assets = new address[](1);
        __assets[0] = _$_._assets[0];
        amounts = new uint[](1);
        amounts[0] = $.comet.balanceOf(address(this)) - _$_.total;
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external pure override returns (string memory, bool) {
        return ("", false);
    }

    /// @inheritdoc IStrategy
    function supportedVaultTypes() external pure override returns (string[] memory types) {
        types = new string[](1);
        types[0] = VaultTypeLib.COMPOUNDING;
        // types[1] = VaultTypeLib.REWARDING;
        // types[2] = VaultTypeLib.REWARDING_MANAGED;
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_)
        public
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        addresses = new address[](0);
        ticks = new int24[](0);
        IFactory.Farm[] memory farms = IFactory(IPlatform(platform_).factory()).farms();
        uint len = farms.length;
        variants = new string[](1);
        nums = new uint[](1);
        uint total;
        // nosemgrep
        for (uint i; i < len; ++i) {
            // nosemgrep
            IFactory.Farm memory farm = farms[i];
            // nosemgrep
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, StrategyIdLib.COMPOUND_FARM)) {
                ++total;
            }
        }
        variants = new string[](total);
        nums = new uint[](total);
        total = 0;
        // nosemgrep
        for (uint i; i < len; ++i) {
            // nosemgrep
            IFactory.Farm memory farm = farms[i];
            // nosemgrep
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, StrategyIdLib.COMPOUND_FARM)) {
                nums[total] = i;
                variants[total] = _genDesc(farm.addresses[0]);
                ++total;
            }
        }
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
    function _depositAssets(uint[] memory amounts, bool /*claimRevenue*/ ) internal override returns (uint value) {
        value = amounts[0];
        if (value > 0) {
            CompoundFarmStrategyStorage storage $ = _getCompoundFarmStrategyStorage();
            StrategyBaseStorage storage _$_ = _getStrategyBaseStorage();
            IComet comet = $.comet;
            comet.supply(_$_._assets[0], amounts[0]);
            // _$_.total += value;
            _$_.total = comet.balanceOf(address(this));
        }
    }

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
    ) internal override returns (uint[] memory amountsOut) {
        CompoundFarmStrategyStorage storage $ = _getCompoundFarmStrategyStorage();
        StrategyBaseStorage storage _$_ = _getStrategyBaseStorage();
        $.comet.withdrawTo(receiver, assets_[0], value);
        amountsOut = new uint[](1);
        amountsOut[0] = value;
        _$_.total -= value;
    }

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
    {
        CompoundFarmStrategyStorage storage $ = _getCompoundFarmStrategyStorage();
        StrategyBaseStorage storage _$_ = _getStrategyBaseStorage();
        IComet comet = $.comet;
        __assets = _$_._assets;
        __amounts = new uint[](1);
        __amounts[0] = comet.balanceOf(address(this)) - _$_.total;
        __rewardAssets = _getFarmingStrategyBaseStorage()._rewardAssets;
        __rewardAmounts = new uint[](1);
        $.cometRewards.claim(address(comet), address(this), true);
        __rewardAmounts[0] = StrategyLib.balance(__rewardAssets[0]);
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {
        CompoundFarmStrategyStorage storage $ = _getCompoundFarmStrategyStorage();
        StrategyBaseStorage storage _$_ = _getStrategyBaseStorage();
        IComet comet = $.comet;
        _$_.total = comet.balanceOf(address(this));
        uint[] memory amounts = new uint[](1);
        amounts[0] = StrategyLib.balance(_$_._assets[0]);
        _depositAssets(amounts, false);
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        pure
        override(StrategyBase)
        returns (uint[] memory amountsConsumed, uint value)
    {
        // todo check max deposit amount via IComet
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

    function _getCompoundFarmStrategyStorage() private pure returns (CompoundFarmStrategyStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := COMPOUNDFARMSTRATEGY_STORAGE_LOCATION
        }
    }

    function _genDesc(address comet) internal view returns (string memory) {
        return string.concat(
            "Earn COMP by supplying ", IERC20Metadata(IComet(comet).baseToken()).symbol(), " to Compound III"
        );
    }
}
