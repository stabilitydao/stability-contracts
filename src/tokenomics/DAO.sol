// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Controllable, IControllable} from "../core/base/Controllable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20BurnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {IStabilityDAO} from "../interfaces/IStabilityDAO.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ConstantsLib} from "../core/libs/ConstantsLib.sol";

/// @title Stability DAO Token contract
/// Amount of tokens for each user represents their voting power in the DAO.
/// Only users with high enough amount of staked xSTBL have DAO-tokens.
/// Tokens are non-transferable and can be only minted and burned by XStaking contract.
/// @author Omriss (https://github.com/omriss)
/// Changelog:
///  1.1.0: getVotes returns total voting power for all chains. Add setOtherChainsPowers + whitelist.
///         initialize() has two new params: name and symbol - #424
///  1.0.1: userPower is renamed to getVotes (compatibility with OpenZeppelin's ERC20Votes) - #423
contract DAO is Controllable, ERC20Upgradeable, ERC20BurnableUpgradeable, ReentrancyGuardUpgradeable, IStabilityDAO {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.1.0";

    /// @notice Power location kinds for getVotes function. 0 - total, 1 - current chain, 2 - other chains
    uint internal constant POWER_LOCATION_TOTAL_0 = 0;
    uint internal constant POWER_LOCATION_CURRENT_CHAIN_1 = 1;
    uint internal constant POWER_LOCATION_OTHER_CHAINS_2 = 2;

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.StabilityDAO")) - 1)) & ~bytes32(uint(0xff));
    bytes32 private constant _STABILITY_DAO_TOKEN_STORAGE_LOCATION =
        0xb41400b8ab7d5c4f4647f6397fc72c137345511eb9c9a0082de7fe729c2ae200; // StabilityDAO name is used historically

    /// @dev Same to XSTBL.DENOMINATOR
    uint internal constant DENOMINATOR_XSTBL = 10_000;

    //region ----------------------------------- Data types
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Voting power of the users on other chains
    struct OtherChainsPowers {
        /// @notice Voting powers of users on other chains
        EnumerableMap.AddressToUintMap powers;

        /// @notice Timestamp of OtherChainsPowers-data creation
        uint timestamp;
    }

    /// @custom:storage-location erc7201:stability.StabilityDAO
    struct DaoStorage {
        /// @dev Mapping is used to be able to add new fields to DaoParams struct in future, only config[0] is used
        mapping(uint => DaoParams) config;
        /// @notice Address of XSTBL token
        address xStbl;
        /// @notice Address of xStaking contract
        address xStaking;
        /// @notice Address to which a user has delegated his vote power
        mapping(address user => address) delegatedTo;
        /// @notice Set of addresses that have delegated their vote power to a user
        mapping(address user => EnumerableSet.AddressSet) delegators;

        /// @notice Single instance of OtherChainsPowers stored for address(0).
        /// Map is used to update all data by single write operation
        mapping(address zeroAddress => OtherChainsPowers) otherChainsPowers;

        /// @notice Whitelist for addresses allowed to update OtherChainsPowers
        mapping(address user => bool allowed) otherChainsPowersWhitelist;

        /// @notice Is delegation of voting power on the current chain forbidden
        /// Basically delegation must be forbidden on all chains except main one (sonic for Stability)
        bool delegationForbidden;
    }

    error NonTransferable();
    error NotDelegatedTo();
    error AlreadyDelegated();
    error WrongValue();
    error NotOtherChainsPowersWhitelisted();
    error DelegationForbiddenOnTheChain();

    event ConfigUpdated(DaoParams newConfig);
    event DelegatePower(address from, address to);
    event UnDelegatePower(address from, address to);
    event WhitelistOtherChainsPowers(address user, bool whitelisted);
    event PowersOtherChainsUpdated(uint timestamp);
    event SetDelegationForbiddenOnTheChain(bool forbidden);

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
    function initialize(
        address platform_,
        address xStbl_,
        address xStaking_,
        DaoParams memory p,
        string memory name_,
        string memory symbol_
    ) public initializer {
        __Controllable_init(platform_);
        __ERC20_init(name_, symbol_); // "Stability DAO", "STBL_DAO"
        DaoStorage storage $ = _getDaoStorage();
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
        DaoStorage storage $ = _getDaoStorage();

        require(p.exitPenalty < DENOMINATOR_XSTBL, WrongValue());
        require(p.quorum < ConstantsLib.DENOMINATOR && p.proposalThreshold < ConstantsLib.DENOMINATOR, WrongValue());

        $.config[0] = p;

        emit ConfigUpdated(p);
    }

    /// @inheritdoc IStabilityDAO
    function setPowerDelegation(address to) external nonReentrant {
        // anyone can call this function

        DaoStorage storage $ = _getDaoStorage();

        if (to == msg.sender || to == address(0)) {
            address delegatee = $.delegatedTo[msg.sender];
            $.delegatedTo[msg.sender] = address(0);

            //slither-disable-next-line unused-return
            EnumerableSet.remove($.delegators[delegatee], msg.sender);

            emit UnDelegatePower(msg.sender, to);
        } else {
            require(!$.delegationForbidden, DelegationForbiddenOnTheChain());
            require($.delegatedTo[msg.sender] == address(0), AlreadyDelegated());
            $.delegatedTo[msg.sender] = to;

            //slither-disable-next-line unused-return
            EnumerableSet.add($.delegators[to], msg.sender);

            emit DelegatePower(msg.sender, to);
        }
    }

    /// @inheritdoc IStabilityDAO
    function setWhitelistedForOtherChainsPowers(address user, bool whitelisted) external onlyGovernanceOrMultisig {
        DaoStorage storage $ = _getDaoStorage();
        $.otherChainsPowersWhitelist[user] = whitelisted;

        emit WhitelistOtherChainsPowers(user, whitelisted);
    }

    /// @inheritdoc IStabilityDAO
    function updateOtherChainsPowers(address[] memory users, uint[] memory powers) external {
        DaoStorage storage $ = _getDaoStorage();
        require($.otherChainsPowersWhitelist[msg.sender], NotOtherChainsPowersWhitelisted());

        uint len = users.length;
        require(len == powers.length, IControllable.IncorrectArrayLength());

        delete $.otherChainsPowers[address(0)];
        OtherChainsPowers storage poc = $.otherChainsPowers[address(0)];

        for (uint i; i < len; ++i) {
            poc.powers.set(users[i], powers[i]);
        }

        poc.timestamp = block.timestamp;
        emit PowersOtherChainsUpdated(block.timestamp);
    }

    /// @inheritdoc IStabilityDAO
    function setDelegationForbidden(bool forbidden) external onlyGovernanceOrMultisig {
        DaoStorage storage $ = _getDaoStorage();
        $.delegationForbidden = forbidden;

        emit SetDelegationForbiddenOnTheChain(forbidden);
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
        return _getDaoStorage().config[0];
    }

    /// @inheritdoc IStabilityDAO
    function xStbl() public view returns (address) {
        return _getDaoStorage().xStbl;
    }

    /// @inheritdoc IStabilityDAO
    function xStaking() public view returns (address) {
        return _getDaoStorage().xStaking;
    }

    /// @inheritdoc IStabilityDAO
    function minimalPower() external view returns (uint) {
        return _getDaoStorage().config[0].minimalPower;
    }

    /// @inheritdoc IStabilityDAO
    function exitPenalty() external view returns (uint) {
        return _getDaoStorage().config[0].exitPenalty;
    }

    /// @inheritdoc IStabilityDAO
    function proposalThreshold() external view returns (uint) {
        return _getDaoStorage().config[0].proposalThreshold;
    }

    /// @inheritdoc IStabilityDAO
    function quorum() external view returns (uint) {
        return _getDaoStorage().config[0].quorum;
    }

    /// @inheritdoc IStabilityDAO
    function powerAllocationDelay() external view returns (uint) {
        return _getDaoStorage().config[0].powerAllocationDelay;
    }

    /// @inheritdoc IStabilityDAO
    function getVotes(address user_) public view returns (uint) {
        return _getVotesPower(user_, true, true, true);
    }

    /// @inheritdoc IStabilityDAO
    function getVotesPower(address user_, uint powerLocation_) external view returns (uint) {
        if (powerLocation_ == POWER_LOCATION_TOTAL_0) {
            return _getVotesPower(user_, true, true, false);
        } else if (powerLocation_ == POWER_LOCATION_CURRENT_CHAIN_1) {
            return _getVotesPower(user_, true, false, false);
        } else if (powerLocation_ == POWER_LOCATION_OTHER_CHAINS_2) {
            return _getVotesPower(user_, false, true, false);
        }

        return 0;
    }

    /// @inheritdoc IStabilityDAO
    function delegates(address user_) external view returns (address delegatedTo, address[] memory delegators) {
        DaoStorage storage $ = _getDaoStorage();
        return ($.delegatedTo[user_], EnumerableSet.values($.delegators[user_]));
    }

    /// @inheritdoc IStabilityDAO
    function getOtherChainsPowers()
        external
        view
        returns (uint timestamp, address[] memory users, uint[] memory powers)
    {
        DaoStorage storage $ = _getDaoStorage();
        OtherChainsPowers storage poc = $.otherChainsPowers[address(0)];

        uint len = poc.powers.length();
        users = new address[](len);
        powers = new uint[](len);
        for (uint i; i < len; ++i) {
            (address user, uint power) = poc.powers.at(i);
            users[i] = user;
            powers[i] = power;
        }

        timestamp = poc.timestamp;
    }

    /// @inheritdoc IStabilityDAO
    function isWhitelistedForOtherChainsPowers(address user_) external view returns (bool) {
        return _getDaoStorage().otherChainsPowersWhitelist[user_];
    }

    /// @inheritdoc IStabilityDAO
    function delegationForbidden() external view returns (bool) {
        return _getDaoStorage().delegationForbidden;
    }

    //endregion ----------------------------------- View functions

    //region ----------------------------------- Voting power calculation

    /// @notice Get voting power of a user on the current chain
    function _getVotesPower(address user_, bool local, bool other, bool allowDelegation) internal view returns (uint) {
        DaoStorage storage $ = _getDaoStorage();
        EnumerableMap.AddressToUintMap storage _otherPowers = $.otherChainsPowers[address(0)].powers;

        uint localPower = local ? $.delegatedTo[user_] == address(0) || !allowDelegation ? balanceOf(user_) : 0 : 0;

        uint otherPower = other ? _otherPowers.contains(user_) ? _otherPowers.get(user_) : 0 : 0;

        if (allowDelegation && !$.delegationForbidden) {
            address[] memory delegators = EnumerableSet.values($.delegators[user_]);
            uint len = delegators.length;
            for (uint i; i < len; ++i) {
                localPower += balanceOf(delegators[i]);
                otherPower += _otherPowers.contains(delegators[i]) ? _otherPowers.get(delegators[i]) : 0;
            }
        }

        return localPower + otherPower;
    }
    //endregion ----------------------------------- Voting power calculation

    //region ----------------------------------- Internal logic
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _requireXStaking() internal view {
        require(_getDaoStorage().xStaking == msg.sender, IncorrectMsgSender());
    }

    function _getDaoStorage() internal pure returns (DaoStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _STABILITY_DAO_TOKEN_STORAGE_LOCATION
        }
    }
    //endregion ----------------------------------- Internal logic
}
