// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {VaultBase, IVault} from "../base/VaultBase.sol";
import {VaultTypeLib} from "../libs/VaultTypeLib.sol";
import {CommonLib} from "../libs/CommonLib.sol";
import {IControllable} from "../../interfaces/IControllable.sol";

/// @notice Tokenized 100% auto compounding vault with a single underlying liquidity mining position.
/// @dev This vault implementation contract is used by VaultProxy instances deployed by the Factory.
/// Changelog:
///   1.11.0 Use VaultBase 2.8.0
///   1.10.1 Use VaultBase 2.7.1
///   1.10.0 Use VaultBase 2.7.0
///   1.9.0: Use VaultBase 2.6.0
///   1.8.0: Use VaultBase 2.5.0
///   1.7.2: Use VaultBase 2.4.2
///   1.7.1: Use mulDiv - #300
///   1.7.0: IStabilityVault.lastBlockDefenseDisabled()
///   1.6.0: IStabilityVault
///   1.5.0: hardWorkMintFeeCallback use revenueRouter
///   1.4.0: previewDepositAssetsWrite
///   1.3.0: hardWorkMintFeeCallback
///   1.2.0: doHardWorkOnDeposit fix
///   1.1.0: setName, setSymbol
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
/// @author dvpublic (https://github.com/dvpublic)
contract CVault is VaultBase {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.11.0";

    uint internal constant _UNIQUE_INIT_ADDRESSES = 1;

    uint internal constant _UNIQUE_INIT_NUMS = 0;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IVault
    function initialize(VaultInitializationData memory vaultInitializationData) public initializer {
        __VaultBase_init(
            vaultInitializationData.platform,
            VaultTypeLib.COMPOUNDING,
            vaultInitializationData.strategy,
            vaultInitializationData.name,
            vaultInitializationData.symbol,
            vaultInitializationData.tokenId
        );
        if (vaultInitializationData.vaultInitAddresses.length != 0 || vaultInitializationData.vaultInitNums.length != 0)
        {
            revert IControllable.IncorrectInitParams();
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IVault
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x00bb99), bytes3(0x00110a)));
    }

    /// @inheritdoc IVault
    function getUniqueInitParamLength() public pure override returns (uint uniqueInitAddresses, uint uniqueInitNums) {
        return (_UNIQUE_INIT_ADDRESSES, _UNIQUE_INIT_NUMS);
    }
}
