// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {OFTUpgradeable} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";
import {IControllable, Controllable} from "../core/base/Controllable.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IBridgedToken} from "../interfaces/IBridgedToken.sol";
import {IOFTPausable} from "../interfaces/IOFTPausable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

/// @notice Omnichain Fungible Token - bridged version of main-token from Sonic to other chains
/// Changelog:
///  - 1.0.2: Add buildOptions function
///  - 1.0.1: Add setName and setSymbol functions
contract BridgedToken is Controllable, OFTUpgradeable, IBridgedToken {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.2";

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.BridgedToken")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant BRIDGED_TOKEN_STORAGE_LOCATION =
        0x5908ba930cd8810ead4eba737803862bca8ae4a4891cfeedea00ad638eaee100;

    /// @custom:storage-location erc7201:stability.BridgedToken
    struct BridgedTokenStorage {
        /// @notice Paused state for addresses
        mapping(address => bool) paused;
        /// @dev Changed ERC20 name
        string changedName;
        /// @dev Changed ERC20 symbol
        string changedSymbol;
    }

    //region --------------------------------- Initializers
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(address lzEndpoint_) OFTUpgradeable(lzEndpoint_) {
        _disableInitializers();
    }

    /// @inheritdoc IBridgedToken
    function initialize(
        address platform_,
        string memory name_,
        string memory symbol_,
        address delegate_
    ) public initializer {
        address _owner = IPlatform(platform_).multisig();

        __Controllable_init(platform_);
        __OFT_init(name_, symbol_, delegate_);
        __Ownable_init(_owner);
    }

    //endregion --------------------------------- Initializers

    //region --------------------------------- Restricted actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  RESTRICTED ACTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IOFTPausable
    function setPaused(address account, bool paused_) external onlyOperator {
        BridgedTokenStorage storage $ = getBridgedTokenStorage();
        $.paused[account] = paused_;

        emit Pause(account, paused_);
    }

    /// @inheritdoc IBridgedToken
    function setName(string calldata newName) external onlyOperator {
        BridgedTokenStorage storage $ = getBridgedTokenStorage();
        $.changedName = newName;
        emit BridgedTokenName(newName);
    }

    /// @inheritdoc IBridgedToken
    function setSymbol(string calldata newSymbol) external onlyOperator {
        BridgedTokenStorage storage $ = getBridgedTokenStorage();
        $.changedSymbol = newSymbol;
        emit BridgedTokenSymbol(newSymbol);
    }

    //endregion --------------------------------- Restricted actions

    //region --------------------------------- View

    /// @inheritdoc IOFTPausable
    function paused(address account_) external view returns (bool) {
        return getBridgedTokenStorage().paused[account_];
    }

    /// @inheritdoc ERC20Upgradeable
    function name() public view override returns (string memory) {
        BridgedTokenStorage storage $ = getBridgedTokenStorage();
        string memory changedName = $.changedName;
        if (bytes(changedName).length != 0) {
            return changedName;
        }
        return super.name();
    }

    /// @inheritdoc ERC20Upgradeable
    function symbol() public view override returns (string memory) {
        BridgedTokenStorage storage $ = getBridgedTokenStorage();
        string memory changedSymbol = $.changedSymbol;
        if (bytes(changedSymbol).length != 0) {
            return changedSymbol;
        }
        return super.symbol();
    }

    /// @inheritdoc IOFTPausable
    function buildOptions(uint128 gas_, uint128 value_) external pure returns (bytes memory) {
        return OptionsBuilder.addExecutorLzReceiveOption(OptionsBuilder.newOptions(), gas_, value_);
    }

    //endregion --------------------------------- View

    //region --------------------------------- Overrides
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  OVERRIDES                                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function _checkOwner() internal view override {
        _requireMultisig();
    }

    /// @dev Paused accounts cannot send tokens
    function _update(address from, address to, uint value) internal virtual override {
        _requireNotPaused(from);

        super._update(from, to, value);
    }

    /// @dev Paused accounts cannot send tokens
    function _debit(
        address from_,
        uint amountLD_,
        uint minAmountLD_,
        uint32 dstEid_
    ) internal virtual override returns (uint amountSentLD, uint amountReceivedLD) {
        _requireNotPaused(from_);

        return super._debit(from_, amountLD_, minAmountLD_, dstEid_);
    }

    /// @dev Paused accounts cannot receive tokens
    function _credit(
        address to_,
        uint amountLD_,
        uint32 srcEid_
    ) internal virtual override returns (uint amountReceivedLD) {
        _requireNotPaused(to_);

        return super._credit(to_, amountLD_, srcEid_);
    }

    //endregion --------------------------------- Overrides

    //region --------------------------------- Internal logic
    function getBridgedTokenStorage() internal pure returns (BridgedTokenStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := BRIDGED_TOKEN_STORAGE_LOCATION
        }
    }

    /// @notice Reverts if the account is paused OR the whole bridge is paused
    function _requireNotPaused(address account) internal view {
        BridgedTokenStorage storage $ = getBridgedTokenStorage();
        require(!$.paused[account] && !$.paused[address(this)], Paused());
    }

    //endregion --------------------------------- Internal logic
}
