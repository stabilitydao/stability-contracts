// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../core/libs/ConstantsLib.sol";
import "../core/base/Controllable.sol";
import "../adapters/libs/AmmAdapterIdLib.sol";
import "../interfaces/IAmmAdapter.sol";

/// @title AMM adapter for GyroECLP pools
/// @author Jude (https://github.com/iammrjude)
contract GyroscopeAdapter is Controllable, IAmmAdapter {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function init(address platform_) external initializer {
        __Controllable_init(platform_);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    //slither-disable-next-line reentrancy-events
    function swap(
        address pool,
        address tokenIn,
        address tokenOut,
        address recipient,
        uint priceImpactTolerance
    ) external {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function ammAdapterId() external pure returns (string memory) {
        return AmmAdapterIdLib.GYROSCOPE;
    }

    /// @inheritdoc IAmmAdapter
    function poolTokens(address pool) public view returns (address[] memory tokens) {}

    /// @inheritdoc IAmmAdapter
    function getLiquidityForAmounts(
        address pool,
        uint[] memory amounts
    ) external view returns (uint liquidity, uint[] memory amountsConsumed) {}

    /// @inheritdoc IAmmAdapter
    function getProportions(address pool) external view returns (uint[] memory props) {}

    /// @inheritdoc IAmmAdapter
    function getPrice(address pool, address tokenIn, address tokenOut, uint amount) public view returns (uint) {}

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(Controllable, IERC165) returns (bool) {
        return interfaceId == type(IAmmAdapter).interfaceId || super.supportsInterface(interfaceId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getTokensIndexes(
        address pool,
        address tokenIn,
        address tokenOut
    ) internal view returns (int128 tokenInIndex, int128 tokenOutIndex) {
        address[] memory tokens = poolTokens(pool);
        uint len = tokens.length;
        for (uint i; i < len; ++i) {
            if (tokenIn == tokens[i]) {
                tokenInIndex = int128(uint128(i));
            }
            if (tokenOut == tokens[i]) {
                tokenOutIndex = int128(uint128(i));
            }
        }
    }

    /// @notice Make infinite approve of {token} to {spender} if the approved amount is less than {amount}
    /// @dev Should NOT be used for third-party pools
    function _approveIfNeeded(address token, uint amount, address spender) internal {
        if (IERC20(token).allowance(address(this), spender) < amount) {
            // infinite approve, 2*255 is more gas efficient then type(uint).max
            IERC20(token).forceApprove(spender, 2 ** 255);
        }
    }
}
