// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CommonLib} from "../core/libs/CommonLib.sol";
import {IComptroller} from "../integrations/compoundv2/IComptroller.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IVToken} from "../integrations/compoundv2/IVToken.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SharedLib} from "./libs/SharedLib.sol";
import {StrategyBase} from "./base/StrategyBase.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {StrategyLib} from "./libs/StrategyLib.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";

/// @title Earns APR by lending assets on Compound V2 protocol.
/// @author dvpublic (https://github.com/dvpublic)
/// Changelog:
///   1.0.1: StrategyBase 2.5.1
contract CompoundV2Strategy is StrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.1";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.CompoundV2Strategy")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant COMPOUND_V2_STRATEGY_STORAGE_LOCATION =
        0x521f61dff1434739ba1cce3408ca24814df0ac37d5c1f8d308e97ca6d9831800; // erc7201:stability.CompoundV2Strategy

    error MintError(uint errorCode);
    error RedeemError(uint errorCode);
    error AccrueInterestError(uint errorCode);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.CompoundV2Strategy
    struct CompoundV2StrategyStorage {
        uint lastSharePrice;
    }

    //region ----------------------- Initialization
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 3 || nums.length != 0 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }
        address[] memory _assets = new address[](1);
        _assets[0] = IVToken(addresses[2]).underlying();

        __StrategyBase_init(
            addresses[0], // platform
            StrategyIdLib.COMPOUND_V2,
            addresses[1], // vault
            _assets,
            addresses[2], // underlying
            type(uint).max
        );

        IERC20(_assets[0]).forceApprove(addresses[2], type(uint).max);
    }

    //endregion ----------------------- Initialization

    //region ----------------------- View functions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.COMPOUND_V2;
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        return _generateDescription(__$__._underlying);
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        //slither-disable-next-line too-many-digits
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x00d395), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        address _underlying = _getStrategyBaseStorage()._underlying;
        string memory shortAddr = SharedLib.shortAddress(_underlying);
        return (string.concat(IERC20Metadata(_underlying).symbol(), " ", shortAddr), true);
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
        IFactory.StrategyAvailableInitParams memory params = IFactory(IPlatform(platform_).factory())
            .strategyAvailableInitParams(keccak256(bytes(strategyLogicId())));
        uint len = params.initAddresses.length;
        variants = new string[](len);
        addresses = new address[](len);
        nums = new uint[](0);
        ticks = new int24[](0);
        for (uint i; i < len; ++i) {
            variants[i] = _generateDescription(params.initAddresses[i]);
            addresses[i] = params.initAddresses[i];
        }
    }

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function total() public view override returns (uint) {
        address _underlying = _getStrategyBaseStorage()._underlying;
        // total is a number of cTokens on the strategy balance
        // this number is changes on deposit/withdraw only
        return StrategyLib.balance(_underlying);
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() external pure override returns (uint[] memory proportions) {
        proportions = new uint[](1);
        proportions[0] = 1e18;
    }

    /// @inheritdoc IStrategy
    function getRevenue() public view override returns (address[] memory assets_, uint[] memory amounts) {
        address _underlying = _getStrategyBaseStorage()._underlying;
        uint newPrice = _getSharePrice(_underlying);
        (assets_, amounts) = _getRevenue(newPrice, _underlying);
    }

    /// @inheritdoc IStrategy
    function autoCompoundingByUnderlyingProtocol() public pure override returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external pure override returns (bool isReady) {
        isReady = true;
    }

    /// @inheritdoc IStrategy
    function poolTvl() public view override returns (uint tvlUsd) {
        address _underlying = _getStrategyBaseStorage()._underlying;
        address asset = IVToken(_underlying).underlying();

        IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());

        // get price of 1 amount of asset in USD with decimals 18
        // slither-disable-next-line unused-return
        (uint price,) = priceReader.getPrice(asset);
        uint totalSupply = IVToken(_underlying).totalSupply(); // 8 decimals
        uint exchangeRate = IVToken(_underlying).exchangeRateStored(); // underlying decimals * 1e18 / 1e8
        uint underlyingTotal = _tokensToAmount(totalSupply, exchangeRate);

        return underlyingTotal * price / (10 ** IERC20Metadata(asset).decimals());
    }

    /// @inheritdoc IStrategy
    function maxWithdrawAssets(uint mode) public view override returns (uint[] memory amounts) {
        address _underlying = _getStrategyBaseStorage()._underlying;
        address asset = IVToken(_underlying).underlying();

        // currently available liquidity in the pool
        uint availableLiquidity = IERC20(asset).balanceOf(_underlying);

        // balance of the strategy
        uint cTokenBalance = IVToken(_underlying).balanceOf(address(this)); // 8 decimals
        uint exchangeRate = IVToken(_underlying).exchangeRateStored(); // underlying decimals * 1e18 / 1e8
        uint underlyingBalance = _tokensToAmount(cTokenBalance, exchangeRate);

        amounts = new uint[](1);
        amounts[0] = mode == 0 ? Math.min(underlyingBalance, availableLiquidity) : underlyingBalance;
    }

    /// @notice IStrategy
    function maxDepositAssets() public view override returns (uint[] memory amounts) {
        address _underlying = _getStrategyBaseStorage()._underlying;
        uint supplyCap = IComptroller(IVToken(_underlying).comptroller()).supplyCaps(_underlying);
        if (supplyCap != type(uint).max) {
            uint vTokenSupply = IVToken(_underlying).totalSupply();
            uint totalSupply = _tokensToAmount(vTokenSupply, IVToken(_underlying).exchangeRateStored());

            amounts = new uint[](1);
            amounts[0] = supplyCap > totalSupply
                ? (supplyCap - totalSupply) * 99_9 / 100_0  // 99.9% of the supply cap
                : 0;
        }

        return amounts;
    }

    //endregion ----------------------- View functions

    //region ----------------------- Strategy base
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    //slither-disable-next-line unused-return
    function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
        CompoundV2StrategyStorage storage $ = _getStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        IVToken _market = IVToken($base._underlying);

        uint cTokenBalanceBefore = StrategyLib.balance(address(_market));
        if (amounts[0] != 0) {
            uint errorCode = _market.mint(amounts[0]);
            require(errorCode == 0, MintError(errorCode));

            // value is amount of minted cTokens
            value = StrategyLib.balance(address(_market)) - cTokenBalanceBefore;

            if ($.lastSharePrice == 0) {
                $.lastSharePrice = _getSharePrice(address(_market));
            }
        }

        return value;
    }

    /// @inheritdoc StrategyBase
    function _liquidateRewards(
        address, /*exchangeAsset*/
        address[] memory, /*rewardAssets_*/
        uint[] memory /*rewardAmounts_*/
    ) internal override returns (uint earnedExchangeAsset) {
        // do nothing
    }

    /// @inheritdoc StrategyBase
    function _processRevenue(
        address[] memory, /*assets_*/
        uint[] memory /*amountsRemaining*/
    ) internal override returns (bool needCompound) {
        // do nothing
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {
        // do nothing
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        view
        override
        returns (uint[] memory amountsConsumed, uint value)
    {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        amountsConsumed = new uint[](1);
        amountsConsumed[0] = amountsMax[0];
        value = _amountToTokens(amountsMax[0], IVToken($base._underlying).exchangeRateStored());
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(
        address[] memory, /*assets_*/
        uint[] memory amountsMax
    ) internal view override returns (uint[] memory amountsConsumed, uint value) {
        return _previewDepositAssets(amountsMax);
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

        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        IVToken _market = IVToken(__$__._underlying);
        address depositedAsset = _market.underlying();

        uint initialValue = StrategyLib.balance(depositedAsset);
        uint errorCode = _market.redeem(value);
        require(errorCode == 0, RedeemError(errorCode));
        amountsOut[0] = StrategyLib.balance(depositedAsset) - initialValue;

        IERC20(depositedAsset).safeTransfer(receiver, amountsOut[0]);
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();

        assets_ = $base._assets;

        amounts_ = new uint[](1);
        amounts_[0] =
            _tokensToAmount(StrategyLib.balance($base._underlying), IVToken($base._underlying).exchangeRateStored());
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
        CompoundV2StrategyStorage storage $ = _getStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        address market = $base._underlying;

        uint errorCode = IVToken(market).accrueInterest();
        require(errorCode == 0, AccrueInterestError(errorCode));

        uint newPrice = _getSharePrice(market);
        (__assets, __amounts) = _getRevenue(newPrice, market);
        $.lastSharePrice = newPrice;

        __rewardAssets = new address[](0);
        __rewardAmounts = new uint[](0);
    }

    /// @inheritdoc StrategyBase
    function _depositUnderlying(uint amount) internal override returns (uint[] memory amountsConsumed) {
        CompoundV2StrategyStorage storage $ = _getStorage();
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();

        amountsConsumed = _previewDepositUnderlying(amount);

        if ($.lastSharePrice == 0) {
            $.lastSharePrice = _getSharePrice(__$__._underlying);
        }
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        IERC20(__$__._underlying).safeTransfer(receiver, amount);
    }

    function _previewDepositUnderlying(uint amount) internal view override returns (uint[] memory amountsConsumed) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        amountsConsumed = new uint[](1);
        amountsConsumed[0] = _tokensToAmount(amount, IVToken($base._underlying).exchangeRateStored());
    }

    //endregion ----------------------- Strategy base

    //region ----------------------- Internal logic
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function _getStorage() internal pure returns (CompoundV2StrategyStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := COMPOUND_V2_STRATEGY_STORAGE_LOCATION
        }
    }

    function _getSharePrice(address u) internal view returns (uint) {
        return IVToken(u).exchangeRateStored();
    }

    function _getRevenue(
        uint newPrice,
        address u
    ) internal view returns (address[] memory __assets, uint[] memory amounts) {
        CompoundV2StrategyStorage storage $ = _getStorage();
        __assets = assets();
        amounts = new uint[](1);
        uint oldPrice = $.lastSharePrice;
        if (newPrice > oldPrice && oldPrice != 0) {
            // deposited asset balance
            uint userBalanceCTokens = IVToken(u).balanceOf(address(this));

            // share price already takes into account accumulated interest
            amounts[0] = _tokensToAmount(userBalanceCTokens, (newPrice - oldPrice));
        }
    }

    function _generateDescription(address market_) internal view returns (string memory) {
        //slither-disable-next-line calls-loop
        return string.concat(
            "Supply ",
            IERC20Metadata(IVToken(market_).underlying()).symbol(),
            " to ",
            IVToken(market_).name(),
            SharedLib.shortAddress(market_)
        );
    }

    /// @param exchangeRate The exchange rate of cTokens to underlying asset = underlying decimals * 1e18 / 1e8
    function _tokensToAmount(uint cTokens, uint exchangeRate) internal pure returns (uint amount) {
        return cTokens * exchangeRate / 1e18;
    }

    function _amountToTokens(uint amount, uint exchangeRate) internal pure returns (uint cTokens) {
        return amount * 1e18 / exchangeRate;
    }
    //endregion ----------------------- Internal logic
}
