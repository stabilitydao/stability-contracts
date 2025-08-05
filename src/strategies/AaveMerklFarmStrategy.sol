// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {FarmingStrategyBase} from "./base/FarmingStrategyBase.sol";
import {IAToken} from "../integrations/aave/IAToken.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IFarmingStrategy} from "../interfaces/IFarmingStrategy.sol";
import {IMerklStrategy} from "../interfaces/IMerklStrategy.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IPool} from "../integrations/aave/IPool.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {IVault} from "../interfaces/IVault.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SharedLib} from "./libs/SharedLib.sol";
import {StrategyBase} from "./base/StrategyBase.sol";
import {MerklStrategyBase} from "./base/MerklStrategyBase.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {StrategyLib} from "./libs/StrategyLib.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";

/// @title Earns APR by lending assets on AAVE
/// Changelog:
///   1.0.0: initial release
/// @author dvpublic (https://github.com/dvpublic)
contract AaveMerklFarmStrategy is FarmingStrategyBase, MerklStrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.1.0"; // todo

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.AaveMerklFarmStrategy")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant AAVE_MERKL_FARM_STRATEGY_STORAGE_LOCATION =
        0x38e9b949b88cb4e4dbd7831dad2798de9f4727f749800ba055a2fba2077fec00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.AaveStrategy
    struct AaveMerklFarmStrategyStorage {
        uint lastSharePrice;
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
        if (farm.addresses.length != 1 || farm.nums.length != 0 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }

        address[] memory _assets = new address[](1);
        _assets[0] = IAToken(farm.addresses[0]).UNDERLYING_ASSET_ADDRESS();

        __StrategyBase_init(
            addresses[0],
            StrategyIdLib.AAVE_MERKL_FARM,
            addresses[1],
            _assets,
            address(0),
            0 // exchangeAssetIndex
        );
        __FarmingStrategyBase_init(addresses[0], nums[0]);

        IERC20(_assets[0]).forceApprove(IAToken(farm.addresses[0]).POOL(), type(uint).max);
    }

    function setUnderlying() external onlyOperator {
        // todo
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base._underlying = aaveToken();
    }

    //region ----------------------- View functions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(FarmingStrategyBase, MerklStrategyBase)
        returns (bool)
    {
        return interfaceId == type(IFarmingStrategy).interfaceId || interfaceId == type(IMerklStrategy).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.AAVE_MERKL_FARM;
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        return _generateDescription(aaveToken());
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        //slither-disable-next-line too-many-digits
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x00d395), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        address atoken = aaveToken();
        string memory shortAddr = SharedLib.shortAddress(IAToken(atoken).POOL());
        return (string.concat(IERC20Metadata(atoken).symbol(), " ", shortAddr), true);
    }

    /// @inheritdoc IStrategy
    function supportedVaultTypes() external pure override returns (string[] memory types) {
        types = new string[](1);
        types[0] = VaultTypeLib.COMPOUNDING;
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_)
        external
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        addresses = new address[](0);
        ticks = new int24[](0);
        IFactory.Farm[] memory farms = IFactory(IPlatform(platform_).factory()).farms();
        uint len = farms.length;
        //slither-disable-next-line uninitialized-local
        uint _total;
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = farms[i];
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, StrategyIdLib.AAVE_MERKL_FARM)) {
                ++_total;
            }
        }
        variants = new string[](_total);
        nums = new uint[](_total);
        _total = 0;
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = farms[i];
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, StrategyIdLib.AAVE_MERKL_FARM)) {
                nums[_total] = i;
                variants[_total] = _generateDescription(farm.addresses[0]);
                ++_total;
            }
        }
    }

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool) {
        return false;
    }

    /// @inheritdoc IStrategy
    function total() public view override returns (uint) {
        return StrategyLib.balance(aaveToken());
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() external pure override returns (uint[] memory proportions) {
        proportions = new uint[](1);
        proportions[0] = 1e18;
    }

    /// @inheritdoc IStrategy
    function getRevenue() public view override returns (address[] memory assets_, uint[] memory amounts) {
        address aToken = aaveToken();
        uint newPrice = _getSharePrice(aToken);
        (assets_, amounts) = _getRevenue(newPrice, aToken);
    }

    //    /// @inheritdoc IStrategy
    //    function autoCompoundingByUnderlyingProtocol() public pure override returns (bool) {
    //        return true;
    //    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external pure override returns (bool isReady) {
        isReady = true;
    }

    function aaveToken() public view returns (address) {
        return _getAToken(_getFarmingStrategyBaseStorage());
    }

    /// @inheritdoc IStrategy
    function poolTvl() public view override returns (uint tvlUsd) {
        address aToken = aaveToken();
        address asset = IAToken(aToken).UNDERLYING_ASSET_ADDRESS();

        IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());

        // get price of 1 amount of asset in USD with decimals 18
        // assume that {trusted} value doesn't matter here
        // slither-disable-next-line unused-return
        (uint price,) = priceReader.getPrice(asset);

        return IAToken(aToken).totalSupply() * price / (10 ** IERC20Metadata(asset).decimals());
    }

    /// @inheritdoc IStrategy
    function maxWithdrawAssets() public view override returns (uint[] memory amounts) {
        address aToken = aaveToken();
        address asset = IAToken(aToken).UNDERLYING_ASSET_ADDRESS();

        // currently available reserves in the pool
        uint availableLiquidity = IERC20(asset).balanceOf(aToken);

        // aToken balance of the strategy
        uint aTokenBalance = IERC20(aToken).balanceOf(address(this));

        amounts = new uint[](1);
        amounts[0] = Math.min(availableLiquidity, aTokenBalance);
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        assets_ = $base._assets;
        amounts_ = new uint[](1);
        amounts_[0] = StrategyLib.balance(aaveToken());
    }

    //endregion ----------------------- View functions

    //region ----------------------- Strategy base
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    //slither-disable-next-line unused-return
    function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
        AaveMerklFarmStrategyStorage storage $ = _getStorage();

        IAToken aToken = IAToken(aaveToken());
        address[] memory _assets = assets();

        value = amounts[0];
        if (value != 0) {
            IPool(aToken.POOL()).supply(_assets[0], amounts[0], address(this), 0);

            if ($.lastSharePrice == 0) {
                $.lastSharePrice = _getSharePrice(address(aToken));
            }
        }
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();

        return _withdrawAssets($base._assets, value, receiver);
    }

    /// @inheritdoc StrategyBase
    //slither-disable-next-line unused-return
    function _withdrawAssets(
        address[] memory,
        uint value,
        address receiver
    ) internal override returns (uint[] memory amountsOut) {
        amountsOut = new uint[](1);

        IAToken aToken = IAToken(aaveToken());
        address depositedAsset = aToken.UNDERLYING_ASSET_ADDRESS();

        address[] memory _assets = assets();

        uint initialValue = StrategyLib.balance(depositedAsset);
        IPool(aToken.POOL()).withdraw(_assets[0], value, address(this));
        amountsOut[0] = StrategyLib.balance(depositedAsset) - initialValue;

        IERC20(depositedAsset).safeTransfer(receiver, amountsOut[0]);
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        pure
        override
        returns (uint[] memory amountsConsumed, uint value)
    {
        amountsConsumed = new uint[](1);
        amountsConsumed[0] = amountsMax[0];
        value = amountsMax[0];
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(
        address[] memory, /*assets_*/
        uint[] memory amountsMax
    ) internal pure override returns (uint[] memory amountsConsumed, uint value) {
        return _previewDepositAssets(amountsMax);
    }

    /// @inheritdoc StrategyBase
    function _processRevenue(
        address[] memory, /*assets_*/
        uint[] memory /*amountsRemaining*/
    ) internal pure override returns (bool needCompound) {
        needCompound = true;
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
        AaveMerklFarmStrategyStorage storage $ = _getStorage();
        FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();

        address aToken = aaveToken();
        uint newPrice = _getSharePrice(aToken);
        (__assets, __amounts) = _getRevenue(newPrice, aToken);
        $.lastSharePrice = newPrice;

        // ---------------------- collect Merkl rewards
        __rewardAssets = $f._rewardAssets;
        uint rwLen = __rewardAssets.length;
        __rewardAmounts = new uint[](rwLen);
        for (uint i; i < rwLen; ++i) {
            // Reward asset can be equal to the borrow asset.
            // The borrow asset is never left on the balance, see _receiveFlashLoan().
            // So, any borrow asset on balance can be considered as a reward.
            __rewardAmounts[i] = StrategyLib.balance(__rewardAssets[i]);
        }

        // This strategy doesn't use $base.total at all
        // but StrategyBase expects it to be set in doHardWork in order to calculate aprCompound
        // so, we set it twice: here (old value) and in _compound (new value)
        $base.total = total();
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {
        address[] memory _assets = assets();
        uint len = _assets.length;
        uint[] memory amounts = new uint[](len);

        //slither-disable-next-line uninitialized-local
        bool notZero;

        for (uint i; i < len; ++i) {
            amounts[i] = StrategyLib.balance(_assets[i]);
            if (amounts[i] != 0) {
                notZero = true;
            }
        }
        if (notZero) {
            _depositAssets(amounts, false);
        }

        StrategyBaseStorage storage $base = _getStrategyBaseStorage();

        // This strategy doesn't use $base.total at all
        // but StrategyBase expects it to be set in doHardWork in order to calculate aprCompound
        // so, we set it twice: here (new value) and in _claimRevenue (old value)
        $base.total = total();
    }

    //endregion ----------------------- Strategy base

    //region ----------------------------------- FarmingStrategy
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     FARMING STRATEGY                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IFarmingStrategy
    function canFarm() external view override returns (bool) {
        IFactory.Farm memory farm = _getFarm();
        return farm.status == 0;
    }

    /// @inheritdoc IFarmingStrategy
    function farmMechanics() external pure returns (string memory) {
        return FarmMechanicsLib.MERKL;
    }

    //endregion ----------------------------------- FarmingStrategy

    //region ----------------------- Internal logic
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function _getStorage() internal pure returns (AaveMerklFarmStrategyStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := AAVE_MERKL_FARM_STRATEGY_STORAGE_LOCATION
        }
    }

    function _getSharePrice(address u) internal view returns (uint) {
        IAToken aToken = IAToken(u);
        uint scaledBalance = aToken.scaledTotalSupply();
        return scaledBalance == 0 ? 0 : aToken.totalSupply() * 1e18 / scaledBalance;
    }

    function _getRevenue(
        uint newPrice,
        address u
    ) internal view returns (address[] memory __assets, uint[] memory amounts) {
        AaveMerklFarmStrategyStorage storage $ = _getStorage();
        __assets = assets();
        amounts = new uint[](1);
        uint oldPrice = $.lastSharePrice;
        if (newPrice > oldPrice && oldPrice != 0) {
            // deposited asset balance
            uint scaledBalance = IAToken(u).scaledBalanceOf(address(this));

            // share price already takes into account accumulated interest
            amounts[0] = scaledBalance * (newPrice - oldPrice) / 1e18;
        }
    }

    function _generateDescription(address aToken) internal view returns (string memory) {
        //slither-disable-next-line calls-loop
        return string.concat(
            "Supply ",
            IERC20Metadata(IAToken(aToken).UNDERLYING_ASSET_ADDRESS()).symbol(),
            " to AAVE ",
            SharedLib.shortAddress(IAToken(aToken).POOL()),
            " with Merkl rewards"
        );
    }

    function _getAToken(FarmingStrategyBaseStorage storage $) internal view returns (address) {
        return _getFarm(platform(), $.farmId).addresses[0];
    }
    //endregion ----------------------- Internal logic
}
