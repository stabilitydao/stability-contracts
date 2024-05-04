// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

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
/// @author JodsMigel (https://github.com/JodsMigel)
/// @author Jude (https://github.com/iammrjude)
contract RVault is RVaultBase {
    using SafeERC20 for IERC20;

    //region ----- Constants -----

    /// @dev Version of RVault implementation
    string public constant VERSION = "1.3.0";

    uint public constant BB_TOKEN_DURATION = 86400 * 7;

    uint public constant BOOST_REWARD_DURATION = 86400 * 30;

    uint internal constant _UNIQUE_INIT_ADDRESSES = 1;

    uint internal constant _UNIQUE_INIT_NUMS = 0;

    //endregion -- Constants -----

    //region ----- Data types -----

    struct InitVars {
        address[] defaultBoostRewardTokens;
        address[] vaultInitAddresses_;
        uint[] vaultInitNums_;
    }
    //endregion -- Data types -----

    //region ----- Init -----

    /// @inheritdoc IVault
    function initialize(VaultInitializationData memory vaultInitializationData) public initializer {
        if (vaultInitializationData.vaultInitAddresses.length != 1 || vaultInitializationData.vaultInitNums.length < 1)
        {
            revert IControllable.IncorrectInitParams();
        }
        //slither-disable-next-line uninitialized-local
        InitVars memory vars;
        vars.defaultBoostRewardTokens = CommonLib.filterAddresses(
            IPlatform(vaultInitializationData.platform).defaultBoostRewardTokens(),
            vaultInitializationData.vaultInitAddresses[0]
        );
        uint len = 2 + vars.defaultBoostRewardTokens.length;
        vars.vaultInitAddresses_ = new address[](len);
        vars.vaultInitNums_ = new uint[](len * 2);
        vars.vaultInitAddresses_[0] = vaultInitializationData.vaultInitAddresses[0]; // bb token
        vars.vaultInitAddresses_[1] = vaultInitializationData.vaultInitAddresses[0]; // first boost reward token
        vars.vaultInitNums_[0] = BB_TOKEN_DURATION;
        vars.vaultInitNums_[1] = BOOST_REWARD_DURATION;
        // nosemgrep
        for (uint i = 2; i < len; ++i) {
            vars.vaultInitAddresses_[i] = vars.defaultBoostRewardTokens[i - 2];
            vars.vaultInitNums_[i] = BOOST_REWARD_DURATION;
        }
        __RVaultBase_init(
            vaultInitializationData.platform,
            VaultTypeLib.REWARDING,
            vaultInitializationData.strategy,
            vaultInitializationData.name,
            vaultInitializationData.symbol,
            vaultInitializationData.tokenId,
            vars.vaultInitAddresses_,
            vars.vaultInitNums_
        );
    }

    //endregion -- Init -----

    //region ----- Callbacks -----

    /// @inheritdoc IVault
    function hardWorkMintFeeCallback(address[] memory, uint[] memory) external pure override(VaultBase, IVault) {
        revert NotSupported();
    }

    //endregion -- Callbacks -----

    //region ----- View functions -----

    /// @inheritdoc IVault
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x6052ff), bytes3(0x090816)));
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
