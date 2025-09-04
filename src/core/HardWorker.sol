// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Controllable} from "./base/Controllable.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {VaultStatusLib} from "./libs/VaultStatusLib.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IVaultManager} from "../interfaces/IVaultManager.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IHardWorker} from "../interfaces/IHardWorker.sol";

/// @notice HardWork resolver and caller.
/// Executor is server script.
/// Changelog:
///   1.1.0: remove Gelato support
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
contract HardWorker is Controllable, IHardWorker {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.1.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.HardWorker")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant HARDWORKER_STORAGE_LOCATION =
        0xb27d1d090fdefd817c9451b2e705942c4078dc680872cd693dd4ae2b2aaa9000;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.HardWorker
    struct HardWorkerStorage {
        mapping(address => bool) excludedVaults;
        mapping(address caller => bool allowed) dedicatedServerMsgSender;
        address __deprecated1;
        address __deprecated2;
        bytes32 __deprecated3;
        uint __deprecated4;
        uint __deprecated5;
        uint delayServer;
        uint __deprecated6;
        uint maxHwPerCall;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    //slither-disable-next-line reentrancy-events
    function initialize(address platform_) public payable initializer {
        __Controllable_init(platform_);

        HardWorkerStorage storage $ = _getStorage();
        $.delayServer = 11 hours;

        emit Delays(11 hours, 0);

        $.maxHwPerCall = 5;
        emit MaxHwPerCall(5);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CALLBACKS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    receive() external payable {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IHardWorker
    function setDedicatedServerMsgSender(address sender, bool allowed) external onlyGovernanceOrMultisig {
        HardWorkerStorage storage $ = _getStorage();
        if ($.dedicatedServerMsgSender[sender] == allowed) {
            revert AlreadyExist();
        }
        $.dedicatedServerMsgSender[sender] = allowed;
        emit DedicatedServerMsgSender(sender, allowed);
    }

    /// @inheritdoc IHardWorker
    function setDelay(uint delayServer_) external onlyGovernanceOrMultisig {
        HardWorkerStorage storage $ = _getStorage();
        // nosemgrep
        if ($.delayServer == delayServer_) {
            revert AlreadyExist();
        }
        $.delayServer = delayServer_;
        emit Delays(delayServer_, 0);
    }

    /// @inheritdoc IHardWorker
    //slither-disable-next-line similar-names
    function setMaxHwPerCall(uint maxHwPerCall_) external onlyOperator {
        HardWorkerStorage storage $ = _getStorage();
        if (maxHwPerCall_ <= 0) {
            revert IControllable.IncorrectZeroArgument();
        }
        $.maxHwPerCall = maxHwPerCall_;
        emit MaxHwPerCall(maxHwPerCall_);
    }

    /// @inheritdoc IHardWorker
    function changeVaultExcludeStatus(address[] memory vaults_, bool[] memory status) external onlyOperator {
        HardWorkerStorage storage $ = _getStorage();
        uint len = vaults_.length;
        if (len != status.length || len == 0) {
            revert IControllable.IncorrectArrayLength();
        }
        IFactory factory = IFactory(IPlatform(platform()).factory());
        // nosemgrep
        for (uint i; i < len; ++i) {
            // calls-loop here is not dangerous
            //slither-disable-next-line calls-loop
            if (factory.vaultStatus(vaults_[i]) == VaultStatusLib.NOT_EXIST) {
                revert NotExistWithObject(vaults_[i]);
            }
            if ($.excludedVaults[vaults_[i]] == status[i]) {
                revert AlreadyExclude(vaults_[i]);
            } else {
                $.excludedVaults[vaults_[i]] = status[i];
                emit VaultExcludeStatusChanged(vaults_[i], status[i]);
            }
        }
    }

    /// @inheritdoc IHardWorker
    //slither-disable-next-line cyclomatic-complexity
    function call(address[] memory vaults) external {
        HardWorkerStorage storage $ = _getStorage();

        uint startGas = gasleft();

        require($.dedicatedServerMsgSender[msg.sender], NotServer());

        uint _maxHwPerCall = $.maxHwPerCall;
        uint vaultsLength = vaults.length;
        uint counter;
        for (uint i; i < vaultsLength; ++i) {
            IVault vault = IVault(vaults[i]);
            //slither-disable-next-line calls-loop
            try vault.doHardWork() {}
            catch Error(string memory _err) {
                revert(string(abi.encodePacked("Vault error: 0x", Strings.toHexString(address(vault)), " ", _err)));
            } catch (bytes memory _err) {
                revert(
                    string(
                        abi.encodePacked(
                            "Vault low-level error: 0x", Strings.toHexString(address(vault)), " ", string(_err)
                        )
                    )
                );
            }
            ++counter;
            if (counter >= _maxHwPerCall) {
                break;
            }
        }

        uint gasUsed = startGas - gasleft();
        uint gasCost = gasUsed * tx.gasprice;
        if (gasCost > 0 && address(this).balance >= gasCost) {
            //slither-disable-next-line low-level-calls
            (bool success,) = msg.sender.call{value: gasCost}("");
            if (!success) {
                revert IControllable.ETHTransferFailed();
            }
        }
        //slither-disable-end unused-return
        emit Call(counter, gasUsed, gasCost, true);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function getDelay() external view returns (uint delayServer) {
        delayServer = _getStorage().delayServer;
    }

    /// @inheritdoc IHardWorker
    function dedicatedServerMsgSender(address sender) external view returns (bool allowed) {
        return _getStorage().dedicatedServerMsgSender[sender];
    }

    /// @inheritdoc IHardWorker
    function maxHwPerCall() external view returns (uint) {
        return _getStorage().maxHwPerCall;
    }

    /// @inheritdoc IHardWorker
    function checkerServer() external view returns (bool canExec, bytes memory execPayload) {
        return _checker(_getStorage().delayServer);
    }

    /// @inheritdoc IHardWorker
    function excludedVaults(address vault) external view returns (bool) {
        return _getStorage().excludedVaults[vault];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getStorage() private pure returns (HardWorkerStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := HARDWORKER_STORAGE_LOCATION
        }
    }

    function _checker(uint delay_) internal view returns (bool canExec, bytes memory execPayload) {
        HardWorkerStorage storage $ = _getStorage();
        IPlatform _platform = IPlatform(platform());
        IFactory factory = IFactory(_platform.factory());
        address[] memory vaults = IVaultManager(_platform.vaultManager()).vaultAddresses();
        uint len = vaults.length;
        address[] memory vaultsForHardWork = new address[](len);
        //slither-disable-next-line uninitialized-local
        uint counter;
        // nosemgrep
        for (uint i; i < len; ++i) {
            if ($.excludedVaults[vaults[i]]) {
                continue;
            }

            IVault vault = IVault(vaults[i]);
            IStrategy strategy = vault.strategy();
            //slither-disable-next-line unused-return
            (uint tvl,) = vault.tvl();
            // nosemgrep
            if (
                //slither-disable-next-line timestamp
                tvl > 0 && block.timestamp - strategy.lastHardWork() > delay_
                    && factory.vaultStatus(vaults[i]) == VaultStatusLib.ACTIVE
            ) {
                ++counter;
                vaultsForHardWork[i] = vaults[i];
            }
        }

        if (counter == 0) {
            return (false, bytes("No ready vaults"));
        } else {
            address[] memory vaultsResult = new address[](counter);
            uint j;
            // nosemgrep
            for (uint i; i < len; ++i) {
                if (vaultsForHardWork[i] == address(0)) {
                    continue;
                }

                vaultsResult[j] = vaultsForHardWork[i];
                ++j;
            }

            return (true, abi.encodeWithSelector(HardWorker.call.selector, vaultsResult));
        }
    }
}
