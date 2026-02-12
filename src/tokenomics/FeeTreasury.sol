// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableMap, EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IFeeTreasury} from "../interfaces/IFeeTreasury.sol";

/// @title Performance fee treasury that distribute fees to claimers
/// Changelog:
///   1.1.1: fix removeAssets, add assets()
///   1.1.0: assets, harvest, fixes
/// @author Alien Deployer (https://github.com/a17)
contract FeeTreasury is Controllable, IFeeTreasury {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.1.1";

    uint public constant TOTAL_SHARES = 100;

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
        address manager;
        EnumerableSet.AddressSet assets;
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

    function initialize(address platform_, address manager_) external initializer {
        __Controllable_init(platform_);
        FeeTreasuryStorage storage $ = _getTreasuryStorage();
        $.manager = manager_;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyManager() {
        _requireManager();
        _;
    }

    modifier onlyClaimer() {
        _requireClaimer();
        _;
    }

    function setManager(address manager_) external onlyGovernanceOrMultisig {
        FeeTreasuryStorage storage $ = _getTreasuryStorage();
        $.manager = manager_;
    }

    function setClaimers(address[] memory claimers_, uint[] memory shares) external onlyManager {
        FeeTreasuryStorage storage $ = _getTreasuryStorage();
        _cleanClaimers($);
        uint len = claimers_.length;
        uint total;
        for (uint i; i < len; ++i) {
            $.claimers.set(claimers_[i], shares[i]);
            total += shares[i];
        }
        require(total == TOTAL_SHARES, IncorrectSharesTotal());
        emit Claimers(claimers_, shares);
    }

    function addAssets(address[] memory assets_) external onlyOperator {
        FeeTreasuryStorage storage $ = _getTreasuryStorage();
        uint len = assets_.length;
        for (uint i; i < len; ++i) {
            $.assets.add(assets_[i]);
        }
    }

    function removeAssets(address[] memory assets_) external onlyOperator {
        FeeTreasuryStorage storage $ = _getTreasuryStorage();
        uint len = assets_.length;
        for (uint i; i < len; ++i) {
            $.assets.remove(assets_[i]);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IFeeTreasury
    function harvest() external onlyClaimer returns (address[] memory outAssets, uint[] memory amounts) {
        uint totalOutAssets;
        FeeTreasuryStorage storage $ = _getTreasuryStorage();
        address[] memory _assets = $.assets.values();
        _distribute($, _assets);
        uint len = $.assets.length();
        uint[] memory _claimedAmounts = new uint[](len);
        for (uint i; i < len; ++i) {
            uint toClaim = $.toClaim[_assets[i]][msg.sender];
            if (toClaim != 0) {
                totalOutAssets++;
                _claimedAmounts[i] = toClaim;
                _claimAsset($, _assets[i], toClaim);
            }
        }
        outAssets = new address[](totalOutAssets);
        amounts = new uint[](totalOutAssets);
        uint k;
        for (uint i; i < len; ++i) {
            if (_claimedAmounts[i] != 0) {
                outAssets[k] = _assets[i];
                amounts[k] = _claimedAmounts[i];
                k++;
            }
        }
    }

    function claim(address[] memory assets_) external onlyClaimer {
        FeeTreasuryStorage storage $ = _getTreasuryStorage();
        uint len = assets_.length;
        for (uint i; i < len; ++i) {
            uint toClaim = $.toClaim[assets_[i]][msg.sender];
            if (toClaim != 0) {
                _claimAsset($, assets_[i], toClaim);
            }
        }
    }

    function distribute(address[] memory assets_) external {
        _distribute(_getTreasuryStorage(), assets_);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IFeeTreasury
    function claimers() external view returns (address[] memory claimerAddresses, uint[] memory shares) {
        FeeTreasuryStorage storage $ = _getTreasuryStorage();
        uint len = $.claimers.length();
        claimerAddresses = new address[](len);
        shares = new uint[](len);
        for (uint i; i < len; ++i) {
            (claimerAddresses[i], shares[i]) = $.claimers.at(i);
        }
    }

    /// @notice Get list of all registered assets
    function assets() external view returns (address[] memory) {
        FeeTreasuryStorage storage $ = _getTreasuryStorage();
        return $.assets.values();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _claimAsset(FeeTreasuryStorage storage $, address asset, uint amount) internal {
        $.toClaim[asset][msg.sender] = 0;
        IERC20(asset).safeTransfer(msg.sender, amount);
        AssetData memory assetData = $.assetData[asset];
        $.assetData[asset].claimed = assetData.claimed + amount;
    }

    function _distribute(FeeTreasuryStorage storage $, address[] memory assets_) internal {
        uint len = assets_.length;
        for (uint i; i < len; ++i) {
            AssetData memory assetData = $.assetData[assets_[i]];
            uint bal = IERC20(assets_[i]).balanceOf(address(this));
            uint distributedOnBalance = assetData.distributed - assetData.claimed;
            if (bal > distributedOnBalance) {
                uint amountToDistribute = bal - distributedOnBalance;
                if (amountToDistribute > 100) {
                    _distributeAssetAmount($, assets_[i], amountToDistribute);
                    $.assetData[assets_[i]].distributed = assetData.distributed + amountToDistribute;
                }
            }
        }
    }

    function _distributeAssetAmount(FeeTreasuryStorage storage $, address asset, uint amount) internal {
        address[] memory claimerAddress = $.claimers.keys();
        uint len = claimerAddress.length;
        if (len == 0) {
            revert SetupFeeTreasuryFirst();
        }
        for (uint i; i < len; ++i) {
            uint share = $.claimers.get(claimerAddress[i]);
            uint amountForClaimer = amount * share / TOTAL_SHARES;
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

    function _requireClaimer() internal view {
        FeeTreasuryStorage storage $ = _getTreasuryStorage();
        (bool exists,) = $.claimers.tryGet(msg.sender);
        require(exists, IncorrectMsgSender());
    }

    function _requireManager() internal view {
        FeeTreasuryStorage storage $ = _getTreasuryStorage();
        require(msg.sender == $.manager, "denied");
    }

    function _getTreasuryStorage() private pure returns (FeeTreasuryStorage storage $) {
        assembly {
            $.slot := FEE_TREASURY_STORAGE_LOCATION
        }
    }
}
