// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev HardWork resolver and caller. Primary executor is server script, reserve executor is Gelato Automate.
/// Hardwork is important task of any vault - claiming revenue and processing it by strategy, updating rewarding,
/// compounding, declaring income and losses, related things.
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
interface IHardWorker {
    //region ----- Custom Errors -----
    error NotExistWithObject(address notExistObject);
    error AlreadyExclude(address alreadyExcludedObject);
    error NotServerOrGelato();
    error NotEnoughETH();
    //endregion ----- Custom Errors -----

    event Call(uint hardworks, uint gasUsed, uint gasCost, bool server);
    event DedicatedServerMsgSender(address indexed sender, bool allowed);
    event DedicatedGelatoMsgSender(address oldSender, address newSender);
    event Delays(uint delayServer, uint delayGelato);
    event GelatoTask(bytes32 id);
    event GelatoDeposit(uint amount);
    event MaxHwPerCall(uint maxHwPerCall_);
    event VaultExcludeStatusChanged(address vault, bool status);

    function getDelays() external view returns (uint delayServer, uint delayGelato);

    /// @notice Vaults that excluded from HardWork execution
    function excludedVaults(address vault) external view returns (bool);

    /// @notice Maximum vault HardWork calls per execution
    function maxHwPerCall() external view returns (uint);

    /// @notice Check dedicated server address allowance for execute vault HardWorks
    function dedicatedServerMsgSender(address sender) external view returns (bool allowed);

    /// @notice Dedicated Gelato OPS proxy for HardWorker contract address.
    /// OPS proxy is deployed at HardWorker initialization.
    /// @return Immutable Gelato dedicated msg.sender
    function dedicatedGelatoMsgSender() external view returns (address);

    /// @notice Checker method for calling from server script
    /// @return canExec Hard Work can be executed
    /// @return execPayload Vault addresses for HardWork
    function checkerServer() external view returns (bool canExec, bytes memory execPayload);

    /// @notice Checker method for calling from Gelato Automate
    /// @return canExec Hard Work can be executed
    /// @return execPayload Vault addresses for HardWork
    function checkerGelato() external view returns (bool canExec, bytes memory execPayload);

    /// @notice Gelato Automate task ID created by this contract
    function gelatoTaskId() external view returns (bytes32);

    /// @notice ETH balance of HardWork contract on Gelato
    /// @return ETH amount with 18 decimals
    function gelatoBalance() external view returns (uint);

    /// @notice Return minimum required ETH balance of HardWork contract on Gelato
    /// @return ETH amount with 18 decimals
    function gelatoMinBalance() external view returns (uint);

    /// @notice Setup allowance status for dedicated server address
    function setDedicatedServerMsgSender(address sender, bool allowed) external;

    /// @notice Setup delays between HardWorks in seconds
    /// @param delayServer_ Delay for server script
    /// @param delayGelato_ Delay for Gelato
    function setDelays(uint delayServer_, uint delayGelato_) external;

    /// @notice Set maximum vault HardWork calls per execution
    /// Only operator cal call this
    /// @param maxHwPerCall_ Max vault HardWorks per call(vaults) execution
    //slither-disable-next-line similar-names
    function setMaxHwPerCall(uint maxHwPerCall_) external;

    /// @notice Changing vault excluding status
    /// @param vaults_ Addresses of vaults
    /// @param status New status
    function changeVaultExcludeStatus(address[] memory vaults_, bool[] memory status) external;

    /// @notice Call vault HardWorks
    /// @param vaults Addresses of vault from checkerServer/checkerGelato output
    function call(address[] memory vaults) external;
}
