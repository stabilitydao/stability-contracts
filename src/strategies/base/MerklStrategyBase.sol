// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./StrategyBase.sol";
import "../../interfaces/IMerklStrategy.sol";
import "../../integrations/merkl/IMerklDistributor.sol";

/// @title Base for Merkl strategies
/// @author Alien Deployer (https://github.com/a17)
abstract contract MerklStrategyBase is StrategyBase, IMerklStrategy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Version of StrategyBase implementation
    string public constant VERSION_MERKL_STRATEGY_BASE = "1.0.0";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function toggleDistributorUserOperator(address distributor, address operator) external onlyOperator {
        IMerklDistributor(distributor).toggleOperator(address(this), operator);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IMerklStrategy).interfaceId || super.supportsInterface(interfaceId);
    }
}
