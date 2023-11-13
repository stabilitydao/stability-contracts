// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "../base/VaultBase.sol";
import "../libs/VaultTypeLib.sol";
import "../../interfaces/IRVault.sol";
import "../libs/CommonLib.sol";
import "../base/RVaultBase.sol";

/// @notice Rewarding unmanaged vault.
///         Vault has 0% compound ratio, buy-back reward token and additional default boost reward tokens with default vesting duration.
/// @dev This vault implementation contract is used by VaultProxy instances deployed by the Factory.
/// @author Alien Deployer (https://github.com/a17)
contract RVault is RVaultBase {
    using SafeERC20 for IERC20;

    //region ----- Constants -----

    /// @dev Version of RVault implementation
    string public constant VERSION = '1.0.0';

    uint public constant BB_TOKEN_DURATION = 86400 * 7;

    uint public constant BOOST_REWARD_DURATION = 86400 * 30;

    //endregion -- Constants -----

    //region ----- Storage -----

    /// @dev This empty reserved space is put in place to allow future versions to add new.
    /// variables without shifting down storage in the inheritance chain.
    /// Total gap == 50 - storage slots used.
    uint[50 - 0] private __gap;

    //endregion -- Storage -----

    //region ----- Data types -----

    struct InitVars {
        address[] defaultBoostRewardTokens;
        address[] vaultInitAddresses_;
        uint[] vaultInitNums_;
    }
    //endregion -- Data types -----

    //region ----- Init -----

    /// @inheritdoc IVault
    function initialize(
        address platform_,
        address strategy_,
        string memory name_,
        string memory symbol_,
        uint tokenId_,
        address[] memory vaultInitAddresses,
        uint[] memory vaultInitNums
    ) initializer public {
        require(vaultInitAddresses.length == 1 && vaultInitNums.length >= 1, "RVault: incorrect init params");
        InitVars memory vars;
        vars.defaultBoostRewardTokens = CommonLib.filterAddresses(IPlatform(platform_).defaultBoostRewardTokens(), vaultInitAddresses[0]);
        uint len = 2 + vars.defaultBoostRewardTokens.length;
        vars.vaultInitAddresses_ = new address[](len);
        vars.vaultInitNums_ = new uint[](len * 2);
        vars.vaultInitAddresses_[0] = vaultInitAddresses[0]; // bb token
        vars.vaultInitAddresses_[1] = vaultInitAddresses[0]; // first boost reward token
        vars.vaultInitNums_[0] = BB_TOKEN_DURATION;
        vars.vaultInitNums_[1] = BOOST_REWARD_DURATION;
        for (uint i = 2; i < len; ++i) {
            vars.vaultInitAddresses_[i] = vars.defaultBoostRewardTokens[i - 2];
            vars.vaultInitNums_[i] = BOOST_REWARD_DURATION;
        }
        __RVaultBase_init(platform_, VaultTypeLib.REWARDING, strategy_, name_, symbol_, tokenId_, vars.vaultInitAddresses_, vars.vaultInitNums_);
    }

    //endregion -- Init -----

    //region ----- View functions -----

    /// @inheritdoc IVault
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x6052ff), bytes3(0x090816)));
    }

    //endregion -- View functions -----

}
