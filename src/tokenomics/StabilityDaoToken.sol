// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Controllable, IControllable, IPlatform} from "../core/base/Controllable.sol";
import {ERC20Upgradeable, IERC20Metadata} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {IStabilityDaoToken} from "../interfaces/IStabilityDaoToken.sol";

/// @title Incident impact recovery token
/// @author Omriss (https://github.com/omriss)
/// Changelog:
contract StabilityDaoToken is Controllable, ERC20Upgradeable, ERC20BurnableUpgradeable, IStabilityDaoToken {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.StabilityDaoToken")) - 1)) & ~bytes32(uint(0xff));
    bytes32 private constant _STABILITY_DAO_TOKEN_STORAGE_LOCATION = 0; // todo

    //region ----------------------------------- Data types
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.StabilityDaoToken
    struct StabilityDaoTokenStorage {
        /// @dev Mapping is used to be able to add new fields to DaoParams struct in future, only pausedAccounts[0] is used
        mapping(uint => DaoParams) config;

        /// @notice Address of XSTBL token
        address xStbl;

        /// @notice Address of xStaking contract
        address xStaking;
    }

    error IncorrectMsgSender();
    error NonTransferable();

    //endregion ----------------------------------- Data types

    //region ----------------------------------- Initialization and modifiers
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      MODIFIERS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    modifier onlyXStaking() virtual {
        _requireXStaking();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStabilityDaoToken
    function initialize(address platform_, address xStbl_, address xStaking_, DaoParams memory p) public initializer {
        __Controllable_init(platform_);
        __ERC20_init("Stability DAO", "STBLDAO");
        StabilityDaoTokenStorage storage $ = _getStorage();
        $.xStaking = xStaking_;
        $.xStbl = xStbl_;
        $.config[0] = p;
    }
    //endregion ----------------------------------- Initialization and modifiers

    //region ----------------------------------- Restricted actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStabilityDaoToken
    function mint(address account, uint amount) external onlyXStaking {
        _mint(account, amount);
    }

    /// @inheritdoc IStabilityDaoToken
    function burn(address account, uint amount) external onlyXStaking {
        _burn(account, amount);
    }

    /// @inheritdoc IStabilityDaoToken
    function updateConfig(DaoParams memory p) external onlyMultisig {
        StabilityDaoTokenStorage storage $ = _getStorage();
        $.config[0] = p;
    }

    //endregion ----------------------------------- Restricted actions

    //region ----------------------------------- ERC20 hooks
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERC20 HOOKS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _update(address from, address to, uint256 value) internal override {
        require(from == address(0) || to == address(0), NonTransferable());

        super._update(from, to, value);
    }
    //endregion ----------------------------------- ERC20 hooks

    //region ----------------------------------- View functions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStabilityDaoToken
    function config() public view returns (DaoParams memory) {
        return _getStorage().config[0];
    }

    /// @inheritdoc IStabilityDaoToken
    function xStbl() public view returns (address) {
        return _getStorage().xStbl;
    }

    /// @inheritdoc IStabilityDaoToken
    function xStaking() public view returns (address) {
        return _getStorage().xStaking;
    }

    /// @inheritdoc IStabilityDaoToken
    function minimalPower() external view returns (uint) {
        return _getStorage().config[0].minimalPower;
    }

    /// @inheritdoc IStabilityDaoToken
    function exitPenalty() external view returns (uint) {
        return _getStorage().config[0].exitPenalty;
    }

    /// @inheritdoc IStabilityDaoToken
    function proposalThreshold() external view returns (uint) {
        return _getStorage().config[0].proposalThreshold;
    }

    /// @inheritdoc IStabilityDaoToken
    function powerAllocationDelay() external view returns (uint) {
        return _getStorage().config[0].powerAllocationDelay;
    }

    //endregion ----------------------------------- View functions

    //region ----------------------------------- Internal logic
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _requireXStaking() internal view {
        require(_getStorage().xStaking == msg.sender, IncorrectMsgSender());
    }

    function _requireXStakingOrMultisig() internal view {
        address _xStaking = _getStorage().xStaking;
        address multisig = IPlatform(platform()).multisig();
        require(_xStaking == msg.sender || multisig == msg.sender, IncorrectMsgSender());
    }

    function _getStorage() internal pure returns (StabilityDaoTokenStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _STABILITY_DAO_TOKEN_STORAGE_LOCATION
        }
    }
    //endregion ----------------------------------- Internal logic
}

