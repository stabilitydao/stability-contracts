// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {IVault} from "../interfaces/IVault.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StrategyBase} from "./base/StrategyBase.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {StrategyLib} from "./libs/StrategyLib.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";
import {IVToken} from "../integrations/compoundv2/IVToken.sol";
import {SharedLib} from "./libs/SharedLib.sol";

/// @title Earns APR by lending assets on Compound V2 protocol.
/// @author dvpublic (https://github.com/dvpublic)
contract CompoundV2Strategy is StrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.CompoundV2Strategy")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant COMPOUND_V2_STRATEGY_STORAGE_LOCATION =
        0x521f61dff1434739ba1cce3408ca24814df0ac37d5c1f8d308e97ca6d9831800; // erc7201:stability.CompoundV2Strategy

    error MintError(uint errorCode);
    error RedeemError(uint errorCode);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.CompoundV2Strategy
    struct CompoundV2StrategyStorage {
        uint lastSharePrice;
        address market;
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
            address(0), // underlying
            type(uint).max
        );
        _getStorage().market = addresses[2]; // todo: try to use market as underlying

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
        CompoundV2StrategyStorage storage $ = _getStorage();
        return _generateDescription($.market);
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        //slither-disable-next-line too-many-digits
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x00d395), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        CompoundV2StrategyStorage storage $ = _getStorage();
        address _market = $.market;
        string memory shortAddr = SharedLib.shortAddress(_market);
        return (string.concat(IERC20Metadata(_market).symbol(), " ", shortAddr), true);
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
        IFactory.StrategyAvailableInitParams memory params =
            IFactory(IPlatform(platform_).factory()).strategyAvailableInitParams(keccak256(bytes(strategyLogicId())));
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
        CompoundV2StrategyStorage storage $ = _getStorage();
        // total is a number of cTokens on the strategy balance
        // this number is changes on deposit/withdraw only
        return StrategyLib.balance($.market);
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() external pure override returns (uint[] memory proportions) {
        proportions = new uint[](1);
        proportions[0] = 1e18;
    }

    /// @inheritdoc IStrategy
    function getRevenue() public view override returns (address[] memory assets_, uint[] memory amounts) {
        CompoundV2StrategyStorage storage $ = _getStorage();
        address _market = $.market;
        uint newPrice = _getSharePrice(_market);
        (assets_, amounts) = _getRevenue(newPrice, _market);
    }

    /// @inheritdoc IStrategy
    function autoCompoundingByUnderlyingProtocol() public pure override returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external pure override returns (bool isReady) {
        isReady = true;
    }

    function market() external view returns (address) {
        return _getStorage().market;
    }

    /// @inheritdoc IStrategy
    function poolTvl() public view override returns (uint tvlUsd) {
        console.log("!!!!!!!!!!! poolTvl");
        address _market = _getStorage().market;
        address asset = IVToken(_market).underlying();

        IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());

        // get price of 1 amount of asset in USD with decimals 18
        // slither-disable-next-line unused-return
        (uint price,) = priceReader.getPrice(asset);
        uint totalSupply = IVToken(_market).totalSupply(); // 8 decimals
        uint exchangeRate = IVToken(_market).exchangeRateStored(); // underlying decimals * 1e18 / 1e8
        uint underlyingTotal = _convertCTokensToAmount(totalSupply, exchangeRate);

        return underlyingTotal * price / (10 ** IERC20Metadata(asset).decimals());
    }

    /// @inheritdoc IStrategy
    function maxWithdrawAssets() public view override returns (uint[] memory amounts) {
        console.log("!!!!!!!!!!! maxWithdrawAssets");
        address _market = _getStorage().market;
        address asset = IVToken(_market).underlying();

        // currently available liquidity in the pool
        uint availableLiquidity = IERC20(asset).balanceOf(_market);

        // balance of the strategy
        uint cTokenBalance = IVToken(_market).balanceOf(address(this)); // 8 decimals
        uint exchangeRate = IVToken(_market).exchangeRateStored(); // underlying decimals * 1e18 / 1e8
        uint underlyingBalance = _convertCTokensToAmount(cTokenBalance, exchangeRate);

        amounts = new uint[](1);
        amounts[0] = Math.min(underlyingBalance, availableLiquidity);
    }
    //endregion ----------------------- View functions

    //region ----------------------- Strategy base
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    //slither-disable-next-line unused-return
    function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
        console.log("!!!!!!!!!!! deposit", amounts[0]);
        CompoundV2StrategyStorage storage $ = _getStorage();

        IVToken _market = IVToken($.market);
        value = amounts[0];


        uint cTokenBalanceBefore = StrategyLib.balance(address(_market));
        if (amounts[0] != 0) {
            uint errorCode = _market.mint(amounts[0]);
            require(errorCode == 0, MintError(errorCode));

            value = StrategyLib.balance(address(_market)) - cTokenBalanceBefore;

            if ($.lastSharePrice == 0) {
                $.lastSharePrice = _getSharePrice(address(_market));
            }
        }
        console.log("Deposit value, amount", value, amounts[0]);
        console.log("Balance after mint:", StrategyLib.balance(address(_market)));
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
        console.log("!!!!!!!!!!! _previewDepositAssets");
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
        console.log("!!!!!!!!!!! _withdrawAssets", value);
        amountsOut = new uint[](1);

        CompoundV2StrategyStorage storage $ = _getStorage();
        IVToken _market = IVToken($.market);
        address depositedAsset = _market.underlying();

        console.log("balance before redeem:", StrategyLib.balance(address(_market)));
        console.log("value to redeem:", value);
        uint initialValue = StrategyLib.balance(depositedAsset);
        uint errorCode = _market.redeem(value);
        require(errorCode == 0, RedeemError(errorCode));
        amountsOut[0] = StrategyLib.balance(depositedAsset) - initialValue;
        console.log("balance after redeem:", StrategyLib.balance(address(_market)));
        console.log("amountsOut[0]:", amountsOut[0]);

        IERC20(depositedAsset).safeTransfer(receiver, amountsOut[0]);
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        console.log("!!!!!!!!!!! _assetsAmounts");
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        CompoundV2StrategyStorage storage $ = _getStorage();

        assets_ = $base._assets;

        amounts_ = new uint[](1);
        amounts_[0] = _convertCTokensToAmount(StrategyLib.balance($.market), IVToken($.market).exchangeRateStored());
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
        console.log("!!!!!!!!!!! _claimRevenue");
        CompoundV2StrategyStorage storage $ = _getStorage();

        uint newPrice = _getSharePrice($.market);
        (__assets, __amounts) = _getRevenue(newPrice, $.market);
        $.lastSharePrice = newPrice;

        __rewardAssets = new address[](0);
        __rewardAmounts = new uint[](0);
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
        console.log("!!!!!!!!!!! _getRevenue");
        CompoundV2StrategyStorage storage $ = _getStorage();
        __assets = assets();
        amounts = new uint[](1);
        uint oldPrice = $.lastSharePrice;
        if (newPrice > oldPrice && oldPrice != 0) {
            // deposited asset balance
            uint userBalance = IVToken(u).balanceOf(address(this));

            // share price already takes into account accumulated interest
            amounts[0] = userBalance * (newPrice - oldPrice) / 1e18;
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
    function _convertCTokensToAmount(uint cTokens, uint exchangeRate) internal pure returns (uint amount) {
        return cTokens * exchangeRate / 1e18;
    }
    //endregion ----------------------- Internal logic
}
