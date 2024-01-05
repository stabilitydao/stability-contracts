// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev Base core interface implemented by most platform contracts.
///      Inherited contracts store an immutable Platform proxy address in the storage,
///      which provides authorization capabilities and infrastructure contract addresses.
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
interface IControllable {
    //region ----- Custom Errors -----
    error IncorrectZeroArgument();
    error IncorrectMsgSender();
    error NotGovernance();
    error NotMultisig();
    error NotGovernanceAndNotMultisig();
    error NotOperator();
    error NotFactory();
    error NotPlatform();
    error NotVault();
    error IncorrectArrayLength();
    error AlreadyExist();
    error NotExist();
    error NotTheOwner();
    error ETHTransferFailed();
    error IncorrectInitParams();
    //endregion -- Custom Errors -----

    event ContractInitialized(address platform, uint ts, uint block);

    /// @notice Stability Platform main contract address
    function platform() external view returns (address);

    /// @notice Version of contract implementation
    /// @dev SemVer scheme MAJOR.MINOR.PATCH
    //slither-disable-next-line naming-convention
    function VERSION() external view returns (string memory);

    /// @notice Block number when contract was initialized
    function createdBlock() external view returns (uint);
}
