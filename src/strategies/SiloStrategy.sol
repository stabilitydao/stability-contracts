// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC4626StrategyBase} from "./base/ERC4626StrategyBase.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {ISilo} from "../integrations/silo/ISilo.sol";
import {ISiloConfig} from "../integrations/silo/ISiloConfig.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {StrategyBase} from "./base/StrategyBase.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";

/// @notice SiloStrategy is a strategy for lending assets on Silo V2.
/// Changelog:
///     1.0.2: Use ERC4626StrategyBase 1.0.4 with fixed revenue formula - #304
///     1.0.1: _assetsAmounts uses previewRedeem to fix #300
/// @title Lend asset on Silo V2
/// @author 0xhokugava (https://github.com/0xhokugava)
/// @author dvpublic (https://github.com/dvpublic)
contract SiloStrategy is ERC4626StrategyBase {
    using SafeERC20 for IERC20;
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.2";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 3 || nums.length != 0 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }
        __ERC4626StrategyBase_init(StrategyIdLib.SILO, addresses[0], addresses[1], addresses[2]);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.SILO;
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x00d395), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        return _genDesc($base._underlying);
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        return (CommonLib.u2s(_getMarketId($base._underlying)), true);
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
            variants[i] = _genDesc(params.initAddresses[i]);
            addresses[i] = params.initAddresses[i];
        }
    }

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool) {
        return true;
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        assets_ = __$__._assets;
        address u = __$__._underlying;
        amounts_ = new uint[](1);

        // #300: _assetsAmounts is used to calculate prices and tvl
        // these values are used in withdraw to estimate how much shares to burn
        // convertToAssets in SilStrategy uses different rounding mode then previewRedeem
        // only previewRedeem gives correct value

        //amounts_[0] = IERC4626(u).convertToAssets(IERC20(u).balanceOf(address(this)));
        amounts_[0] = ISilo(u).previewRedeem(IERC20(u).balanceOf(address(this)));
    }

    /// @inheritdoc IStrategy
    function poolTvl() public view virtual override returns (uint tvlUsd) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        IERC4626 u = IERC4626(__$__._underlying);

        address asset = u.asset();
        IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());

        // get price of 1 amount of asset in USD with decimals 18
        // assume that {trusted} value doesn't matter here
        (uint price, ) = priceReader.getPrice(asset);

        return u.totalAssets() * price / (10**IERC20Metadata(asset).decimals());
    }

    /// @inheritdoc IStrategy
    function maxWithdrawAssets() public view override returns (uint[] memory amounts) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        IERC4626 u = IERC4626(__$__._underlying);
        amounts = new uint[](1);
        amounts[0] = u.maxWithdraw(address(this));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc ERC4626StrategyBase
    //slither-disable-next-line unused-return
    function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        address u = $base._underlying;
        ERC4626StrategyBaseStorage storage $ = _getERC4626StrategyBaseStorage();
        if ($.lastSharePrice == 0) {
            $.lastSharePrice = _getSharePrice(u);
        }
        ISilo siloVault = ISilo(u);
        value = siloVault.deposit(amounts[0], address(this), ISilo.CollateralType.Collateral);
    }

    /// @inheritdoc ERC4626StrategyBase
    //slither-disable-next-line unused-return
    function _withdrawAssets(
        address[] memory,
        uint value,
        address receiver
    ) internal virtual override returns (uint[] memory amountsOut) {
        amountsOut = new uint[](1);
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        ISilo silo = ISilo($base._underlying);
        amountsOut[0] = silo.redeem(value, receiver, address(this));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _genDesc(address silo) internal view returns (string memory) {
        return string.concat(
            "Earn by lending ",
            IERC20Metadata(ISilo(silo).asset()).symbol(),
            " to Silo V2 market with ID ",
            CommonLib.u2s(_getMarketId(silo))
        );
    }

    function _getMarketId(address _silo) internal view returns (uint marketId) {
        marketId = ISiloConfig(ISilo(_silo).config()).SILO_ID();
    }
}
