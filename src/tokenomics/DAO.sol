// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Controllable, IControllable} from "../core/base/Controllable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20BurnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {IDAO} from "../interfaces/IDAO.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ConstantsLib} from "../core/libs/ConstantsLib.sol";

/// @title Stability DAO Token contract
/// Amount of tokens for each user represents their voting power in the DAO.
/// Only users with high enough amount of staked xToken have DAO-tokens.
/// Tokens are non-transferable and can be only minted and burned by XStaking contract.
/// @author Omriss (https://github.com/omriss)
/// Changelog:
///  1.1.0: getVotes returns total voting power for all chains. Add setOtherChainsPowers + whitelist.
///         initialize() has two new params: name and symbol. Contract renamed from StabilityDAO to DAO
///         Allow to forbid delegation - #424
///  1.0.1: userPower is renamed to getVotes (compatibility with OpenZeppelin's ERC20Votes) - #423
contract DAO is Controllable, ERC20Upgradeable, ERC20BurnableUpgradeable, ReentrancyGuardUpgradeable, IDAO {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.1.0";

    /// @dev Name "erc7201:stability.StabilityDAO" is used historically
    // keccak256(abi.encode(uint(keccak256("erc7201:stability.StabilityDAO")) - 1)) & ~bytes32(uint(0xff));
    bytes32 private constant _DAO_TOKEN_STORAGE_LOCATION =
        0xb41400b8ab7d5c4f4647f6397fc72c137345511eb9c9a0082de7fe729c2ae200; // StabilityDAO name is used historically

    /// @dev Same to xToken.DENOMINATOR
    uint internal constant DENOMINATOR_XTOKEN = 10_000;

    //region ----------------------------------- Data types
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Voting power of the users on other chains
    /// @dev We keep it in a separate struct to be able to update all data by single write operation
    struct OtherChainsPowers {
        /// @notice Voting powers of users on other chains
        EnumerableMap.AddressToUintMap powers;
    }

    /// @custom:storage-location erc7201:stability.StabilityDAO
    struct DaoStorage {
        /// @dev Mapping is used to be able to add new fields to DaoParams struct in future, only config[0] is used
        mapping(uint => DaoParams) config;
        /// @notice Address of xToken
        address xToken;
        /// @notice Address of xStaking contract
        address xStaking;
        /// @notice Address to which a user has delegated his vote power
        mapping(address user => address) delegatedTo;
        /// @notice Set of addresses that have delegated their vote power to a user
        mapping(address user => EnumerableSet.AddressSet) delegators;

        /// @notice Epoch of the last update of OtherChainsPowers. Each call of updateOtherChainsPowers increases it.
        /// @dev It's timestamp of the block when otherChainsPowers were updated last time
        uint otherChainsEpoch;

        /// @notice Active instance of OtherChainsPowers stored for key = {otherChainsEpoch}
        /// Map is used to update all data by single write operation
        mapping(uint epoch => OtherChainsPowers) otherChainsPowers;

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

    /// @inheritdoc IDAO
    function initialize(
        address platform_,
        address xToken_,
        address xStaking_,
        DaoParams memory p,
        string memory name_,
        string memory symbol_
    ) public initializer {
        __Controllable_init(platform_);
        __ERC20_init(name_, symbol_); // i.e. "Stability DAO", "STBL_DAO"
        DaoStorage storage $ = _getDaoStorage();
        $.xStaking = xStaking_;
        $.xToken = xToken_;
        $.config[0] = p;
    }

    //endregion ----------------------------------- Initialization and modifiers

    //region ----------------------------------- Actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IDAO
    function mint(address account, uint amount) external onlyXStaking {
        _mint(account, amount);
    }

    /// @inheritdoc IDAO
    function burn(address account, uint amount) external onlyXStaking {
        _burn(account, amount);
    }

    /// @inheritdoc IDAO
    function updateConfig(DaoParams memory p) external onlyGovernanceOrMultisig {
        DaoStorage storage $ = _getDaoStorage();

        require(p.exitPenalty < DENOMINATOR_XTOKEN, WrongValue());
        require(p.quorum < ConstantsLib.DENOMINATOR && p.proposalThreshold < ConstantsLib.DENOMINATOR, WrongValue());

        $.config[0] = p;

        emit ConfigUpdated(p);
    }

    /// @inheritdoc IDAO
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

    /// @inheritdoc IDAO
    function setWhitelistedForOtherChainsPowers(address user, bool whitelisted) external onlyGovernanceOrMultisig {
        DaoStorage storage $ = _getDaoStorage();
        $.otherChainsPowersWhitelist[user] = whitelisted;

        emit WhitelistOtherChainsPowers(user, whitelisted);
    }

    /// @inheritdoc IDAO
    function updateOtherChainsPowers(address[] memory users, uint[] memory powers) external {
        DaoStorage storage $ = _getDaoStorage();
        require($.otherChainsPowersWhitelist[msg.sender], NotOtherChainsPowersWhitelisted());

        uint len = users.length;
        require(len == powers.length, IControllable.IncorrectArrayLength());

        uint epoch = block.timestamp;
        require(epoch > $.otherChainsEpoch, WrongValue()); // just for safety forbid double update in the same block
        $.otherChainsEpoch = epoch;

        OtherChainsPowers storage poc = $.otherChainsPowers[epoch];

        for (uint i; i < len; ++i) {
            // slither-disable-next-line unused-return
            poc.powers.set(users[i], powers[i]);
        }

        emit PowersOtherChainsUpdated(block.timestamp);
    }

    /// @inheritdoc IDAO
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

    /// @inheritdoc IDAO
    function config() public view returns (DaoParams memory) {
        return _getDaoStorage().config[0];
    }

    /// @inheritdoc IDAO
    function xToken() public view returns (address) {
        return _getDaoStorage().xToken;
    }

    /// @inheritdoc IDAO
    function xStaking() public view returns (address) {
        return _getDaoStorage().xStaking;
    }

    /// @inheritdoc IDAO
    function minimalPower() external view returns (uint) {
        return _getDaoStorage().config[0].minimalPower;
    }

    /// @inheritdoc IDAO
    function exitPenalty() external view returns (uint) {
        return _getDaoStorage().config[0].exitPenalty;
    }

    /// @inheritdoc IDAO
    function proposalThreshold() external view returns (uint) {
        return _getDaoStorage().config[0].proposalThreshold;
    }

    /// @inheritdoc IDAO
    function quorum() external view returns (uint) {
        return _getDaoStorage().config[0].quorum;
    }

    /// @inheritdoc IDAO
    function powerAllocationDelay() external view returns (uint) {
        return _getDaoStorage().config[0].powerAllocationDelay;
    }

    /// @inheritdoc IDAO
    function getVotes(address user_) public view returns (uint votes) {
        DaoStorage storage $ = _getDaoStorage();
        if ($.delegatedTo[user_] == address(0)) {
            (uint localPower, uint otherPower) = _getPowers($, user_);
            votes = localPower + otherPower;
        }

        if (!$.delegationForbidden) {
            EnumerableMap.AddressToUintMap storage _otherPowers = $.otherChainsPowers[$.otherChainsEpoch].powers;
            address[] memory delegators = EnumerableSet.values($.delegators[user_]);
            uint len = delegators.length;
            for (uint i; i < len; ++i) {
                votes += balanceOf(delegators[i]);
                votes += _otherPowers.contains(delegators[i]) ? _otherPowers.get(delegators[i]) : 0;
            }
        }

        return votes;
    }

    /// @inheritdoc IDAO
    function getPowers(address user_) external view returns (uint localPower, uint otherPower) {
        (localPower, otherPower) = _getPowers(_getDaoStorage(), user_);
    }

    /// @inheritdoc IDAO
    function delegates(address user_) external view returns (address delegatedTo, address[] memory delegators) {
        DaoStorage storage $ = _getDaoStorage();
        return ($.delegatedTo[user_], EnumerableSet.values($.delegators[user_]));
    }

    /// @inheritdoc IDAO
    function getOtherChainsPowers()
        external
        view
        returns (uint timestamp, address[] memory users, uint[] memory powers)
    {
        DaoStorage storage $ = _getDaoStorage();
        uint epoch = $.otherChainsEpoch;
        OtherChainsPowers storage poc = $.otherChainsPowers[$.otherChainsEpoch];

        uint len = poc.powers.length();

        users = new address[](len);
        powers = new uint[](len);
        for (uint i; i < len; ++i) {
            (address user, uint power) = poc.powers.at(i);
            users[i] = user;
            powers[i] = power;
        }

        timestamp = epoch;
    }

    /// @inheritdoc IDAO
    function isWhitelistedForOtherChainsPowers(address user_) external view returns (bool) {
        return _getDaoStorage().otherChainsPowersWhitelist[user_];
    }

    /// @inheritdoc IDAO
    function delegationForbidden() external view returns (bool) {
        return _getDaoStorage().delegationForbidden;
    }

    //endregion ----------------------------------- View functions

    //region ----------------------------------- Voting power calculation

    /// @notice Get powers of the given user.
    /// @param user_ The address of the user.
    /// @return localPower Power on the current chain. This power can be delegated to other user (delegates.delegatedTo}.
    /// @return otherPower Power on other chains. This power can be delegated to other user (delegates.delegatedTo}.
    function _getPowers(DaoStorage storage $, address user_) internal view returns (uint localPower, uint otherPower) {
        EnumerableMap.AddressToUintMap storage _otherPowers = $.otherChainsPowers[$.otherChainsEpoch].powers;

        localPower = balanceOf(user_);
        otherPower = _otherPowers.contains(user_) ? _otherPowers.get(user_) : 0;

        return (localPower, otherPower);
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
            $.slot := _DAO_TOKEN_STORAGE_LOCATION
        }
    }
    //endregion ----------------------------------- Internal logic
}
