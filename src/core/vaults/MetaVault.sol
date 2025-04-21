// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Upgradeable, IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Controllable, IControllable} from "../base/Controllable.sol";
import {IMetaVault, IStabilityVault, EnumerableSet} from "../../interfaces/IMetaVault.sol";
import {VaultTypeLib} from "../libs/VaultTypeLib.sol";
import {IPriceReader} from "../../interfaces/IPriceReader.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IVault, IStrategy} from "../../interfaces/IVault.sol";

/// @title Stability MetaVault implementation
/// @dev Rebase vault that deposit to other vaults
/// @author Alien Deployer (https://github.com/a17)
contract MetaVault is Controllable, ReentrancyGuardUpgradeable, IERC20Errors, IMetaVault {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.MetaVault")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant _METAVAULT_STORAGE_LOCATION =
        0x303154e675d2f93642b6b4ae068c749c9b8a57de9202c6344dbbb24ab936f000;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMetaVault
    function initialize(
        address platform_,
        address pegAsset_,
        string memory name_,
        string memory symbol_,
        address[] memory vaults_,
        uint[] memory proportions_
    ) public initializer {
        __Controllable_init(platform_);
        __ReentrancyGuard_init();
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        $.vaults = vaults_;
        uint len = vaults_.length;
        EnumerableSet.AddressSet storage _assets = $.assets;
        for (uint i; i < len; ++i) {
            IStrategy strategy = IVault(vaults_[i]).strategy();
            address[] memory __assets = strategy.assets();
            uint assetsLength = __assets.length;
            for (uint k; k < assetsLength; ++k) {
                _assets.add(__assets[k]);
            }
        }
        $.targetProportions = proportions_;
        $.pegAsset = pegAsset_;
        $.name = name_;
        $.symbol = symbol_;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMetaVault
    function rebalance(
        uint[] memory withdrawAmounts,
        uint[] memory depositAmounts
    ) external returns (uint proportions, uint cost) {
        // todo
    }

    /// @inheritdoc IMetaVault
    function addVault(address vault, uint[] memory newTargetProportions) external {
        // todo
    }

    /// @inheritdoc IStabilityVault
    function setName(string calldata newName) external onlyOperator {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        $.name = newName;
        emit VaultName(newName);
    }

    /// @inheritdoc IStabilityVault
    function setSymbol(string calldata newSymbol) external onlyOperator {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        $.symbol = newSymbol;
        emit VaultSymbol(newSymbol);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStabilityVault
    function depositAssets(
        address[] memory assets_,
        uint[] memory amountsMax,
        uint minSharesOut,
        address receiver
    ) external virtual nonReentrant {
        // todo deposit to target vault
    }

    /// @inheritdoc IStabilityVault
    function withdrawAssets(
        address[] memory assets_,
        uint amountShares,
        uint[] memory minAssetAmountsOut
    ) external virtual nonReentrant returns (uint[] memory) {
        // todo
    }

    /// @inheritdoc IStabilityVault
    function withdrawAssets(
        address[] memory assets_,
        uint amountShares,
        uint[] memory minAssetAmountsOut,
        address receiver,
        address owner
    ) external virtual nonReentrant returns (uint[] memory) {}

    /// @inheritdoc IERC20
    function approve(address spender, uint amount) external returns (bool) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        $.allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @inheritdoc IERC20
    function transfer(address to, uint amount) external returns (bool) {
        transferFrom(msg.sender, to, amount);
        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint amount) public returns (bool) {
        require(to != address(0), ERC20InvalidReceiver(to));
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        _spendAllowanceOrBlock(from, msg.sender, amount);
        uint shareTransfer = _amountToShares(amount, $.totalShares, totalSupply());
        $.shareBalance[from] -= shareTransfer;
        $.shareBalance[to] += shareTransfer;

        // todo flash loan defence

        emit Transfer(from, to, amount);
        return true;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMetaVault
    function assets() external view returns (address[] memory) {
        return _getMetaVaultStorage().assets.values();
    }

    /// @inheritdoc IMetaVault
    function currentProportions() public view returns (uint[] memory proportions) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        address[] memory _vaults = $.vaults;
        if ($.totalShares == 0) {
            return targetProportions();
        }
        uint len = _vaults.length;
        proportions = new uint[](len);
        uint[] memory vaultUsdValue = new uint[](len);
        uint totalTvl;
        for (uint i; i < len; ++i) {
            (uint vaultTvl,) = IStabilityVault(_vaults[i]).tvl();
            totalTvl += vaultTvl;
            uint vaultSharesBalance = IERC20(_vaults[i]).balanceOf(address(this));
            uint vaultTotalSupply = IERC20(_vaults[i]).totalSupply();
            vaultUsdValue[i] = vaultSharesBalance * vaultTvl / vaultTotalSupply;
        }
        for (uint i; i < len; ++i) {
            proportions[i] = vaultUsdValue[i] * 1e18 / totalTvl;
        }
    }

    /// @inheritdoc IMetaVault
    function targetProportions() public view returns (uint[] memory) {
        return _getMetaVaultStorage().targetProportions;
    }

    /// @inheritdoc IMetaVault
    function targetVault() public view returns (address target) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        address[] memory _vaults = $.vaults;
        if ($.totalShares == 0) {
            return _vaults[0];
        }
        uint len = _vaults.length;
        uint[] memory _proportions = currentProportions();
        uint[] memory _targetProportions = targetProportions();
        uint lowProportionDiff;
        target = _vaults[0];
        for (uint i; i < len; ++i) {
            if (_proportions[i] < _targetProportions[i]) {
                uint diff = _targetProportions[i] - _proportions[i];
                if (diff > lowProportionDiff) {
                    lowProportionDiff = diff;
                    target = _vaults[i];
                }
            }
        }
    }

    /// @inheritdoc IMetaVault
    function pegAsset() external view returns (address) {
        return _getMetaVaultStorage().pegAsset;
    }

    /// @inheritdoc IMetaVault
    function vaults() external view returns (address[] memory) {
        return _getMetaVaultStorage().vaults;
    }

    /// @inheritdoc IStabilityVault
    function vaultType() external pure returns (string memory) {
        return VaultTypeLib.METAVAULT;
    }

    /// @inheritdoc IStabilityVault
    function previewDepositAssets(
        address[] memory assets_,
        uint[] memory amountsMax
    ) external view returns (uint[] memory amountsConsumed, uint sharesOut, uint valueOut) {
        // todo
    }

    /// @inheritdoc IStabilityVault
    function price() public view returns (uint price_, bool trusted_) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        address _pegAsset = $.pegAsset;
        if (_pegAsset == address(0)) {
            return (1e18, true);
        }
        return IPriceReader(IPlatform(platform()).priceReader()).getPrice(_pegAsset);
    }

    /// @inheritdoc IStabilityVault
    function tvl() public view returns (uint tvl_, bool trusted_) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        address[] memory _vaults = $.vaults;
        uint len = _vaults.length;
        for (uint i; i < len; ++i) {
            (uint vaultTvl,) = IStabilityVault(_vaults[i]).tvl();
            uint vaultSharesBalance = IERC20(_vaults[i]).balanceOf(address(this));
            uint vaultTotalSupply = IERC20(_vaults[i]).totalSupply();
            tvl_ += vaultSharesBalance * vaultTvl / vaultTotalSupply;
        }
        address[] memory _assets = $.assets.values();
        len = _assets.length;
        uint[] memory assetsOnBalance = new uint[](len);
        for (uint i; i < len; ++i) {
            assetsOnBalance[i] = IERC20(_assets[i]).balanceOf(address(this));
        }
        (uint assetsTvlUsd,,,) =
            IPriceReader(IPlatform(platform()).priceReader()).getAssetsPrice(_assets, assetsOnBalance);
        tvl_ += assetsTvlUsd;
        trusted_ = true;
    }

    /// @inheritdoc IERC20
    function totalSupply() public view returns (uint _tvl) {
        // totalSupply is balance of peg asset
        (uint tvlUsd,) = tvl();
        (uint priceAsset,) = price();
        return tvlUsd * 1e18 / priceAsset;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view returns (uint) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        uint _totalShares = $.totalShares;
        if (_totalShares == 0) {
            return 0;
        }
        return $.shareBalance[account] * totalSupply() / _totalShares;
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) external view returns (uint) {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        return $.allowance[owner][spender];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _amountToShares(uint amount, uint totalShares_, uint totalSupply_) public pure returns (uint) {
        if (totalSupply_ == 0) {
            return 0;
        }
        return amount * totalShares_ / totalSupply_;
    }

    function _spendAllowanceOrBlock(address owner, address spender, uint amount) internal {
        MetaVaultStorage storage $ = _getMetaVaultStorage();
        uint currentAllowance = $.allowance[owner][spender];
        if (owner != msg.sender && currentAllowance != type(uint).max) {
            require(currentAllowance >= amount, ERC20InsufficientAllowance(spender, currentAllowance, amount));
            $.allowance[owner][spender] = currentAllowance - amount;
        }
    }

    function _getMetaVaultStorage() internal pure returns (MetaVaultStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _METAVAULT_STORAGE_LOCATION
        }
    }
}
