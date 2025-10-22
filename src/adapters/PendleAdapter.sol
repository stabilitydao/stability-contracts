// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Controllable, IControllable, IERC165} from "../core/base/Controllable.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {AmmAdapterIdLib} from "./libs/AmmAdapterIdLib.sol";
import {IPMarket, IStandardizedYield} from "../integrations/pendle/IPMarket.sol";
import {IPPYLpOracle} from "../integrations/pendle/IPPYLpOracle.sol";
import {IPPrincipalToken} from "../integrations/pendle/IPPrincipalToken.sol";
import {IPYieldToken} from "../integrations/pendle/IPYieldToken.sol";
import {IPActionMiscV3} from "../integrations/pendle/IPActionMiscV3.sol";
import {IPActionSwapPTV3, TokenOutput, TokenInput, ApproxParams} from "../integrations/pendle/IPActionSwapPTV3.sol";
import {createEmptyLimitOrderData} from "../integrations/pendle/IPAllActionTypeV3.sol";
import {SwapData} from "../integrations/pendle/IPSwapAggregator.sol";
import {ConstantsLib} from "../core/libs/ConstantsLib.sol";

/// @title AMM adapter for Pendle
/// Changelog:
///     1.1.1: add empty IAmmAdapter.getTwaPrice
///     1.1.0: swap is able to redeem from expired PT-markets - #352
/// @author Alien Deployer (https://github.com/a17)
/// @author dvpublic (https://github.com/dvpublic)
contract PendleAdapter is Controllable, IAmmAdapter {
    using SafeERC20 for IERC20;

    /// @dev Pendle oracle address for all chains
    address public constant ORACLE = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;
    address public constant ROUTER = 0x888888888889758F76e7103c6CbF23ABbF58F946;
    address public constant ACTION_MISC_V3 = 0x373Dba2055Ad40cb4815148bC47cd1DC16e92E44;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.1.1";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error IncorrectTokens();

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
    ) external {
        address[] memory tokens = poolTokens(pool);
        SwapData memory emptySwapData;

        uint amount = IERC20(tokenIn).balanceOf(address(this));
        uint amountOut;
        uint amountOutWithoutImpact = getPrice(pool, tokenIn, tokenOut, amount);

        IERC20(tokenIn).forceApprove(ROUTER, amount);

        // pt to yield token
        // pt to asset
        if ((tokenIn == tokens[1] && tokenOut == tokens[3]) || (tokenIn == tokens[1] && tokenOut == tokens[4])) {
            if (IPPrincipalToken(tokenIn).isExpired()) {
                IERC20(tokenIn).forceApprove(ACTION_MISC_V3, amount);
                (amountOut,) = IPActionMiscV3(ACTION_MISC_V3)
                    .redeemPyToToken(
                        recipient,
                        IPPrincipalToken(tokenIn).YT(),
                        amount,
                        TokenOutput({
                            tokenOut: tokenOut,
                            minTokenOut: 0,
                            tokenRedeemSy: tokenOut,
                            pendleSwap: address(0),
                            swapData: emptySwapData
                        })
                    );
            } else {
                (amountOut,,) = IPActionSwapPTV3(ROUTER)
                    .swapExactPtForToken(
                        recipient,
                        pool,
                        amount,
                        TokenOutput({
                            tokenOut: tokenOut,
                            minTokenOut: 0,
                            tokenRedeemSy: tokenOut,
                            pendleSwap: address(0),
                            swapData: emptySwapData
                        }),
                        createEmptyLimitOrderData()
                    );
            }
        }

        // yield token to pt
        // asset to PT
        if ((tokenIn == tokens[3] && tokenOut == tokens[1]) || (tokenIn == tokens[4] && tokenOut == tokens[1])) {
            // DefaultApprox means no off-chain preparation is involved, more gas consuming (~ 180k gas)
            ApproxParams memory defaultApprox =
                ApproxParams({guessMin: 0, guessMax: type(uint).max, guessOffchain: 0, maxIteration: 256, eps: 1e14});
            TokenInput memory input = TokenInput({
                tokenIn: tokenIn,
                netTokenIn: amount,
                tokenMintSy: tokenIn,
                pendleSwap: address(0),
                swapData: emptySwapData
            });
            (amountOut,,) = IPActionSwapPTV3(ROUTER)
                .swapExactTokenForPt(recipient, pool, 0, defaultApprox, input, createEmptyLimitOrderData());
        }

        if (amountOut < amountOutWithoutImpact) {
            uint amountImpact = (amountOutWithoutImpact - amountOut) * ConstantsLib.DENOMINATOR / amountOutWithoutImpact;
            if (amountImpact >= priceImpactTolerance) {
                revert(string(abi.encodePacked("!PRICE ", Strings.toString(amountImpact))));
            }
        }

        emit SwapInPool(pool, tokenIn, tokenOut, recipient, priceImpactTolerance, amount, amountOut);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAmmAdapter
    function ammAdapterId() external pure returns (string memory) {
        return AmmAdapterIdLib.PENDLE;
    }

    /// @inheritdoc IAmmAdapter
    function poolTokens(address pool) public view returns (address[] memory tokens) {
        tokens = new address[](5);
        (IStandardizedYield _SY, IPPrincipalToken _PT, IPYieldToken _YT) = IPMarket(pool).readTokens();
        tokens[0] = address(_SY);
        tokens[1] = address(_PT);
        tokens[2] = address(_YT);
        tokens[3] = _SY.yieldToken();
        (, tokens[4],) = _SY.assetInfo();
    }

    /// @inheritdoc IAmmAdapter
    function getLiquidityForAmounts(address, uint[] memory) external pure returns (uint, uint[] memory) {
        revert("Not supported");
    }

    /// @inheritdoc IAmmAdapter
    function getProportions(address) external pure returns (uint[] memory) {
        revert("Not supported");
    }

    /// @inheritdoc IAmmAdapter
    function getPrice(address pool, address tokenIn, address tokenOut, uint amount) public view returns (uint) {
        address[] memory tokens = poolTokens(pool);
        // PT to Yield token (aUSDC, weETH, etc)
        if (tokenIn == tokens[1] && tokenOut == tokens[3]) {
            uint price = IPPYLpOracle(ORACLE).getPtToSyRate(pool, 9000);
            // this is incorrect data for rebase yield token like aUSDC, but for wrapped is ok
            // rebase need use exchangeRate too
            // uint syExchangeRate = IStandardizedYield(tokens[0]).exchangeRate();
            return amount * price / 1e18;
        }
        // Yield token (aUSDC, weETH, etc) to PT
        if (tokenIn == tokens[3] && tokenOut == tokens[1]) {
            uint price = IPPYLpOracle(ORACLE).getPtToSyRate(pool, 9000);
            return amount * 1e18 / price;
        }
        // PT to asset
        if (tokenIn == tokens[1] && tokenOut == tokens[4]) {
            uint price = IPPYLpOracle(ORACLE).getPtToAssetRate(pool, 9000);
            return amount * price / 1e18;
        }
        // asset to PT
        if (tokenIn == tokens[4] && tokenOut == tokens[1]) {
            uint price = IPPYLpOracle(ORACLE).getPtToAssetRate(pool, 9000);
            return amount * 1e18 / price;
        }

        revert IncorrectTokens();
    }

    /// @inheritdoc IAmmAdapter
    function getTwaPrice(address /*pool*/, address /*tokenIn*/, address /*tokenOut*/, uint /*amount*/, uint32 /*period*/) external pure returns (uint) {
        revert("Not supported");
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(Controllable, IERC165) returns (bool) {
        return interfaceId == type(IAmmAdapter).interfaceId || super.supportsInterface(interfaceId);
    }
}
