// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev HardWork resolver and caller. Executor is server script.
/// Hardwork is important task of any vault - claiming revenue and processing it by strategy, updating rewarding,
/// compounding, declaring income and losses, related things.
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
interface IHardWorker {
    //region ----- Custom Errors -----
    error NotExistWithObject(address notExistObject);
    error AlreadyExclude(address alreadyExcludedObject);
    error NotServer();
    error NotEnoughETH();
    //endregion ----- Custom Errors -----

    event Call(uint hardworks, uint gasUsed, uint gasCost, bool server);
    event DedicatedServerMsgSender(address indexed sender, bool allowed);
    event Delays(uint delayServer, uint);
    event MaxHwPerCall(uint maxHwPerCall_);
    event VaultExcludeStatusChanged(address vault, bool status);

    /// @notice Default delay between HardWorks
    function getDelay() external view returns (uint delayServer);

    /// @notice Vaults that excluded from HardWork execution
    function excludedVaults(address vault) external view returns (bool);

    /// @notice Maximum vault HardWork calls per execution
    function maxHwPerCall() external view returns (uint);

    /// @notice Check dedicated server address allowance for execute vault HardWorks
    function dedicatedServerMsgSender(address sender) external view returns (bool allowed);

    /// @notice Checker method for calling from server script
    /// @return canExec Hard Work can be executed
    /// @return execPayload Vault addresses for HardWork
    function checkerServer() external view returns (bool canExec, bytes memory execPayload);

    /// @notice Setup allowance status for dedicated server address
    function setDedicatedServerMsgSender(address sender, bool allowed) external;

    /// @notice Setup delays between HardWorks in seconds
    /// @param delayServer_ Delay for server script
    function setDelay(uint delayServer_) external;

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
    /// @param vaults Addresses of vault from checkerServer output
    function call(address[] memory vaults) external;
}
