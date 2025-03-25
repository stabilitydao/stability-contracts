// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {IControllable} from "../interfaces/IControllable.sol";

/// @title Performance fee treasury that distribute fees to claimers
/// @author Alien Deployer (https://github.com/a17)
contract FeeTreasury is Controllable {
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    uint public constant SHARE_DELIMITER = 100;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.FeeTreasury")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FEE_TREASURY_STORAGE_LOCATION =
        0x9841ffcb19b07e2df5c0f154ac42c4f1d3d843e5998ccaba277a7e70b5ce1800;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct AssetData {
        uint distributed;
        uint claimed;
    }

    /// @custom:storage-location erc7201:stability.FeeTreasury
    struct FeeTreasuryStorage {
        EnumerableMap.AddressToUintMap claimers;
        mapping(address asset => AssetData) assetData;
        mapping(address asset => mapping(address claimer => uint amount)) toClaim;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event Claimers(address[] claimers, uint[] shares);
    event Claim(address indexed claimer, address indexed asset, uint amount);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error SetupFeeTreasuryFirst();
    error IncorrectSharesTotal();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(address platform_) external initializer {
        __Controllable_init(platform_);
    }

    function setClaimers(address[] memory claimers_, uint[] memory shares) external onlyGovernanceOrMultisig {
        FeeTreasuryStorage storage $ = _getTreasuryStorage();
        _cleanClaimers($);
        uint len = claimers_.length;
        uint total;
        for (uint i; i < len; ++i) {
            $.claimers.set(claimers_[i], shares[i]);
            total += shares[i];
        }
        require(total == SHARE_DELIMITER, IncorrectSharesTotal());
        emit Claimers(claimers_, shares);
    }

    function claim(address[] memory assets) external {
        FeeTreasuryStorage storage $ = _getTreasuryStorage();
        (bool exists,) = $.claimers.tryGet(msg.sender);
        require(exists, IncorrectMsgSender());
        uint len = assets.length;
        for (uint i; i < len; ++i) {
            uint toClaim = $.toClaim[assets[i]][msg.sender];
            $.toClaim[assets[i]][msg.sender] = 0;
            IERC20(assets[i]).safeTransfer(msg.sender, toClaim);
            AssetData memory assetData = $.assetData[assets[i]];
            $.assetData[assets[i]].claimed = assetData.claimed + toClaim;
        }
    }

    function distribute(address[] memory assets) external {
        FeeTreasuryStorage storage $ = _getTreasuryStorage();
        uint len = assets.length;
        for (uint i; i < len; ++i) {
            AssetData memory assetData = $.assetData[assets[i]];
            uint bal = IERC20(assets[i]).balanceOf(address(this));
            uint distributedOnBalance = assetData.distributed - assetData.claimed;
            if (bal > distributedOnBalance) {
                uint amountToDistribute = bal - distributedOnBalance;
                if (amountToDistribute > 100) {
                    _distributeAssetAmount($, assets[i], amountToDistribute);
                    $.assetData[assets[i]].distributed = assetData.distributed + amountToDistribute;
                }
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _distributeAssetAmount(FeeTreasuryStorage storage $, address asset, uint amount) internal {
        address[] memory claimerAddress = $.claimers.keys();
        uint len = claimerAddress.length;
        if (len == 0) {
            revert SetupFeeTreasuryFirst();
        }
        for (uint i; i < len; ++i) {
            uint share = $.claimers.get(claimerAddress[i]);
            uint amountForClaimer = amount * share / SHARE_DELIMITER;
            uint oldAmountToClaim = $.toClaim[asset][claimerAddress[i]];
            $.toClaim[asset][claimerAddress[i]] = oldAmountToClaim + amountForClaimer;
        }
    }

    function _cleanClaimers(FeeTreasuryStorage storage $) internal {
        uint len = $.claimers.length();
        if (len > 0) {
            address[] memory claimerAddress = $.claimers.keys();
            for (uint i; i < len; ++i) {
                $.claimers.remove(claimerAddress[i]);
            }
        }
    }

    function _getTreasuryStorage() private pure returns (FeeTreasuryStorage storage $) {
        assembly {
            $.slot := FEE_TREASURY_STORAGE_LOCATION
        }
    }
}
