// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IXSTBL} from "../interfaces/IXSTBL.sol";
import {IRevenueRouter} from "../interfaces/IRevenueRouter.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IXStaking} from "../interfaces/IXStaking.sol";

/// @title Platform revenue distributor
/// @author Alien Deployer (https://github.com/a17)
contract RevenueRouter is Controllable, IRevenueRouter {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.RevenueRouter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant REVENUE_ROUTER_STORAGE_LOCATION =
        0x052d2762d037d7d0dd41be56f750d8d5de9f07d940d686a3b9365e8e49143600;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.RevenueRouter
    struct RevenueRouterStorage {
        address stbl;
        address xStbl;
        address xStaking;
        address feeTreasury;
        uint xShare;
        uint activePeriod;
        uint pendingRevenue;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(address platform_, address xStbl_, address feeTreasury_) external initializer {
        __Controllable_init(platform_);
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        $.stbl = IXSTBL(xStbl_).STBL();
        $.xStbl = xStbl_;
        $.xStaking = IXSTBL(xStbl_).xStaking();
        $.feeTreasury = feeTreasury_;
        $.xShare = 50;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRevenueRouter
    function updatePeriod() external returns (uint newPeriod) {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();

        uint _activePeriod = getPeriod();
        uint _pendingRevenue = $.pendingRevenue;

        require($.activePeriod < _activePeriod, WaitForNewPeriod());

        $.activePeriod = _activePeriod;
        newPeriod = _activePeriod;

        IXSTBL($.xStbl).rebase();

        if (_pendingRevenue != 0) {
            address _xStaking = $.xStaking;
            IERC20($.stbl).approve(_xStaking, _pendingRevenue);
            IXStaking(_xStaking).notifyRewardAmount(_pendingRevenue);
            $.pendingRevenue = 0;
        }
    }

    /// @inheritdoc IRevenueRouter
    function processFeeAsset(address asset, uint amount) external {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        uint xAmount = amount * $.xShare / 100;
        uint feeTreasuryAmount = amount - xAmount;
        address stbl = $.stbl;
        uint stblBalanceWas = IERC20(stbl).balanceOf(address(this));
        IERC20(asset).safeTransferFrom(msg.sender, address(this), xAmount);
        IERC20(asset).safeTransferFrom(msg.sender, $.feeTreasury, feeTreasuryAmount);
        ISwapper swapper = ISwapper(IPlatform(platform()).swapper());
        uint threshold = swapper.threshold(asset);
        if (xAmount > threshold) {
            if (asset != stbl) {
                uint amountToSwap = IERC20(asset).balanceOf(address(this));
                IERC20(asset).forceApprove(address(swapper), amountToSwap);
                try swapper.swap(asset, stbl, amountToSwap, 20_000) {} catch {}
            }
            uint stblGot = IERC20(stbl).balanceOf(address(this)) - stblBalanceWas;
            $.pendingRevenue += stblGot;
        }
    }

    /// @inheritdoc IRevenueRouter
    function processFeeVault(address vault, uint amount) external {
        IERC20(vault).safeTransferFrom(msg.sender, _getRevenueRouterStorage().feeTreasury, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getRevenueRouterStorage() internal pure returns (RevenueRouterStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := REVENUE_ROUTER_STORAGE_LOCATION
        }
    }
}
