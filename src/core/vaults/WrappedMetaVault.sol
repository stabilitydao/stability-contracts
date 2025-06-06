// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    ERC4626Upgradeable,
    IERC4626,
    IERC20,
    IERC20Metadata
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Controllable, IControllable} from "../base/Controllable.sol";
import {IWrappedMetaVault} from "../../interfaces/IWrappedMetaVault.sol";
import {CommonLib} from "../libs/CommonLib.sol";
import {IStabilityVault} from "../../interfaces/IStabilityVault.sol";
import {VaultTypeLib} from "../libs/VaultTypeLib.sol";
import {IMetaVault} from "../../interfaces/IMetaVault.sol";

/// @title Wrapped rebase MetaVault
/// Changelog:
///   1.1.0: add deposit/mint/withdraw/redeem with slippage protection - #306
///   1.0.2: withdraw sends to receiver exact requested amount, not more; mulDiv is used - #300.
///   1.0.1: fix withdraw to pass Balancer ERC4626 test
/// @author Alien Deployer (https://github.com/a17)
/// @author dvpublic (https://github.com/dvpublic)
contract WrappedMetaVault is Controllable, ERC4626Upgradeable, IWrappedMetaVault {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.1.0"; // todo PR

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.WrappedMetaVault")) - 1)) & ~bytes32(uint(0xff));
    bytes32 private constant _WRAPPED_METAVAULT_STORAGE_LOCATION =
        0xf43f9113ffe60414568925ff5214c308a4f0d31cac6adbb67396dfc55ceb9700;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IWrappedMetaVault
    function initialize(address platform_, address metaVault_) public initializer {
        WrappedMetaVaultStorage storage $ = _getWrappedMetaVaultStorage();
        bool _isMulti = CommonLib.eq(IStabilityVault(metaVault_).vaultType(), VaultTypeLib.MULTIVAULT);
        $.metaVault = metaVault_;
        $.isMulti = _isMulti;
        address _asset = _isMulti ? IStabilityVault(metaVault_).assets()[0] : metaVault_;
        __Controllable_init(platform_);
        __ERC4626_init(IERC20(_asset));
        __ERC20_init(
            string.concat("Wrapped ", IERC20Metadata(metaVault_).name()),
            string.concat("w", IERC20Metadata(metaVault_).symbol())
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IWrappedMetaVault
    function metaVault() external view returns (address) {
        return _getWrappedMetaVaultStorage().metaVault;
    }

    /// @inheritdoc IERC4626
    function totalAssets() public view override(ERC4626Upgradeable, IERC4626) returns (uint) {
        WrappedMetaVaultStorage storage $ = _getWrappedMetaVaultStorage();
        if ($.isMulti) {
            uint decimalsOffset = 10 ** (18 - decimals());
            return Math.mulDiv(IMetaVault($.metaVault).balanceOf(address(this)), 1, decimalsOffset, Math.Rounding.Floor);
        }
        return super.totalAssets();
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address owner) public view override(ERC4626Upgradeable, IERC4626) returns (uint maxShares) {
        WrappedMetaVaultStorage storage $ = _getWrappedMetaVaultStorage();
        uint maxUserShares = super.maxRedeem(owner);
        if ($.isMulti) {
            uint maxVaultWithdrawAmountTx = IMetaVault($.metaVault).maxWithdrawAmountTx();
            uint decimalsOffset = 10 ** (18 - IERC20Metadata(asset()).decimals());
            maxVaultWithdrawAmountTx = Math.mulDiv(maxVaultWithdrawAmountTx, 1, decimalsOffset, Math.Rounding.Floor);
            uint maxVaultWithdrawShares = convertToShares(maxVaultWithdrawAmountTx);
            maxShares = Math.min(maxUserShares, maxVaultWithdrawShares);
        } else {
            maxShares = maxUserShares;
        }
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address owner) public view override(ERC4626Upgradeable, IERC4626) returns (uint) {
        WrappedMetaVaultStorage storage $ = _getWrappedMetaVaultStorage();
        uint maxUserWithdraw = super.maxWithdraw(owner);
        if ($.isMulti) {
            uint maxVaultWithdrawAmountTx = IMetaVault($.metaVault).maxWithdrawAmountTx();
            uint decimalsOffset = 10 ** (18 - IERC20Metadata(asset()).decimals());
            maxVaultWithdrawAmountTx = Math.mulDiv(maxVaultWithdrawAmountTx, 1, decimalsOffset, Math.Rounding.Floor);
            return Math.min(maxUserWithdraw, maxVaultWithdrawAmountTx);
        }
        return maxUserWithdraw;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ERC4626 HOOKS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _deposit(address caller, address receiver, uint assets, uint shares) internal override {
        WrappedMetaVaultStorage storage $ = _getWrappedMetaVaultStorage();
        if ($.isMulti) {
            address _metaVault = $.metaVault;
            address[] memory _assets = new address[](1);
            _assets[0] = asset();
            uint[] memory amountsMax = new uint[](1);
            amountsMax[0] = assets;
            IERC20(_assets[0]).safeTransferFrom(caller, address(this), assets);
            _mint(receiver, shares);
            IERC20(_assets[0]).forceApprove(_metaVault, assets);
            IStabilityVault(_metaVault).depositAssets(_assets, amountsMax, 0, address(this));
            emit Deposit(caller, receiver, assets, shares);
        } else {
            super._deposit(caller, receiver, assets, shares);
        }
    }

    function _withdraw(address caller, address receiver, address owner, uint assets, uint shares) internal override {
        WrappedMetaVaultStorage storage $ = _getWrappedMetaVaultStorage();

        if ($.isMulti) {
            if (caller != owner) {
                _spendAllowance(owner, caller, shares);
            }

            address[] memory _assets = new address[](1);
            _assets[0] = asset();

            uint balanceBefore = IERC20(_assets[0]).balanceOf(address(this));

            IStabilityVault($.metaVault).withdrawAssets(
                _assets,
                assets * 10 ** (18 - IERC20Metadata(_assets[0]).decimals()),
                new uint[](1),
                address(this), // withdraw to this contract
                address(this)
            );

            _burn(owner, shares);

            // in some cases we can receive more than requested
            // but we should send ony requested amount to receiver
            uint balanceAfter = IERC20(_assets[0]).balanceOf(address(this));
            uint assetsToSend = Math.min(balanceAfter - balanceBefore, assets);
            SafeERC20.safeTransfer(IERC20(_assets[0]), receiver, assetsToSend);

            emit Withdraw(caller, receiver, owner, assets, shares);
        } else {
            super._withdraw(caller, receiver, owner, assets, shares);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*               deposit/withdraw with slippage               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IWrappedMetaVault
    function deposit(uint assets, address receiver, uint minShares) public virtual returns (uint) {
        uint shares = deposit(assets, receiver);
        require(shares > minShares, Slippage(shares, minShares));
        return shares;
    }

    /// @inheritdoc IWrappedMetaVault
    function mint(uint shares, address receiver, uint maxAssets) public virtual returns (uint) {
        uint assets = mint(shares, receiver);
        require(assets < maxAssets, Slippage(assets, maxAssets));
        return assets;
    }

    /// @inheritdoc IWrappedMetaVault
    function withdraw(uint assets, address receiver, address owner, uint maxShares) public virtual returns (uint) {
        uint shares = withdraw(assets, receiver, owner);
        require(shares < maxShares, Slippage(shares, maxShares));
        return shares;
    }

    /// @inheritdoc IWrappedMetaVault
    function redeem(uint shares, address receiver, address owner, uint minAssets) public virtual returns (uint) {
        uint assets = redeem(shares, receiver, owner);
        require(assets > minAssets, Slippage(assets, minAssets));
        return assets;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getWrappedMetaVaultStorage() internal pure returns (WrappedMetaVaultStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _WRAPPED_METAVAULT_STORAGE_LOCATION
        }
    }
}
