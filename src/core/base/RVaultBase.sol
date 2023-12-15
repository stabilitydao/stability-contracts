// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./VaultBase.sol";
import "../libs/RVaultLib.sol";
import "../libs/VaultTypeLib.sol";
import "../libs/CommonLib.sol";
import "../../interfaces/IRVault.sol";
import "../../interfaces/IPlatform.sol";

/// @notice Base rewarding vault.
///         It has a buy-back reward token and boost reward tokens.
///         Rewards are distributed smoothly by vesting with variable periods.
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
/// @author 0xhokugava (https://github.com/0xhokugava)
abstract contract RVaultBase is VaultBase, IRVault {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Version of RVaultBase implementation
    string public constant VERSION_RVAULT_BASE = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.RVaultBase")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant RVAULTBASE_STORAGE_LOCATION =
        0xb5732c585a6784b4587829603e9853db681fd231004dc454c3ae683d1ebdca00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    //slither-disable-next-line naming-convention
    function __RVaultBase_init(
        address platform_,
        string memory type_,
        address strategy_,
        string memory name_,
        string memory symbol_,
        uint tokenId_,
        address[] memory vaultInitAddresses,
        uint[] memory vaultInitNums
    ) internal onlyInitializing {
        __VaultBase_init(platform_, type_, strategy_, name_, symbol_, tokenId_);
        RVaultBaseStorage storage $ = _getRVaultBaseStorage();
        RVaultLib.__RVaultBase_init($, platform_, vaultInitAddresses, vaultInitNums);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev All rewards for given owner could be claimed for receiver address.
    function setRewardsRedirect(address owner, address receiver) external onlyMultisig {
        RVaultBaseStorage storage $ = _getRVaultBaseStorage();
        $.rewardsRedirect[owner] = receiver;
        emit SetRewardsRedirect(owner, receiver);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRVault
    function getAllRewards() external {
        _getAllRewards(msg.sender, msg.sender);
    }

    /// @notice Update and Claim all rewards for given owner address. Send them to predefined receiver.
    function getAllRewardsAndRedirect(address owner) external {
        RVaultBaseStorage storage $ = _getRVaultBaseStorage();
        address receiver = $.rewardsRedirect[owner];
        if (receiver == address(0)) {
            revert IControllable.IncorrectZeroArgument();
        }
        _getAllRewards(owner, receiver);
    }

    /// @notice Update and Claim all rewards for the given owner.
    ///         Sender should have allowance for push rewards for the owner.
    function getAllRewardsFor(address owner) external {
        if (owner != msg.sender) {
            // To avoid calls from any address, and possibility to cancel boosts for other addresses
            // we check approval of shares for msg.sender. Msg sender should have approval for max amount
            // As approved amount is deducted every transfer, we checks it with max / 10
            uint allowance = allowance(owner, msg.sender);
            if (allowance <= (type(uint).max / 10)) {
                revert NotAllowed();
            }
        }
        _getAllRewards(owner, owner);
    }

    /// @notice Update and Claim rewards for specific token
    function getReward(uint rt) external {
        RVaultBaseStorage storage $ = _getRVaultBaseStorage();
        RVaultLib.updateReward($, msg.sender, rt);
        RVaultLib.payRewardTo($, rt, msg.sender, msg.sender);
    }

    /// @inheritdoc IRVault
    // slither-disable-next-line reentrancy-no-eth
    // slither-disable-next-line reentrancy-events
    function notifyTargetRewardAmount(uint i, uint amount) external {
        RVaultBaseStorage storage $ = _getRVaultBaseStorage();
        VaultBaseStorage storage _$ = _getVaultBaseStorage();
        RVaultLib.notifyTargetRewardAmount($, _$, i, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, VaultBase) returns (bool) {
        return interfaceId == type(IRVault).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IRVault
    function bbToken() public view returns (address) {
        return _getRVaultBaseStorage().rewardToken[0];
    }

    function rewardTokens() external view returns (address[] memory) {
        RVaultBaseStorage storage $ = _getRVaultBaseStorage();
        return RVaultLib.rewardTokens($);
    }

    /// @notice Return reward per token ratio by reward token address
    ///                rewardPerTokenStoredForToken + (
    ///                (lastTimeRewardApplicable - lastUpdateTimeForToken)
    ///                 * rewardRateForToken * 10**18 / totalSupply)
    function rewardPerToken(uint rewardTokenIndex) external view returns (uint) {
        return _rewardPerToken(rewardTokenIndex);
    }

    /// @inheritdoc IRVault
    function earned(uint rewardTokenIndex, address account) external view returns (uint) {
        RVaultBaseStorage storage $ = _getRVaultBaseStorage();
        return RVaultLib.earned($, rewardTokenIndex, account);
        // return _earned(rewardTokenIndex, account);
    }

    /// @inheritdoc IRVault
    function rewardToken(uint tokenIndex) public view returns (address) {
        RVaultBaseStorage storage $ = _getRVaultBaseStorage();
        return $.rewardToken[tokenIndex];
    }

    /// @inheritdoc IRVault
    function duration(uint tokenIndex) public view returns (uint) {
        RVaultBaseStorage storage $ = _getRVaultBaseStorage();
        return $.duration[tokenIndex];
    }

    /// @inheritdoc IRVault
    function rewardsRedirect(address owner) public view returns (address) {
        RVaultBaseStorage storage $ = _getRVaultBaseStorage();
        return $.rewardsRedirect[owner];
    }

    /// @inheritdoc IRVault
    function compoundRatio() public view returns (uint) {
        RVaultBaseStorage storage $ = _getRVaultBaseStorage();
        return $.compoundRatio;
    }

    /// @inheritdoc IRVault
    function rewardTokensTotal() public view returns (uint) {
        RVaultBaseStorage storage $ = _getRVaultBaseStorage();
        return $.rewardTokensTotal;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getRVaultBaseStorage() internal pure returns (RVaultBaseStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := RVAULTBASE_STORAGE_LOCATION
        }
    }

    function _getAllRewards(address owner, address receiver) internal {
        RVaultBaseStorage storage $ = _getRVaultBaseStorage();
        RVaultLib.getAllRewards($, owner, receiver);
    }

    function _rewardPerToken(uint rewardTokenIndex) internal view returns (uint) {
        RVaultBaseStorage storage $ = _getRVaultBaseStorage();
        return RVaultLib.rewardPerToken($, rewardTokenIndex);
    }

    function _update(address from, address to, uint value) internal override {
        super._update(from, to, value);
        RVaultBaseStorage storage $ = _getRVaultBaseStorage();
        RVaultLib.updateRewards($, from);
        RVaultLib.updateRewards($, to);
    }
}
