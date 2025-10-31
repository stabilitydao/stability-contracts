// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Controllable, IControllable} from "./base/Controllable.sol";
import {Proxy, IProxy} from "./proxy/Proxy.sol";
import {IProxyFactory} from "../interfaces/IProxyFactory.sol";

/// @notice Create2 proxy deployer
/// @author Alien Deployer (https://github.com/a17)
contract ProxyFactory is Controllable, IProxyFactory {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IProxyFactory
    function initialize(address platform_) public initializer {
        __Controllable_init(platform_);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IProxyFactory
    function deployProxy(bytes32 salt, address implementation) external onlyOperator returns (address proxy) {
        proxy = address(new Proxy{salt: salt}());
        IProxy(proxy).initProxy(implementation);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IProxyFactory
    function getProxyInitCodeHash() public pure returns (bytes32) {
        return keccak256(abi.encodePacked(type(Proxy).creationCode));
    }

    /// @inheritdoc IProxyFactory
    function getCreate2Address(bytes32 salt) external view returns (address) {
        return
            address(
                uint160(uint(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, getProxyInitCodeHash()))))
            );
    }
}
