// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./base/VaultBase.sol";
import "./base/RVaultBase.sol";
import "./libs/VaultTypeLib.sol";
import "./libs/CommonLib.sol";
import "../interfaces/IPlatform.sol";
import "../interfaces/IManagedVault.sol";
import "../interfaces/IRVault.sol";

/// @notice Rewarding managed vault.
/// @dev This vault implementation contract is used by VaultProxy instances deployed by the Factory.
/// @author Alien Deployer (https://github.com/a17)
contract RMVault is RVaultBase, IManagedVault {
    using SafeERC20 for IERC20;

    //region ----- Constants -----

    /// @dev Version of RMVault implementation
    string public constant VERSION = '1.0.0';

    //endregion -- Constants -----

    //region ----- Storage -----

    /// @dev This empty reserved space is put in place to allow future versions to add new.
    /// variables without shifting down storage in the inheritance chain.
    /// Total gap == 50 - storage slots used.
    uint[50 - 0] private __gap;

    //endregion -- Storage -----

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
        __RVaultBase_init(platform_, VaultTypeLib.REWARDING_MANAGED, strategy_, name_, symbol_, tokenId_, vaultInitAddresses, vaultInitNums);
    }

    //endregion -- Init -----

    //region ----- User actions -----

    /// @inheritdoc IManagedVault
    function changeParams(address[] memory addresses, uint[] memory nums) external {
        // todo #22 implement bbRatio changing
        require (IPlatform(platform()).vaultManager() == msg.sender, "RMVault: denied");
        uint addressesLength = addresses.length;
        require (nums.length == addressesLength + 2, "RMVault: incorrect params");
        uint _rewardTokensTotal = rewardTokensTotal;
        require (addressesLength >= _rewardTokensTotal - 1, "RMVault: cant remove reward token");
        for (uint i = 1; i < _rewardTokensTotal; ++i) {
            require (rewardToken[i] == addresses[i - 1], "RMVault: incorrect reward tokens");
            require (duration[i] == nums[i], "RMVault: cant change duration");
        }
        
        if (addressesLength > _rewardTokensTotal - 1) {
            for (uint i = _rewardTokensTotal; i < addressesLength + 1; ++i) {
                uint i_1 = i - 1;
                require(addresses[i_1] != address(0), "RMVault: zero token");
                require(nums[i_1] > 0, "RMVault: zero vesting duration");
                
                rewardTokensTotal = i + 1;

                rewardToken[i] = addresses[i_1];
                duration[i] = nums[i_1];
                emit AddedRewardToken(addresses[i_1], i);
            }
        }

        if (nums[addressesLength + 1] != compoundRatio) {
            // todo #22 check side effects with tests
            compoundRatio = nums[addressesLength + 1];
            emit CompoundRatio(nums[addressesLength + 1]);
        }
    }

    //endregion -- User actions ----

    //region ----- View functions -----

    /// @inheritdoc IVault
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0xd45a1d), bytes3(0x170a03)));
    }

    //endregion -- View functions -----

}
