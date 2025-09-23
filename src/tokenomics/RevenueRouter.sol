// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./libs/RevenueRouterLib.sol";
import {Controllable, IControllable} from "../core/base/Controllable.sol";
import {IAToken} from "../integrations/aave/IAToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IFeeTreasury} from "../interfaces/IFeeTreasury.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IPool} from "../integrations/aave/IPool.sol";
import {IRevenueRouter, EnumerableSet} from "../interfaces/IRevenueRouter.sol";
import {IStabilityVault} from "../interfaces/IStabilityVault.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {IXSTBL} from "../interfaces/IXSTBL.sol";
import {IXStaking} from "../interfaces/IXStaking.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Platform revenue distributor
/// Changelog:
///   1.5.0: processAccumulatedVaults
///   1.4.0: processUnitRevenue use try..catch for Aave aToken withdrawals; view vaultsAccumulated
///   1.3.0: vaultsAccumulated; updateUnit; units
///   1.2.0: Units; Aave unit; all revenue via buy-back
/// @author Alien Deployer (https://github.com/a17)
contract RevenueRouter is Controllable, IRevenueRouter {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.5.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.RevenueRouter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant REVENUE_ROUTER_STORAGE_LOCATION =
        0x052d2762d037d7d0dd41be56f750d8d5de9f07d940d686a3b9365e8e49143600;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(address platform_, address xStbl_, address feeTreasury_) external initializer {
        __Controllable_init(platform_);
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        if (xStbl_ != address(0)) {
            $.stbl = IXSTBL(xStbl_).STBL();
            $.xStbl = xStbl_;
            $.xStaking = IXSTBL(xStbl_).xStaking();
            $.xShare = 50;
        }
        $.feeTreasury = feeTreasury_;
        $.activePeriod = getPeriod();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        GOV ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRevenueRouter
    function addUnit(UnitType unitType, string calldata name, address feeTreasury) external onlyGovernanceOrMultisig {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        uint unitIndex = $.units.length;
        $.units.push(Unit({unitType: unitType, name: name, pendingRevenue: 0, feeTreasury: feeTreasury}));
        emit AddedUnit(unitIndex, unitType, name, feeTreasury);
    }

    /// @inheritdoc IRevenueRouter
    function updateUnit(
        uint unitIndex,
        UnitType unitType,
        string calldata name,
        address feeTreasury
    ) external onlyGovernanceOrMultisig {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        $.units[unitIndex].unitType = unitType;
        $.units[unitIndex].name = name;
        $.units[unitIndex].feeTreasury = feeTreasury;
        emit UpdatedUnit(unitIndex, unitType, name, feeTreasury);
    }

    /// @inheritdoc IRevenueRouter
    function setAavePools(address[] calldata pools) external onlyGovernanceOrMultisig {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        $.aavePools = pools;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRevenueRouter
    function updatePeriod() external returns (uint newPeriod) {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        uint _activePeriod = getPeriod();
        require($.activePeriod < _activePeriod, WaitForNewPeriod());
        $.activePeriod = _activePeriod;
        newPeriod = _activePeriod;
        uint periodEnded = newPeriod - 1;
        address _xstbl = $.xStbl;
        if (_xstbl != address(0)) {
            // process PvP rewards (100% xSTBL exit fees)
            IXSTBL(_xstbl).rebase();

            // process core Unit revenue
            uint _pendingRevenue = $.pendingRevenue;
            $.pendingRevenue = 0;
            emit UnitEpochRevenue(periodEnded, "Core", _pendingRevenue);

            // process other Units revenue
            uint len = $.units.length;
            for (uint i; i < len; ++i) {
                uint unitRevenue = $.units[i].pendingRevenue;
                _pendingRevenue += unitRevenue;
                $.units[i].pendingRevenue = 0;
                emit UnitEpochRevenue(periodEnded, $.units[i].name, unitRevenue);
            }

            // put week rewards to XStaking users
            if (_pendingRevenue != 0) {
                address _xStaking = $.xStaking;
                IERC20($.stbl).approve(_xStaking, _pendingRevenue);
                IXStaking(_xStaking).notifyRewardAmount(_pendingRevenue);
            }

            emit EpochFlip(periodEnded, _pendingRevenue);
        }
    }

    /// @inheritdoc IRevenueRouter
    function processFeeAsset(address asset, uint amount) external {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        address stbl = $.stbl;
        address feeTreasury = $.feeTreasury;
        if (stbl != address(0)) {
            uint stblBalanceWas = IERC20(stbl).balanceOf(address(this));
            ISwapper swapper = ISwapper(IPlatform(platform()).swapper());
            uint threshold = swapper.threshold(asset);
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
            if (amount > threshold) {
                if (asset != stbl) {
                    uint amountToSwap = IERC20(asset).balanceOf(address(this));
                    IERC20(asset).forceApprove(address(swapper), amountToSwap);
                    try swapper.swap(asset, stbl, amountToSwap, 20_000) {} catch {}
                }
                uint stblGot = IERC20(stbl).balanceOf(address(this)) - stblBalanceWas;
                uint xGot = stblGot * $.xShare / 100;
                uint feeTreasuryGot = stblGot - xGot;
                IERC20(stbl).safeTransfer(feeTreasury, feeTreasuryGot);
                $.pendingRevenue += xGot;
            }
        } else {
            IERC20(asset).safeTransferFrom(msg.sender, feeTreasury, amount);
        }
    }

    /// @inheritdoc IRevenueRouter
    function processFeeVault(address vault, uint amount) external {
        if (_isDeployedVault(vault)) {
            RevenueRouterStorage storage $ = _getRevenueRouterStorage();
            if (IStabilityVault(vault).lastBlockDefenseDisabled()) {
                _withdrawVaultSharesAndBuyBack($, vault, amount, msg.sender);
            } else {
                IERC20(vault).safeTransferFrom(msg.sender, address(this), amount);
                $.vaultsAccumulated.add(vault);
            }
        }
    }

    /// @inheritdoc IRevenueRouter
    function processUnitRevenue(uint unitIndex) public {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        require(unitIndex < $.units.length, IControllable.NotExist());

        // Aave aTokens revenue
        if ($.units[unitIndex].unitType == UnitType.AaveMarkets) {
            (address[] memory outAssets, uint[] memory amounts) = IFeeTreasury($.units[unitIndex].feeTreasury).harvest();
            ISwapper swapper = ISwapper(IPlatform(platform()).swapper());
            address stbl = $.stbl;
            uint stblBalanceWas = IERC20(stbl).balanceOf(address(this));

            for (uint i; i < outAssets.length; ++i) {
                address asset = IAToken(outAssets[i]).UNDERLYING_ASSET_ADDRESS();
                if (amounts[i] != 0) {
                    // here we use all because extra amounts from failed withdraw can be
                    amounts[i] = IERC20(outAssets[i]).balanceOf(address(this));
                    try IPool(IAToken(outAssets[i]).POOL()).withdraw(asset, amounts[i], address(this)) {
                        IERC20(asset).forceApprove(address(swapper), amounts[i]);
                        try swapper.swap(asset, stbl, amounts[i], 20_000) {} catch {}
                    } catch {}
                }
            }

            uint stblGot = IERC20(stbl).balanceOf(address(this)) - stblBalanceWas;
            $.units[unitIndex].pendingRevenue += stblGot;

            emit ProcessUnitRevenue(unitIndex, stblGot);
        }
    }

    /// @inheritdoc IRevenueRouter
    function processUnitsRevenue() external {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();

        // mint Aave fees
        uint len = $.aavePools.length;
        for (uint i; i < len; ++i) {
            address aavePool = $.aavePools[i];
            address[] memory reserves = IPool(aavePool).getReservesList();
            IPool(aavePool).mintToTreasury(reserves);
        }

        // process all units revenue
        len = $.units.length;
        for (uint i; i < len; ++i) {
            processUnitRevenue(i);
        }
    }

    /// @inheritdoc IRevenueRouter
    function processAccumulatedVaults(uint maxVaultsForWithdraw) external {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();

        // process accumulatedVaults
        address[] memory _vaultsAccumulated = $.vaultsAccumulated.values();
        uint len = _vaultsAccumulated.length;
        for (uint i; i < len; ++i) {
            if (i == maxVaultsForWithdraw) {
                break;
            }
            _withdrawVaultSharesAndBuyBack(
                $, _vaultsAccumulated[i], IERC20(_vaultsAccumulated[i]).balanceOf(address(this)), address(this)
            );
            $.vaultsAccumulated.remove(_vaultsAccumulated[i]);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRevenueRouter
    function units() external view returns (Unit[] memory) {
        return _getRevenueRouterStorage().units;
    }

    /// @inheritdoc IRevenueRouter
    function getPeriod() public view returns (uint) {
        return (block.timestamp / 1 weeks);
    }

    /// @inheritdoc IRevenueRouter
    function activePeriod() external view returns (uint) {
        return _getRevenueRouterStorage().activePeriod;
    }

    /// @inheritdoc IRevenueRouter
    function pendingRevenue() external view returns (uint) {
        return _getRevenueRouterStorage().pendingRevenue;
    }

    /// @inheritdoc IRevenueRouter
    function pendingRevenue(uint unitIndex) external view returns (uint) {
        return _getRevenueRouterStorage().units[unitIndex].pendingRevenue;
    }

    /// @inheritdoc IRevenueRouter
    function aavePools() external view returns (address[] memory) {
        return _getRevenueRouterStorage().aavePools;
    }

    /// @inheritdoc IRevenueRouter
    function vaultsAccumulated() external view returns (address[] memory) {
        return _getRevenueRouterStorage().vaultsAccumulated.values();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _withdrawVaultSharesAndBuyBack(
        RevenueRouterStorage storage $,
        address vault,
        uint amount,
        address owner
    ) internal {
        address stbl = $.stbl;
        ISwapper swapper = ISwapper(IPlatform(platform()).swapper());
        address _recovery = IPlatform(platform()).recovery();
        address[] memory assets = IStabilityVault(vault).assets();
        uint len = assets.length;
        try IStabilityVault(vault).withdrawAssets(assets, amount, new uint[](len), address(this), owner) {
            uint stblBalanceWas = IERC20(stbl).balanceOf(address(this));

            RevenueRouterLib.processAssets(assets, stbl, swapper, _recovery);

            uint stblGot = IERC20(stbl).balanceOf(address(this)) - stblBalanceWas;
            IERC20(stbl).safeTransfer($.feeTreasury, stblGot);
        } catch {}
    }

    function _isDeployedVault(address vault) internal view returns (bool) {
        address[] memory deployedVaults = IFactory(IPlatform(platform()).factory()).deployedVaults();
        uint len = deployedVaults.length;
        for (uint i; i < len; ++i) {
            if (deployedVaults[i] == vault) {
                return true;
            }
        }
        return false;
    }

    function _getRevenueRouterStorage() internal pure returns (RevenueRouterStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := REVENUE_ROUTER_STORAGE_LOCATION
        }
    }
}
