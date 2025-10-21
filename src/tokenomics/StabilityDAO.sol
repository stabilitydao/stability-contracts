// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Controllable, IControllable} from "../core/base/Controllable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20BurnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {IStabilityDAO} from "../interfaces/IStabilityDAO.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @title Stability DAO Token contract
/// Amount of tokens for each user represents their voting power in the DAO.
/// Only user with high enough amount of staked xSTBL have DAO-tokens.
/// Tokens are non-transferable, can be only minted and burned by XStaking contract.
/// @author Omriss (https://github.com/omriss)
/// Changelog:
contract StabilityDAO is
    Controllable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IStabilityDAO
{
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.StabilityDAO")) - 1)) & ~bytes32(uint(0xff));
    bytes32 private constant _STABILITY_DAO_TOKEN_STORAGE_LOCATION = 0; // todo

    //region ----------------------------------- Data types
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.StabilityDAO
    struct StabilityDaoStorage {
        /// @dev Mapping is used to be able to add new fields to DaoParams struct in future, only config[0] is used
        mapping(uint => DaoParams) config;
        /// @notice Address of XSTBL token
        address xStbl;
        /// @notice Address of xStaking contract
        address xStaking;
        /// @notice Address to which a user has delegated his vote power
        mapping(address user => address delegatedTo) delegatedTo;
        /// @notice Set of addresses that have delegated their vote power to a user
        mapping(address user => EnumerableSet.AddressSet) delegatedFrom;
    }

    error NonTransferable();
    error NotDelegatedTo();
    error AlreadyDelegated();

    event ConfigUpdated(DaoParams newConfig);
    event DelegateVotes(address from, address to); // todo move to interface?
    event UnDelegateVotes(address from, address to);

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
        StabilityDaoStorage storage $ = _getStorage();
        $.xStaking = xStaking_;
        $.xStbl = xStbl_;
        $.config[0] = p;
    }

    //endregion ----------------------------------- Initialization and modifiers

    //region ----------------------------------- Actions
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
        StabilityDaoStorage storage $ = _getStorage();
        $.config[0] = p;

        emit ConfigUpdated(p);
    }

    /// @inheritdoc IStabilityDAO
    function setPowerDelegation(address to) external nonReentrant {
        // anyone can call this function

        StabilityDaoStorage storage $ = _getStorage();

        if (to == msg.sender || to == address(0)) {
            address delegatee = $.delegatedTo[msg.sender];
            $.delegatedTo[msg.sender] = address(0);

            //slither-disable-next-line unused-return
            EnumerableSet.remove($.delegatedFrom[delegatee], msg.sender);

            emit UnDelegateVotes(msg.sender, to);
        } else {
            require($.delegatedTo[msg.sender] == address(0), AlreadyDelegated());
            $.delegatedTo[msg.sender] = to;

            //slither-disable-next-line unused-return
            EnumerableSet.add($.delegatedFrom[to], msg.sender);

            emit DelegateVotes(msg.sender, to);
        }
    }

    //endregion ----------------------------------- Actions

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
    function quorum() external view returns (uint) {
        return _getStorage().config[0].quorum;
    }

    /// @inheritdoc IStabilityDAO
    function powerAllocationDelay() external view returns (uint) {
        return _getStorage().config[0].powerAllocationDelay;
    }

    /// @inheritdoc IStabilityDAO
    function userPower(address user_) public view returns (uint) {
        StabilityDaoStorage storage $ = _getStorage();
        uint power = $.delegatedTo[user_] == address(0) ? balanceOf(user_) : 0;

        address[] memory delegated = EnumerableSet.values($.delegatedFrom[user_]);
        uint len = delegated.length;
        for (uint i; i < len; ++i) {
            power += balanceOf(delegated[i]);
        }

        return power;
    }

    /// @inheritdoc IStabilityDAO
    function delegates(address user_) external view returns (address delegatedTo, address[] memory delegatedFrom) {
        StabilityDaoStorage storage $ = _getStorage();
        return ($.delegatedTo[user_], EnumerableSet.values($.delegatedFrom[user_]));
    }

    //endregion ----------------------------------- View functions

    //region ----------------------------------- Internal logic
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _requireXStaking() internal view {
        require(_getStorage().xStaking == msg.sender, IncorrectMsgSender());
    }

    function _getStorage() internal pure returns (StabilityDaoStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _STABILITY_DAO_TOKEN_STORAGE_LOCATION
        }
    }
    //endregion ----------------------------------- Internal logic
}
