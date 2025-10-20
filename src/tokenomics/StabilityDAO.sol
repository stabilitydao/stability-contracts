// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Controllable, IControllable} from "../core/base/Controllable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {IStabilityDAO} from "../interfaces/IStabilityDAO.sol";

/// @title Stability DAO Token contract
/// Amount of tokens for each user represents their voting power in the DAO.
/// Only user with high enough amount of staked xSTBL have DAO-tokens.
/// Tokens are non-transferable, can be only minted and burned by XStaking contract.
/// @author Omriss (https://github.com/omriss)
/// Changelog:
contract StabilityDAO is Controllable, ERC20Upgradeable, ERC20BurnableUpgradeable, IStabilityDAO {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.StabilityDAO")) - 1)) & ~bytes32(uint(0xff));
    bytes32 private constant _STABILITY_DAO_TOKEN_STORAGE_LOCATION =
        0x646b4833d597962e1309a1f3fa0c9ce18df08fcf8941b92012e02e0045f00200;

    //region ----------------------------------- Data types
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.StabilityDAO
    struct StabilityDAOStorage {
        /// @dev Mapping is used to be able to add new fields to DaoParams struct in future, only config[0] is used
        mapping(uint => DaoParams) config;
        /// @notice Address of XSTBL token
        address xStbl;
        /// @notice Address of xStaking contract
        address xStaking;
    }

    error NonTransferable();

    event ConfigUpdated(DaoParams newConfig);

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

    /// @inheritdoc IStabilityDAO
    function initialize(address platform_, address xStbl_, address xStaking_, DaoParams memory p) public initializer {
        __Controllable_init(platform_);
        __ERC20_init("Stability DAO", "STBL_DAO");
        StabilityDAOStorage storage $ = _getStorage();
        $.xStaking = xStaking_;
        $.xStbl = xStbl_;
        $.config[0] = p;
    }
    //endregion ----------------------------------- Initialization and modifiers

    //region ----------------------------------- Restricted actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStabilityDAO
    function mint(address account, uint amount) external onlyXStaking {
        _mint(account, amount);
    }

    /// @inheritdoc IStabilityDAO
    function burn(address account, uint amount) external onlyXStaking {
        _burn(account, amount);
    }

    /// @inheritdoc IStabilityDAO
    function updateConfig(DaoParams memory p) external onlyGovernanceOrMultisig {
        StabilityDAOStorage storage $ = _getStorage();
        $.config[0] = p;

        emit ConfigUpdated(p);
    }

    //endregion ----------------------------------- Restricted actions

    //region ----------------------------------- ERC20 hooks
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERC20 HOOKS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The token is not transferable, only minting and burning is allowed
    function _update(address from, address to, uint value) internal override {
        require(from == address(0) || to == address(0), NonTransferable());

        super._update(from, to, value);
    }
    //endregion ----------------------------------- ERC20 hooks

    //region ----------------------------------- View functions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStabilityDAO
    function config() public view returns (DaoParams memory) {
        return _getStorage().config[0];
    }

    /// @inheritdoc IStabilityDAO
    function xStbl() public view returns (address) {
        return _getStorage().xStbl;
    }

    /// @inheritdoc IStabilityDAO
    function xStaking() public view returns (address) {
        return _getStorage().xStaking;
    }

    /// @inheritdoc IStabilityDAO
    function minimalPower() external view returns (uint) {
        return _getStorage().config[0].minimalPower;
    }

    /// @inheritdoc IStabilityDAO
    function exitPenalty() external view returns (uint) {
        return _getStorage().config[0].exitPenalty;
    }

    /// @inheritdoc IStabilityDAO
    function proposalThreshold() external view returns (uint) {
        return _getStorage().config[0].proposalThreshold;
    }

    /// @inheritdoc IStabilityDAO
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

    function _getStorage() internal pure returns (StabilityDAOStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _STABILITY_DAO_TOKEN_STORAGE_LOCATION
        }
    }
    //endregion ----------------------------------- Internal logic
}
