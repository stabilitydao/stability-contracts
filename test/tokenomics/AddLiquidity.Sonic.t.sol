// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IAmmAdapter} from "../../src/interfaces/IAmmAdapter.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IRouterV2} from "../../src/integrations/swapx/IRouterV2.sol";
import {ISolidlyRouter} from "../../src/integrations/shadow/ISolidlyRouter.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Sale} from "../../src/tokenomics/Sale.sol";

contract AddLiquidityTestSonic is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant SOLIDLY_ADAPTER = 0xE3374041F173FFCB0026A82C6EEf94409F713Cf9;
    address public constant SALE = 0x0a02Be0de3Dd109B1AbF4C197f0B58A3bb68eA1F;
    address public multisig;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(11840000); // Mar-05-2025 04:14:51 PM +UTC
        multisig = IPlatform(PLATFORM).multisig();
    }

    function test_addLiq() public {
        (uint sPrice,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(SonicConstantsLib.TOKEN_WS);
        //console.log('S price', sPrice);
        uint needAddSTBL = 150_000 * 1e18 * sPrice / 1e18 * 1e18 / 0.18e18;
        needAddSTBL = needAddSTBL * 99_45 / 100_00;
        //console.log('Need add STBL to S pair', needAddSTBL);
        //console.log("");
        uint deadLine = 1741208400; // Wed Mar 05 2025 21:00:00 GMT+0000

        vm.startPrank(multisig);

        // SwapX
        uint usdcAmount = 250_000 * 1e6;
        uint stblAmount = 1_384_700 * 1e18;

        // approve USDC
        /*console.log("Tx#1. Approve USDC for SwapX router");
        console.log("Address", SonicConstantsLib.TOKEN_USDC);
        console.log('ABI: [{"type": "function","name": "approve","inputs": [{"name": "spender","type": "address","internalType": "address"},{"name": "amount","type": "uint256","internalType": "uint256"}],"outputs": [{"name": "","type": "bool","internalType": "bool"}],"stateMutability": "nonpayable"}]');
        console.log("Spender", SonicConstantsLib.SWAPX_ROUTER_V2);
        console.log("Amount", usdcAmount);
        console.log("");*/
        IERC20(SonicConstantsLib.TOKEN_USDC).approve(SonicConstantsLib.SWAPX_ROUTER_V2, usdcAmount);

        // approve STBL
        /*console.log("Tx#2. Approve STBL for SwapX router");
        console.log("Address", SonicConstantsLib.TOKEN_STBL);
        console.log('ABI: [{"type": "function","name": "approve","inputs": [{"name": "spender","type": "address","internalType": "address"},{"name": "amount","type": "uint256","internalType": "uint256"}],"outputs": [{"name": "","type": "bool","internalType": "bool"}],"stateMutability": "nonpayable"}]');
        console.log("Spender", SonicConstantsLib.SWAPX_ROUTER_V2);
        console.log("Amount", stblAmount);
        console.log("");*/
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(SonicConstantsLib.SWAPX_ROUTER_V2, stblAmount);

        // add liquidity
        /*console.log("Tx#3. Add USDC+STBL liquidity to SwapX");
        console.log("Address", SonicConstantsLib.SWAPX_ROUTER_V2);
        console.log('ABI: [{"type": "function","name": "addLiquidity","inputs": [{"name": "tokenA","type": "address","internalType": "address"},{"name": "tokenB","type": "address","internalType": "address"},{"name": "stable","type": "bool","internalType": "bool"},{"name": "amountADesired","type": "uint256","internalType": "uint256"},{"name": "amountBDesired","type": "uint256","internalType": "uint256"},{"name": "amountAMin","type": "uint256","internalType": "uint256"},{"name": "amountBMin","type": "uint256","internalType": "uint256"},{"name": "to","type": "address","internalType": "address"},{"name": "deadline","type": "uint256","internalType": "uint256"}],"outputs": [{"name": "amountA","type": "uint256","internalType": "uint256"},{"name": "amountB","type": "uint256","internalType": "uint256"},{"name": "liquidity","type": "uint256","internalType": "uint256"}],"stateMutability": "nonpayable"}]');
        console.log("tokenA", SonicConstantsLib.TOKEN_USDC);
        console.log("tokenB", SonicConstantsLib.TOKEN_STBL);
        console.log("stable false");
        console.log("amountADesired", usdcAmount);
        console.log("amountBDesired", stblAmount);
        console.log("amountAMin", usdcAmount * 999 / 1000);
        console.log("amountBMin", stblAmount * 999 / 1000);
        console.log("to", multisig);
        console.log("deadLine", deadLine);
        console.log("");*/
        IRouterV2(SonicConstantsLib.SWAPX_ROUTER_V2)
            .addLiquidity(
                SonicConstantsLib.TOKEN_USDC,
                SonicConstantsLib.TOKEN_STBL,
                false,
                usdcAmount,
                stblAmount,
                usdcAmount * 999 / 1000,
                stblAmount * 999 / 1000,
                multisig,
                deadLine
            );

        // Shadow
        uint sAmount = 150_000 * 1e18;

        // approve STBL
        /*console.log("Tx#4. Approve STBL for Shadow router");
        console.log("Address", SonicConstantsLib.TOKEN_STBL);
        console.log('ABI: [{"type": "function","name": "approve","inputs": [{"name": "spender","type": "address","internalType": "address"},{"name": "amount","type": "uint256","internalType": "uint256"}],"outputs": [{"name": "","type": "bool","internalType": "bool"}],"stateMutability": "nonpayable"}]');
        console.log("Spender", SonicConstantsLib.SHADOW_ROUTER);
        console.log("Amount", needAddSTBL);
        console.log("");*/
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(SonicConstantsLib.SHADOW_ROUTER, needAddSTBL);

        // add liquidity
        /*console.log("Tx#5. Add S+STBL liquidity to Shadow");
        console.log("Address", SonicConstantsLib.SHADOW_ROUTER);
        console.log('ABI: [{"type": "function","name": "addLiquidityETH","inputs": [{"name": "token","type": "address","internalType": "address"},{"name": "stable","type": "bool","internalType": "bool"},{"name": "amountTokenDesired","type": "uint256","internalType": "uint256"},{"name": "amountTokenMin","type": "uint256","internalType": "uint256"},{"name": "amountETHMin","type": "uint256","internalType": "uint256"},{"name": "to","type": "address","internalType": "address"},{"name": "deadline","type": "uint256","internalType": "uint256"}],"outputs": [{"name": "amountToken","type": "uint256","internalType": "uint256"},{"name": "amountETH","type": "uint256","internalType": "uint256"},{"name": "liquidity","type": "uint256","internalType": "uint256"}],"stateMutability": "payable"}]');
        console.log("S value", sAmount);
        console.log("token", SonicConstantsLib.TOKEN_STBL);
        console.log("stable false");
        console.log("amountTokenDesired", needAddSTBL);
        console.log("amountTokenMin", needAddSTBL * 999 / 1000);
        console.log("amountETHMin", sAmount * 999 / 1000);
        console.log("to", multisig);
        console.log("deadLine", deadLine);
        console.log("");*/
        ISolidlyRouter(SonicConstantsLib.SHADOW_ROUTER)
        .addLiquidityETH{
            value: sAmount
        }(
            SonicConstantsLib.TOKEN_STBL,
            false,
            needAddSTBL,
            needAddSTBL * 999 / 1000,
            sAmount * 999 / 1000,
            multisig,
            deadLine
        );

        // enable claim
        /*console.log("Tx#6. Setup token on Sale contract to allow claim");
        console.log("Address", SALE);
        console.log('ABI: [{"type": "function","name": "setupToken","inputs": [{"name": "token_","type": "address","internalType": "address"}],"outputs": [],"stateMutability": "nonpayable"}]');
        console.log("token", SonicConstantsLib.TOKEN_STBL);
        console.log("");*/
        Sale(SALE).setupToken(SonicConstantsLib.TOKEN_STBL);

        // check price
        address poolSwapX = IRouterV2(SonicConstantsLib.SWAPX_ROUTER_V2)
            .pairFor(SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_STBL, false);
        address poolShadow = ISolidlyRouter(SonicConstantsLib.SHADOW_ROUTER)
            .pairFor(SonicConstantsLib.TOKEN_WS, SonicConstantsLib.TOKEN_STBL, false);
        uint price = IAmmAdapter(SOLIDLY_ADAPTER)
            .getPrice(poolSwapX, SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.TOKEN_USDC, 1e18);
        assertEq(price, 180002); // $0.18
        price = IAmmAdapter(SOLIDLY_ADAPTER)
            .getPrice(poolShadow, SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.TOKEN_WS, 1e18);
        price = price * sPrice / 1e18;
        //console.log('price of stbl per $', price);
        assertGt(price, 180090000000000000); // $0.18
        assertLt(price, 180100000000000000); // $0.18

        vm.stopPrank();
    }
}
