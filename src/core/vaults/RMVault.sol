// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "../base/VaultBase.sol";
import "../base/RVaultBase.sol";
import "../libs/VaultTypeLib.sol";
import "../libs/CommonLib.sol";
import "../../interfaces/IPlatform.sol";
import "../../interfaces/IManagedVault.sol";
import "../../interfaces/IRVault.sol";

/// @notice Rewarding managed vault.
/// @dev This vault implementation contract is used by VaultProxy instances deployed by the Factory.
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
/// @author Jude (https://github.com/iammrjude)
contract RMVault is RVaultBase, IManagedVault {
    using SafeERC20 for IERC20;

    //region ----- Constants -----

    /// @dev Version of RMVault implementation
    string public constant VERSION = "1.3.0";

    uint internal constant _UNIQUE_INIT_ADDRESSES = 1;

    uint internal constant _UNIQUE_INIT_NUMS = 0;

    //endregion -- Constants -----

    //region ----- Init -----

    /// @inheritdoc IVault
    function initialize(VaultInitializationData memory vaultInitializationData) public initializer {
        __RVaultBase_init(
            vaultInitializationData.platform,
            VaultTypeLib.REWARDING_MANAGED,
            vaultInitializationData.strategy,
            vaultInitializationData.name,
            vaultInitializationData.symbol,
            vaultInitializationData.tokenId,
            vaultInitializationData.vaultInitAddresses,
            vaultInitializationData.vaultInitNums
        );
    }

    //endregion -- Init -----

    //region ----- Callbacks -----

    /// @inheritdoc IVault
    function hardWorkMintFeeCallback(address[] memory, uint[] memory) external pure override(VaultBase, IVault) {
        revert NotSupported();
    }

    //endregion -- Callbacks -----

    //region ----- User actions -----

    /// @inheritdoc IManagedVault
    //slither-disable-next-line cyclomatic-complexity
    function changeParams(address[] memory addresses, uint[] memory nums) external {
        // todo #22 implement bbRatio changing
        if (IPlatform(platform()).vaultManager() != msg.sender) {
            revert IManagedVault.NotVaultManager();
        }
        uint addressesLength = addresses.length;
        if (nums.length != addressesLength + 2) {
            revert IControllable.IncorrectInitParams();
        }
        uint _rewardTokensTotal = rewardTokensTotal();
        if (addressesLength < _rewardTokensTotal - 1) {
            revert IManagedVault.CantRemoveRewardToken();
        }
        // nosemgrep
        for (uint i = 1; i < _rewardTokensTotal; ++i) {
            if (rewardToken(i) != addresses[i - 1]) {
                revert IManagedVault.IncorrectRewardToken(addresses[i - 1]);
            }
            if (duration(i) != nums[i]) {
                revert IManagedVault.CantChangeDuration(nums[i]);
            }
        }
        RVaultBaseStorage storage _$ = _getRVaultBaseStorage();
        if (addressesLength > _rewardTokensTotal - 1) {
            // nosemgrep
            for (uint i = _rewardTokensTotal; i < addressesLength + 1; ++i) {
                uint i_1 = i - 1;
                if (addresses[i_1] == address(0)) {
                    revert IControllable.IncorrectZeroArgument();
                }
                if (nums[i] == 0) {
                    revert IControllable.IncorrectZeroArgument();
                }
                _$.rewardTokensTotal = i + 1;
                _$.rewardToken[i] = addresses[i_1];
                _$.duration[i] = nums[i];
                emit AddedRewardToken(addresses[i_1], i);
            }
        }

        if (nums[addressesLength + 1] != _$.compoundRatio) {
            // todo #22 check side effects with tests
            _$.compoundRatio = nums[addressesLength + 1];
            emit CompoundRatio(nums[addressesLength + 1]);
        }
    }

    //endregion -- User actions ----

    //region ----- View functions -----

    /// @inheritdoc IVault
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0xd45a1d), bytes3(0x170a03)));
    }

    /// @inheritdoc IVault
    function getUniqueInitParamLength()
        public
        pure
        override(IVault, VaultBase)
        returns (uint uniqueInitAddresses, uint uniqueInitNums)
    {
        return (_UNIQUE_INIT_ADDRESSES, _UNIQUE_INIT_NUMS);
    }

    //endregion -- View functions -----
}
