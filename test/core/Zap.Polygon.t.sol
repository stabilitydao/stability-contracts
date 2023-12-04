// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import "../base/chains/PolygonSetup.sol";
import "../../src/core/libs/VaultTypeLib.sol";
import "../../src/strategies/libs/StrategyIdLib.sol";

contract ZapTest is PolygonSetup {
    constructor() {
        _init();

        deal(platform.buildingPayPerVaultToken(), address(this), 5e24);
        IERC20(platform.buildingPayPerVaultToken()).approve(address(factory), 5e24);

        deal(platform.targetExchangeAsset(), address(this), 1e9);
        IERC20(platform.targetExchangeAsset()).approve(address(factory), 1e9);
    }

    function testZapDepositWithdraw() public {
        {
            address[] memory vaultInitAddresses = new address[](0);
            uint[] memory vaultInitNums = new uint[](0);
            address[] memory initStrategyAddresses = new address[](0);
            uint[] memory initStrategyNums = new uint[](1);
            int24[] memory initStrategyTicks = new int24[](0);
            // farmId
            initStrategyNums[0] = 6; // WMATIC-USDC narrow

            factory.deployVaultAndStrategy(
                VaultTypeLib.COMPOUNDING,
                StrategyIdLib.GAMMA_QUICKSWAP_FARM,
                vaultInitAddresses,
                vaultInitNums,
                initStrategyAddresses,
                initStrategyNums,
                initStrategyTicks
            );

            initStrategyNums[0] = 7; // WMATIC-WETH wide
            factory.deployVaultAndStrategy(
                VaultTypeLib.COMPOUNDING,
                StrategyIdLib.GAMMA_QUICKSWAP_FARM,
                vaultInitAddresses,
                vaultInitNums,
                initStrategyAddresses,
                initStrategyNums,
                initStrategyTicks
            );
        }

        address vault = factory.deployedVault(0);
        address vault1 = factory.deployedVault(1);

        IZap zap = IZap(platform.zap());

        (, uint[] memory swapAmounts) = zap.getDepositSwapAmounts(vault, PolygonLib.TOKEN_USDC, 1000e6);
        assertEq(swapAmounts.length, 2);
        assertGt(swapAmounts[0], 0);
        assertEq(swapAmounts[1], 0);

        (, swapAmounts) = zap.getDepositSwapAmounts(vault, PolygonLib.TOKEN_WMATIC, 1000e18);
        assertEq(swapAmounts[0], 0);
        assertGt(swapAmounts[1], 0);

        (, swapAmounts) = zap.getDepositSwapAmounts(vault, PolygonLib.TOKEN_WETH, 1e18);
        assertGt(swapAmounts[0], 0);
        assertGt(swapAmounts[1], 0);
        console.log("Deposit WETH to WMATIC-USDC Gamma LP");
        console.log("swapAmounts[0]", swapAmounts[0]);
        console.log("swapAmounts[1]", swapAmounts[1]);

        (, swapAmounts) = zap.getDepositSwapAmounts(vault1, PolygonLib.TOKEN_USDC, 1000e6);
        assertGt(swapAmounts[0], 0); // 20806874719093983
        assertGt(swapAmounts[1], 0); // 979193125280906017

        // deposit weth -> wmatic/usdc gamma lp

        // swap WETH -> WMATIC by POLYGON_UNISWAP_V3
        // https://api.1inch.dev/swap/v5.2/137/swap?src=0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619&dst=0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270&amount=20806874719093983&from=0x3d0c177E035C30bb8681e5859EB98d114b48b935&slippage=10&protocols=POLYGON_UNISWAP_V3&disableEstimate=true
        //         {
        //   "toAmount": "51283287647306023209",
        //   "tx": {
        //     "from": "0x3d0c177e035c30bb8681e5859eb98d114b48b935",
        //     "to": "0x1111111254eeb25477b68fb85ed929f73a960582",
        //     "data":"0xe449022e0000000000000000000000000000000000000000000000000049ebbe088484df00000000000000000000000000000000000000000000000280875a9072ab0dd80000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000180000000000000000000000086f1d8390222a3691c28938ec7404a1661e618e08b1ccac8",
        //     "value": "0",
        //     "gas": 0,
        //     "gasPrice": "191557371430"
        //   }
        // }

        // swap WETH -> USDC
        // https://api.1inch.dev/swap/v5.2/137/swap?src=0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619&dst=0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174&amount=979193125280906017&from=0x3d0c177E035C30bb8681e5859EB98d114b48b935&slippage=1&protocols=POLYGON_BALANCER_V2&disableEstimate=true

        // {
        //   "toAmount": "1999803300",
        //   "tx": {
        //     "from": "0x3d0c177e035c30bb8681e5859eb98d114b48b935",
        //     "to": "0x1111111254eeb25477b68fb85ed929f73a960582",
        //     "data": "0xe449022e0000000000000000000000000000000000000000000000000d96caf59edf7b21000000000000000000000000000000000000000000000000000000006bd0c3350000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000180000000000000000000000045dda9cb7c25131df268515131f647d726f506088b1ccac8",
        //     "value": "0",
        //     "gas": 0,
        //     "gasPrice": "190418024600"
        //   }
        // }

        bytes[] memory swapData = new bytes[](2);
        swapData[0] = abi.encodePacked(
            hex"e449022e0000000000000000000000000000000000000000000000000049ebbe088484df00000000000000000000000000000000000000000000000280875a9072ab0dd80000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000180000000000000000000000086f1d8390222a3691c28938ec7404a1661e618e08b1ccac8"
        );
        swapData[1] = abi.encodePacked(
            hex"e449022e0000000000000000000000000000000000000000000000000d96caf59edf7b21000000000000000000000000000000000000000000000000000000005fa1b0d20000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000180000000000000000000000045dda9cb7c25131df268515131f647d726f506088b1ccac8"
        );

        deal(PolygonLib.TOKEN_WETH, address(this), 20e18);
        IERC20(PolygonLib.TOKEN_WETH).approve(address(zap), 20e18);
        zap.deposit(vault, PolygonLib.TOKEN_WETH, 1e18, PolygonLib.ONE_INCH, swapData, 1, msg.sender);

        swapData[0] = abi.encodePacked(
            hex"0502b1c50000000000000000000000007ceb23fd6bc0add59e62ac25578270cff1b9f61900000000000000000000000000000000000000000000000002c968c9e41684df00000000000000000000000000000000000000000000001c55dd81de2a6ff3380000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000180000000000000003b6d0340c4e595acdd7d12fec385e5da5d43160e8a0bac0e8b1ccac8"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IZap.AggSwapFailed.selector,
                string(
                    abi.encodePacked(
                        hex"08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002645524332303a207472616e7366657220616d6f756e7420657863656564732062616c616e63650000000000000000000000000000000000000000000000000000"
                    )
                )
            )
        );
        zap.deposit(vault, PolygonLib.TOKEN_WETH, 1e18, PolygonLib.ONE_INCH, swapData, 1, address(0));
        swapData[0] = abi.encodePacked(
            hex"e449022e0000000000000000000000000000000000000000000000000049ebbe088484df00000000000000000000000000000000000000000000000280875a9072ab0dd80000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000180000000000000000000000086f1d8390222a3691c28938ec7404a1661e618e08b1ccac8"
        );

        zap.deposit(vault, PolygonLib.TOKEN_WETH, 1e18, PolygonLib.ONE_INCH, swapData, 1, address(0));

        vm.expectRevert(IControllable.IncorrectZeroArgument.selector);
        zap.deposit(vault, PolygonLib.TOKEN_WETH, 0, PolygonLib.ONE_INCH, swapData, 1, msg.sender);

        vm.expectRevert(abi.encodeWithSelector(IZap.NotAllowedDexAggregator.selector, address(10)));
        zap.deposit(vault, PolygonLib.TOKEN_WETH, 1e18, address(10), swapData, 1, msg.sender);

        vm.roll(block.number + 6);
        IERC20(vault).approve(address(zap), 2e18);
        IStrategy strategy = IVault(vault).strategy();
        address[] memory assets = strategy.assets();
        uint[] memory minToWithdraw = new uint[](assets.length);
        minToWithdraw[0] = 0;
        minToWithdraw[1] = 0;

        // swap WMATIC -> USDT
        /* 
        {
        "toAmount": "996136",
        "tx": {
            "from": "0x3d0c177e035c30bb8681e5859eb98d114b48b935",
            "to": "0x1111111254eeb25477b68fb85ed929f73a960582",
            "data": "0xe449022e0000000000000000000000000000000000000000000000001220ba3253bd31be0000000000000000000000000000000000000000000000000000000000079994000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000010000000000000000000000009b08288c3be4f62bbf8d1c20ac9c5e6f9467d8b78b1ccac8",
            "value": "0",
            "gas": 0,
            "gasPrice": "446206898092"
        }
        }

        // swap USDC -> USDT

        {
        "toAmount": "322732",
        "tx": {
            "from": "0x3d0c177e035c30bb8681e5859eb98d114b48b935",
            "to": "0x1111111254eeb25477b68fb85ed929f73a960582",
            "data": "0xe449022e000000000000000000000000000000000000000000000000000000000004ed0b000000000000000000000000000000000000000000000000000000000002765600000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000dac8a8e6dbf8c690ec6815e0ff03491b2770255d8b1ccac8",
            "value": "0",
            "gas": 0,
            "gasPrice": "337104975215"
        }
        }
        */
        // wmatic 1306248617253482942
        // usdc 322827
        swapData[0] = abi.encodePacked(
            hex"e449022e0000000000000000000000000000000000000000000000001220ba3253bd31be0000000000000000000000000000000000000000000000000000000000079994000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000010000000000000000000000009b08288c3be4f62bbf8d1c20ac9c5e6f9467d8b78b1ccac8"
        );
        swapData[1] = abi.encodePacked(
            hex"e449022e000000000000000000000000000000000000000000000000000000000004ed0b000000000000000000000000000000000000000000000000000000000002765600000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000dac8a8e6dbf8c690ec6815e0ff03491b2770255d8b1ccac8"
        );
        deal(PolygonLib.TOKEN_USDT, address(this), 0);

        vm.expectRevert(abi.encodeWithSelector(IZap.NotAllowedDexAggregator.selector, address(10)));
        zap.withdraw(vault, PolygonLib.TOKEN_USDT, address(10), swapData, 1e18, minToWithdraw);

        swapData[0] = abi.encodePacked(
            hex"0502b1c50000000000000000000000000d500b1d8e8ef31e21c99d1db9a6444d3adf12700000000000000000000000000000000000000000000000008f072683364131be00000000000000000000000000000000000000000000000000000000007f0ed10000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000100000000000000003b6d0340604229c960e5cacf2aaeac8be68ac07ba9df81c38b1ccac8"
        );
        vm.expectRevert(abi.encodeWithSelector(IZap.AggSwapFailed.selector, ""));
        zap.withdraw(vault, PolygonLib.TOKEN_USDT, PolygonLib.ONE_INCH, swapData, 1e18, minToWithdraw);
        swapData[0] = abi.encodePacked(
            hex"e449022e0000000000000000000000000000000000000000000000001220ba3253bd31be0000000000000000000000000000000000000000000000000000000000079994000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000010000000000000000000000009b08288c3be4f62bbf8d1c20ac9c5e6f9467d8b78b1ccac8"
        );

        zap.withdraw(vault, PolygonLib.TOKEN_USDT, PolygonLib.ONE_INCH, swapData, 1e18, minToWithdraw);
        assertApproxEqAbs(IERC20(PolygonLib.TOKEN_USDT).balanceOf(address(this)), 1e6, 1000);
    }
}
