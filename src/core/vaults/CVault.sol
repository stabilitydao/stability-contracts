// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../base/VaultBase.sol";
import "../libs/VaultTypeLib.sol";
import "../libs/CommonLib.sol";

/// @notice Tokenized 100% auto compounding vault with a single underlying liquidity mining position.
/// @dev This vault implementation contract is used by VaultProxy instances deployed by the Factory.
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
contract CVault is VaultBase {
    //region ----- Constants -----

    /// @dev Version of CVault implementation
    string public constant VERSION = '1.0.0';

    /// @inheritdoc IVault
    uint public constant UNIQUE_INIT_ADDRESSES = 1;

    /// @inheritdoc IVault
    uint public constant UNIQUE_INIT_NUMS = 0;

    //endregion -- Constants -----

    //region ----- Init -----

    /// @inheritdoc IVault
    function initialize(
        VaultInitializationData memory vaultInitializationData
    ) initializer public {
        __VaultBase_init(
            vaultInitializationData.platform,
            VaultTypeLib.COMPOUNDING,
            vaultInitializationData.strategy,
            vaultInitializationData.name,
            vaultInitializationData.symbol,
            vaultInitializationData.tokenId
        );
        if(vaultInitializationData.vaultInitAddresses.length != 0 || vaultInitializationData.vaultInitNums.length != 0) {
            revert IControllable.IncorrectInitParams();
        }
    }

    //endregion -- Init -----

    //region ----- View functions -----

    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x00bb99), bytes3(0x00110a)));
    }

    //endregion -- View functions -----

}
