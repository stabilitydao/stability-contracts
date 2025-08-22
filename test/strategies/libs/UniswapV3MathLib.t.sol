// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console, Test} from "forge-std/Test.sol";
import {UniswapV3MathLib} from "../../../src/strategies/libs/UniswapV3MathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SonicConstantsLib} from "../../../chains/sonic/SonicConstantsLib.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @dev Basic uniswap v3 math:
/// sqrtPriceX96 = sP * 2^96
/// price of token 1 in token 0 = sqrtPriceX96^2 / 2^192 * 10^(decimals1 - decimals0)
/// price of token 0 in token 1 = 2^192 / sqrtPriceX96^2 * 10^(decimals0 - decimals1)
contract UniswapV3MathLibTests is Test {
    uint public constant FORK_BLOCK = 44050980; // Aug-22-2025 05:33:27 AM +UTC
    uint public constant COUNT_KNOWN_PRICES = 9;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
    }

    /// @dev Calculate prices for two tokens with decimals 6
    function testCalcPriceOutD6D6() external view {
        uint price;

        //----------------------- Token 0 is token IN
        price = UniswapV3MathLib.calcPriceOut(
            SonicConstantsLib.TOKEN_bUSDCe20,
            SonicConstantsLib.TOKEN_bUSDCe20, // TOKEN_wstkscUSD,
            2542995591783599406928485407,
            6,
            6,
            0
        );
        assertEq(price, 1030, "Expected price of bUSDCe20 in wstkscUSD");

        price = UniswapV3MathLib.calcPriceOut(
            SonicConstantsLib.TOKEN_bUSDCe20,
            SonicConstantsLib.TOKEN_bUSDCe20, // TOKEN_wstkscUSD,
            2542995591783599406928485407,
            6,
            6,
            2e6
        );
        assertEq(price, 2*1030, "Expected amount of wstkscUSD for 2 bUSDCe20");

        //----------------------- Token 0 is token OUT
        price = UniswapV3MathLib.calcPriceOut(
            SonicConstantsLib.TOKEN_wstkscUSD,
            SonicConstantsLib.TOKEN_bUSDCe20, // TOKEN_wstkscUSD,
            2542995591783599406928485407,
            6,
            6,
            0
        );
        assertApproxEqAbs(price, 970661832, 20, "Expected price of wstkscUSD in bUSDCe20");

        price = UniswapV3MathLib.calcPriceOut(
            SonicConstantsLib.TOKEN_wstkscUSD,
            SonicConstantsLib.TOKEN_bUSDCe20, // TOKEN_wstkscUSD,
            2542995591783599406928485407,
            6,
            6,
            3e6
        );
        assertApproxEqAbs(price, 3*970661832, 100, "Expected amount of bUSDCe20 for 3 wstkscUSD");
    }

    function testCalcPriceOutD18D6() external view {
        uint price;

        //----------------------- Token 0 is token IN
        price = UniswapV3MathLib.calcPriceOut(
            SonicConstantsLib.TOKEN_wS,
            SonicConstantsLib.TOKEN_wS,
            45035495122636274992972,
            18,
            6,
            0
        );
        assertEq(price, 323110, "Expected price of wS in USDC");

        price = UniswapV3MathLib.calcPriceOut(
            SonicConstantsLib.TOKEN_wS,
            SonicConstantsLib.TOKEN_wS,
            45035495122636274992972,
            18,
            6,
            1e18
        );
        assertEq(price, 323110, "Expected amount of wS for 1 USDC");

        //----------------------- Token 0 is token OUT
        price = UniswapV3MathLib.calcPriceOut(
            SonicConstantsLib.TOKEN_USDC,
            SonicConstantsLib.TOKEN_wS,
            45035495122636274992972,
            6,
            18,
            0
        );
        assertApproxEqAbs(price, 3094918977041563606, 20, "Expected price of USDC in wS");

        price = UniswapV3MathLib.calcPriceOut(
            SonicConstantsLib.TOKEN_USDC,
            SonicConstantsLib.TOKEN_wS,
            45035495122636274992972,
            6,
            18,
            1e6
        );
        assertApproxEqAbs(price, 3094918977041563606, 100, "Expected amount of USDC for 1 wS");
    }

    function testPrice() external view {
        uint[3] memory prices10 = [uint(1e18), uint(112771e18), uint(0.000231e18)];
        uint8[3] memory decimals = [6, 8, 18];
        for (uint p = 0; p < prices10.length; ++p) {
            console.log("!!!!!!!!!!!!!!!! price", prices10[p]);
            for (uint i = 0; i < decimals.length; ++i) {
                for (uint j = 0; j < decimals.length; ++j) {
                    uint d0 = decimals[i];
                    uint d1 = decimals[j];

                    uint price = prices10[p] * 10**d1 / 1e18;
                    uint sqrtPriceX96 = Math.sqrt(price * (2**192 / 10**d0));

                    uint priceOutDirect = UniswapV3MathLib.calcPriceOut(
                        SonicConstantsLib.TOKEN_USDC, // any address
                        SonicConstantsLib.TOKEN_USDC, // same address
                        uint160(sqrtPriceX96),
                        d0,
                        d1,
                        0
                    );
//                    uint priceOutOld = UniswapV3MathLib.calcPriceOut2(
//                        SonicConstantsLib.TOKEN_USDC, // any address
//                        SonicConstantsLib.TOKEN_USDC, // same address
//                        uint160(sqrtPriceX96),
//                        d0,
//                        d1,
//                        0
//                    );

                    console.log("D0, D1, 10*p_expected/p_calculated", d0, d1, price*1e18/priceOutDirect);
                    // console.log("price exact, price calculated", price, priceOut, sqrtPriceX96);
                    assertApproxEqAbs(price, priceOutDirect, price/1e5, "Prices should be equal");
                }
            }
        }
    }

    function testPriceReverse() external view {
        uint[3] memory prices10 = [uint(1e18), uint(112771e18), uint(0.000231e18)];
        uint8[3] memory decimals = [6, 8, 18];
        for (uint p = 0; p < prices10.length; ++p) {
            console.log("!!!!!!!!!!!!!!!! price", prices10[p]);
            for (uint i = 0; i < decimals.length; ++i) {
                for (uint j = 0; j < decimals.length; ++j) {
                    uint d0 = decimals[i];
                    uint d1 = decimals[j];

                    uint price = prices10[p] * 10**d1 / 1e18;
                    uint sqrtPriceX96 = Math.sqrt(price * (2**192 / 10**d0));

                    uint priceOut = UniswapV3MathLib.calcPriceOut(
                        SonicConstantsLib.TOKEN_wETH, // token In is token 1
                        SonicConstantsLib.TOKEN_USDC, // token 0 != token In
                        uint160(sqrtPriceX96),
                        d1,
                        d0,
                        0
                    );

                    uint priceExpected = 10**d0 * 10**d1 / price;

                    console.log("D0, D1, 10*p_expected/p_calculated", d0, d1, priceExpected*1e18/priceOut);
                    console.log("price exact, price calculated", priceExpected, priceOut, sqrtPriceX96);
                    assertApproxEqAbs(priceExpected, priceOut, priceExpected/1e5, "Prices should be equal");
                }
            }
        }
    }

    function testKnownPrices() external view{
        address[COUNT_KNOWN_PRICES] memory tokens0 = [
            SonicConstantsLib.TOKEN_USDC,
            SonicConstantsLib.TOKEN_wS,
            SonicConstantsLib.TOKEN_wS,
            SonicConstantsLib.TOKEN_USDC,
            SonicConstantsLib.TOKEN_bUSDCe20,
            SonicConstantsLib.TOKEN_aUSDC,
            SonicConstantsLib.TOKEN_USDC,
            SonicConstantsLib.TOKEN_wBTC,
            SonicConstantsLib.TOKEN_wBTC
        ];

        address[COUNT_KNOWN_PRICES] memory tokens1 = [
            SonicConstantsLib.TOKEN_USDT,
            SonicConstantsLib.TOKEN_USDC,
            SonicConstantsLib.TOKEN_wETH,
            SonicConstantsLib.TOKEN_wETH,
            SonicConstantsLib.TOKEN_wstkscUSD,
            SonicConstantsLib.TOKEN_wstkscUSD,
            SonicConstantsLib.TOKEN_stS,
            SonicConstantsLib.TOKEN_wETH,
            SonicConstantsLib.TOKEN_USDC
        ];

        uint[COUNT_KNOWN_PRICES] memory sqrtPricesX96 = [
            uint(79224056452590773318864518869),
            uint(45134697201291563237796),
            uint(685956846654828609052839519),
            uint(1204279775304377464103418761510253),
            uint(2545976125373043321668882106),
            uint(79523049711563516889815278582),
            uint(137188368200473961464493031138294480),
            uint(40502652147341205892296758212448164),
            uint(2656908582883325461947310084475)
        ];

        uint[COUNT_KNOWN_PRICES] memory expectedPrices = [
            uint(0.999896e6),
            uint(0.324535e6),
            uint(0.0000749e18),
            uint(0.000231044e18),
            uint(0.001032e6),
            uint(1.007457e6),
            uint(2.998302268e18),
            uint(26.1341125e18),
            uint(112771.368882e6)
        ];

        for (uint i = 0; i < tokens0.length; ++i) {
            uint price = UniswapV3MathLib.calcPriceOut(
                tokens0[i],
                tokens0[i],
                uint160(sqrtPricesX96[i]),
                IERC20Metadata(tokens0[i]).decimals(),
                IERC20Metadata(tokens1[i]).decimals(),
                0
            );
            console.log(i, price, expectedPrices[i]);
            assertApproxEqAbs(price, expectedPrices[i], price/100, "Price should be close to expected"); // todo
        }
    }
}
