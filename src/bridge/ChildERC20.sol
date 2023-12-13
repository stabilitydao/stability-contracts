// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IChildERC20.sol";

/// @notice ChildERC20
/// @author Jude (https://github.com/iammrjude)
contract ChildERC20 is ERC20, IChildERC20 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.ChildERC20")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant CHILDERC20_STORAGE_LOCATION =
        0xb506eeb1b3f54d9da380c49fc8733ef6a2bcc9d32137471ed8d9a6613e6fb900;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         STORAGE                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.ChildERC20
    struct ChildERC20Storage {
        address parentToken;
        uint16 parentChainId;
        address bridge;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(
        address parentToken,
        uint16 parentChainId,
        string memory name,
        string memory symbol,
        address bridge_
    ) payable ERC20(name, symbol) {
        ChildERC20Storage storage $ = _getStorage();
        $.parentToken = parentToken;
        $.parentChainId = parentChainId;
        $.bridge = bridge_;
    }

    modifier onlyBridge() {
        _requireBridge();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function mint(address to, uint amount) external onlyBridge {
        _mint(to, amount);
    }

    function burn(address from, uint amount) external onlyBridge {
        _burn(from, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function bridge() external view returns (address) {
        return _getStorage().bridge;
    }

    function parent() external pure returns (address token, uint16 chainId) {
        ChildERC20Storage memory $ = _getStorage();
        return ($.parentToken, $.parentChainId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getStorage() private pure returns (ChildERC20Storage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := CHILDERC20_STORAGE_LOCATION
        }
    }

    function _requireBridge() internal view {
        if (this.bridge() != msg.sender) {
            revert NotBridge();
        }
    }
}
