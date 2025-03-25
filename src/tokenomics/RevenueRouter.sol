// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IXSTBL} from "../interfaces/IXSTBL.sol";
import {IRevenueRouter} from "../interfaces/IRevenueRouter.sol";

contract RevenueRouter is Controllable, IRevenueRouter {
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
        uint activePeriod;
        uint pendingRevenue;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(address platform_, address xStbl_) external initializer {
        __Controllable_init(platform_);
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();
        $.stbl = IXSTBL(xStbl_).STBL();
        $.xStbl = xStbl_;
        $.xStaking = IXSTBL(xStbl_).xStaking();
    }

    /// @inheritdoc IRevenueRouter
    function updatePeriod() external returns (uint newPeriod) {
        RevenueRouterStorage storage $ = _getRevenueRouterStorage();

        uint _activePeriod = getPeriod();

        require($.activePeriod < _activePeriod, WaitForNewPeriod());

        $.activePeriod = _activePeriod;
        newPeriod = _activePeriod;

        IXSTBL($.xStbl).rebase();
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
