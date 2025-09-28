// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Controllable, IControllable} from "../core/base/Controllable.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {IBalancerAdapter} from "../interfaces/IBalancerAdapter.sol";
import {IPoolInfo} from "../integrations/balancerv3/IPoolInfo.sol";
import {IRouter} from "../integrations/balancerv3/IRouter.sol";
import {AmmAdapterIdLib} from "./libs/AmmAdapterIdLib.sol";

/// @title AMM adapter for Balancer V3 ReCLAMM pools
/// @author Alien Deployer (https://github.com/a17)
contract BalancerV3ReClammAdapter is Controllable, IAmmAdapter, IBalancerAdapter {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.BalancerV3ReClammAdapter")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant STORAGE_LOCATION = 0x1e1f631b42f2fb77972646b67315696ad5ca38a298a2645a48cc79e667edc000;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.BalancerV3ReClammAdapter
    struct AdapterStorage {
        address router;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function init(address platform_) external initializer {
        __Controllable_init(platform_);
    }

    /// @inheritdoc IBalancerAdapter
    function setupHelpers(address router) external {
        AdapterStorage storage $ = _getStorage();
        if ($.router != address(0)) {
            revert AlreadyExist();
        }
        $.router = router;
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
    ) external {
        uint amountIn = IERC20(tokenIn).balanceOf(address(this));

        AdapterStorage storage $ = _getStorage();
        address router = $.router;

        // todo
        // see BalancerV3StableAdapter
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function ammAdapterId() external pure returns (string memory) {
        return AmmAdapterIdLib.BALANCER_V3_RECLAMM;
    }

    /// @inheritdoc IAmmAdapter
    function poolTokens(address pool) public view returns (address[] memory tokens) {
        return IPoolInfo(pool).getTokens();
    }

    /// @inheritdoc IAmmAdapter
    function getLiquidityForAmounts(address, uint[] memory) external pure returns (uint, uint[] memory) {
        revert("Unavailable");
    }

    /// @inheritdoc IBalancerAdapter
    function getLiquidityForAmountsWrite(
        address pool,
        uint[] memory amounts
    ) external returns (uint liquidity, uint[] memory amountsConsumed) {
        revert("Unavailable");
    }

    /// @inheritdoc IAmmAdapter
    function getProportions(address pool) external view returns (uint[] memory props) {
        // todo
        // see BalancerV3StableAdapter
    }

    /// @inheritdoc IAmmAdapter
    function getPrice(address pool, address tokenIn, address tokenOut, uint amount) public view returns (uint) {
        // todo
        // see BalancerV3StableAdapter
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(Controllable, IERC165) returns (bool) {
        return interfaceId == type(IAmmAdapter).interfaceId || interfaceId == type(IBalancerAdapter).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getTokenInOutIndexes(
        address[] memory tokens,
        address tokenIn,
        address tokenOut
    ) internal pure returns (uint tokenInIndex, uint tokenOutIndex) {
        uint len = tokens.length;
        for (uint i; i < len; ++i) {
            if (tokens[i] == tokenIn) {
                tokenInIndex = i;
                break;
            }
        }
        for (uint i; i < len; ++i) {
            if (tokens[i] == tokenOut) {
                tokenOutIndex = i;
                break;
            }
        }
    }

    function _getStorage() private pure returns (AdapterStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }
}
