// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StrategyBase, IERC165, SafeERC20, IERC20} from "./StrategyBase.sol";
import {IMerklStrategy} from "../../interfaces/IMerklStrategy.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IMerklDistributor} from "../../integrations/merkl/IMerklDistributor.sol";

/// @title Base for Merkl strategies
/// Changelog:
///   1.1.0: add claimToMultisig
/// @author Alien Deployer (https://github.com/a17)
abstract contract MerklStrategyBase is StrategyBase, IMerklStrategy {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Version of StrategyBase implementation
    string public constant VERSION_MERKL_STRATEGY_BASE = "1.1.0";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMerklStrategy
    function toggleDistributorUserOperator(address distributor, address operator) external onlyOperator {
        IMerklDistributor(distributor).toggleOperator(address(this), operator);
    }

    /// @inheritdoc IMerklStrategy
    function claimToMultisig(
        address distributor,
        address[] calldata tokens,
        uint[] calldata amounts,
        bytes32[][] calldata proofs
    ) external onlyOperator {
        address multisig = IPlatform(platform()).multisig();
        uint len = tokens.length;
        address[] memory users = new address[](len);
        uint[] memory balanceBefore = new uint[](len);
        for (uint i; i < len; ++i) {
            //slither-disable-next-line calls-loop
            balanceBefore[i] = IERC20(tokens[i]).balanceOf(address(this));
            users[i] = address(this);
        }
        IMerklDistributor(distributor).claim(users, tokens, amounts, proofs);
        for (uint i; i < len; ++i) {
            //slither-disable-next-line calls-loop
            uint got = IERC20(tokens[i]).balanceOf(address(this)) - balanceBefore[i];
            IERC20(tokens[i]).safeTransfer(multisig, got);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IMerklStrategy).interfaceId || super.supportsInterface(interfaceId);
    }
}
