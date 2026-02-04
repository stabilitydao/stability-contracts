// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Controllable, IControllable} from "../core/base/Controllable.sol";
import {IAToken} from "../integrations/aave/IAToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IFeeTreasury} from "../interfaces/IFeeTreasury.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IPool} from "../integrations/aave/IPool.sol";
import {IRevenueRouter, EnumerableMap, EnumerableSet} from "../interfaces/IRevenueRouter.sol";
import {IStabilityVault} from "../interfaces/IStabilityVault.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {IXToken} from "../interfaces/IXToken.sol";
import {IXStaking} from "../interfaces/IXStaking.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IHardWorker} from "../interfaces/IHardWorker.sol";
import {IRecoveryBase} from "../interfaces/IRecoveryBase.sol";

/// @title Platform revenue distributor
/// Changelog:
///   2.0.0: buy-back rate; remove xShare
///   1.8.0: renaming (STBL => main-token, xSTBL => xToken), xShare = 100% by default.
///          Add setAddresses, getXShare. RevenueRouter uses IRecoveryBase instead of IRecovery - #426
///   1.7.1: add addresses()
///   1.7.0: improve
///   1.6.0: send 20% of earned assets to Recovery
///   1.5.0: processAccumulatedVaults
///   1.4.0: processUnitRevenue use try..catch for Aave aToken withdrawals; view vaultsAccumulated
///   1.3.0: vaultsAccumulated; updateUnit; units
///   1.2.0: Units; Aave unit; all revenue via buy-back
/// @author Alien Deployer (https://github.com/a17)
contract RevenueRouter is Controllable, IRevenueRouter {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "2.0.0";

    // todo get from DAO parameters
    uint internal constant RECOVER_PERCENTAGE = 20_000; // 20%

    uint internal constant DENOMINATOR = 100_000; // 100%

    /// @notice Count of addresses in addresses() and setAddresses
    uint internal constant COUNT_ADDRESSES = 4;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.RevenueRouter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant REVENUE_ROUTER_STORAGE_LOCATION =
        0x052d2762d037d7d0dd41be56f750d8d5de9f07d940d686a3b9365e8e49143600;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(address platform_, address xToken_, address feeTreasury_) external initializer {
        __Controllable_init(platform_);
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        if (xToken_ != address(0)) {
            $.token = IXToken(xToken_).token();
            $.xToken = xToken_;
            $.xStaking = IXToken(xToken_).xStaking();
        }
        $.feeTreasury = feeTreasury_;
        $.activePeriod = getPeriod();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        GOV ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyOperatorAgent() {
        _requireOperatorAgent();
        _;
    }

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

    /// @inheritdoc IRevenueRouter
    function setMinSwapAmounts(address[] calldata assets, uint[] calldata minAmounts) external onlyOperator {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        uint len = assets.length;
        require(len > 0 && len == minAmounts.length, IControllable.IncorrectArrayLength());
        for (uint i; i < len; ++i) {
            $.minSwapAmount.set(assets[i], minAmounts[i]);
        }
    }

    /// @inheritdoc IRevenueRouter
    function setMaxSwapAmounts(address[] calldata assets, uint[] calldata maxAmounts) external onlyOperator {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        uint len = assets.length;
        require(len > 0 && len == maxAmounts.length, IControllable.IncorrectArrayLength());
        for (uint i; i < len; ++i) {
            $.maxSwapAmount.set(assets[i], maxAmounts[i]);
        }
    }

    /// @inheritdoc IRevenueRouter
    function setAddresses(address[] memory addresses_) external onlyGovernanceOrMultisig {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        $.token = addresses_[0];
        $.xToken = addresses_[1];
        $.xStaking = addresses_[2];
        $.feeTreasury = addresses_[3];

        emit SetAddresses(addresses_);
    }

    /// @inheritdoc IRevenueRouter
    function setBuyBackRate(uint bbRate) external onlyOperator {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        $.bbRate = bbRate;
        emit BuyBackRate(bbRate);
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
        address _xToken = $.xToken;
        if (_xToken != address(0)) {
            // process PvP rewards (100% xToken exit fees)
            IXToken(_xToken).rebase();

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
            address _xStaking = $.xStaking;

            // buy-back rewards
            if (_pendingRevenue != 0) {
                IERC20($.token).approve(_xStaking, _pendingRevenue);
                IXStaking(_xStaking).notifyRewardAmount(_pendingRevenue);
            }
            // not used now
            emit EpochFlip(periodEnded, _pendingRevenue);

            // other tokens rewards
            address[] memory _pendingRevenueAssets = $.pendingRevenueAsset.keys();
            len = _pendingRevenueAssets.length;
            for (uint i; i < len; ++i) {
                address asset = _pendingRevenueAssets[i];
                uint revenue = $.pendingRevenueAsset.get(asset);
                IERC20(asset).approve(_xStaking, revenue);
                IXStaking(_xStaking).notifyRewardAmountToken(asset, revenue);
            }
            $.pendingRevenueAsset.clear();
        }
    }

    /// @inheritdoc IRevenueRouter
    function processFeeAsset(address asset, uint amount) external {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        $.assetsAccumulated.add(asset);
    }

    /// @inheritdoc IRevenueRouter
    function processFeeVault(address vault, uint amount) external {
        if (_isDeployedVault(vault)) {
            RevenueRouterStorage storage $ = _getRevenueRouterStorage();
            IERC20(vault).safeTransferFrom(msg.sender, address(this), amount);
            $.vaultsAccumulated.add(vault);
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
            address _mainToken = $.token;
            uint mainTokenBalanceWas = IERC20(_mainToken).balanceOf(address(this));

            for (uint i; i < outAssets.length; ++i) {
                address asset = IAToken(outAssets[i]).UNDERLYING_ASSET_ADDRESS();
                if (amounts[i] != 0) {
                    // here we use all because extra amounts from failed withdraw can be
                    amounts[i] = IERC20(outAssets[i]).balanceOf(address(this));
                    try IPool(IAToken(outAssets[i]).POOL()).withdraw(asset, amounts[i], address(this)) {
                        IERC20(asset).forceApprove(address(swapper), amounts[i]);
                        try swapper.swap(asset, _mainToken, amounts[i], 20_000) {} catch {}
                    } catch {}
                }
            }

            uint mainTokenGot = IERC20(_mainToken).balanceOf(address(this)) - mainTokenBalanceWas;
            $.units[unitIndex].pendingRevenue += mainTokenGot;

            emit ProcessUnitRevenue(unitIndex, mainTokenGot);
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

    struct ProcessAssetVars {
        address asset;
        uint amountOnBalance;
        uint amountPending;
        uint amountToProcess;
        uint amountToBuyBack;
        uint amountToPending;
        bool cleanup;
        bool finish;
    }

    /// @inheritdoc IRevenueRouter
    function processAccumulatedAssets(uint maxAssetsForProcess) external onlyOperatorAgent {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        uint bbRate = $.bbRate;

        address[] memory _assetsAccumulated = $.assetsAccumulated.values();
        uint len = _assetsAccumulated.length;
        for (uint i; i < len; ++i) {
            if (i == maxAssetsForProcess) {
                break;
            }

            ProcessAssetVars memory v;
            v.asset = _assetsAccumulated[i];
            v.amountOnBalance = IERC20(v.asset).balanceOf(address(this));
            (, v.amountPending) = $.pendingRevenueAsset.tryGet(v.asset);

            v.amountToProcess = v.amountOnBalance - v.amountPending;
            v.amountToBuyBack = v.amountToProcess * bbRate / 100;

            // when buy-back rate is zero not need to check min/max swap amount settings
            if (v.amountToBuyBack != 0) {
                (bool minAmountExist, uint minSwapAmount) = $.minSwapAmount.tryGet(v.asset);
                (bool maxAmountExist, uint maxSwapAmount) = $.maxSwapAmount.tryGet(v.asset);
                if (!minAmountExist || v.amountToBuyBack < minSwapAmount || !maxAmountExist) {
                    continue;
                }

                if (v.amountToBuyBack > maxSwapAmount) {
                    v.amountToBuyBack = maxSwapAmount;
                    v.amountToProcess = v.amountToBuyBack * 100 / bbRate;
                } else {
                    v.cleanup = true;
                }
            } else {
                v.cleanup = true;
            }

            if (bbRate < 100 && !IXStaking($.xStaking).isTokenAllowed(v.asset)) {
                continue;
            }

            {
                address _recovery = IPlatform(platform()).recovery();
                if (_recovery != address(0)) {
                    uint toRecovery = v.amountToProcess * RECOVER_PERCENTAGE / DENOMINATOR;
                    v.amountToProcess -= toRecovery;
                    v.amountToBuyBack = v.amountToProcess * bbRate / 100;
                    IERC20(v.asset).safeTransfer(_recovery, toRecovery);
                    address[] memory assetsToRegister = new address[](1);
                    assetsToRegister[0] = v.asset;
                    IRecoveryBase(_recovery).registerAssets(assetsToRegister);
                }
            }

            address mainToken = $.token;
            require(mainToken != address(0), "SetupMainToken");
            ISwapper swapper = ISwapper(IPlatform(platform()).swapper());

            if (v.amountToBuyBack != 0) {
                uint mainTokenBalanceWas = IERC20(mainToken).balanceOf(address(this));

                IERC20(v.asset).forceApprove(address(swapper), v.amountToBuyBack);
                try swapper.swap(v.asset, mainToken, v.amountToBuyBack, 40_000) {
                    uint xGot = IERC20(mainToken).balanceOf(address(this)) - mainTokenBalanceWas;
                    $.pendingRevenue += xGot;
                    v.finish = true;
                } catch {}
            }

            v.amountToPending = v.amountToProcess - v.amountToBuyBack;

            if (v.amountToPending != 0) {
                $.pendingRevenueAsset.set(v.asset, v.amountPending + v.amountToPending);
                v.finish = true;
            }

            if (v.cleanup) {
                $.assetsAccumulated.remove(v.asset);
            }

            if (v.finish) {
                return;
            }
        }

        revert CantProcessAction();
    }

    /// @inheritdoc IRevenueRouter
    function processAccumulatedVaults(uint maxVaultsForWithdraw, uint maxWithdrawAmount) public {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();

        uint processed;
        address[] memory _vaultsAccumulated = $.vaultsAccumulated.values();
        uint len = _vaultsAccumulated.length;
        for (uint i; i < len; ++i) {
            if (i == maxVaultsForWithdraw) {
                break;
            }

            bool cleanup;
            uint toWithdraw = IERC20(_vaultsAccumulated[i]).balanceOf(address(this));
            if (toWithdraw > maxWithdrawAmount) {
                toWithdraw = maxWithdrawAmount;
            } else {
                cleanup = true;
            }

            bool withdrawn = _withdrawVaultShares($, _vaultsAccumulated[i], toWithdraw, address(this));

            if (cleanup && withdrawn) {
                $.vaultsAccumulated.remove(_vaultsAccumulated[i]);
            }

            processed++;
        }

        require(processed != 0, CantProcessAction());
    }

    /// @inheritdoc IRevenueRouter
    function processAccumulatedVaults(uint maxVaultsForWithdraw) external {
        processAccumulatedVaults(maxVaultsForWithdraw, 10000e18);
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

    /// @inheritdoc IRevenueRouter
    function addresses() external view returns (address[] memory) {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        address[] memory _addresses = new address[](COUNT_ADDRESSES);
        _addresses[0] = $.token;
        _addresses[1] = $.xToken;
        _addresses[2] = $.xStaking;
        _addresses[3] = $.feeTreasury;
        return _addresses;
    }

    /// @inheritdoc IRevenueRouter
    function assetsAccumulated() external view returns (address[] memory) {
        return _getRevenueRouterStorage().assetsAccumulated.values();
    }

    /// @inheritdoc IRevenueRouter
    function buyBackRate() external view returns (uint) {
        return _getRevenueRouterStorage().bbRate;
    }

    /// @inheritdoc IRevenueRouter
    function pendingRevenueAssets() external view returns (address[] memory) {
        return _getRevenueRouterStorage().pendingRevenueAsset.keys();
    }

    /// @inheritdoc IRevenueRouter
    function pendingRevenueAsset(address asset) external view returns (uint) {
        (, uint amount) = _getRevenueRouterStorage().pendingRevenueAsset.tryGet(asset);
        return amount;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _withdrawVaultShares(
        RevenueRouterStorage storage $,
        address vault,
        uint amount,
        address owner
    ) internal returns (bool withdrawn) {
        address[] memory assets = IStabilityVault(vault).assets();
        uint len = assets.length;
        try IStabilityVault(vault).withdrawAssets(assets, amount, new uint[](len), address(this), owner) {
            for (uint i; i < len; ++i) {
                address asset = assets[i];
                $.assetsAccumulated.add(asset);
            }
            withdrawn = true;
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

    function _requireOperatorAgent() internal view {
        IPlatform _platform = IPlatform(platform());
        IHardWorker hardworker = IHardWorker(_platform.hardWorker());
        require(
            hardworker.dedicatedServerMsgSender(msg.sender) || _platform.isOperator(msg.sender),
            IControllable.IncorrectMsgSender()
        );
    }

    function _getRevenueRouterStorage() internal pure returns (RevenueRouterStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := REVENUE_ROUTER_STORAGE_LOCATION
        }
    }
}
