// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import "../base/chains/RealSetup.sol";

contract ZapTestReal is RealSetup {
    IZap public zap;

    struct ZapTestVars {
        address depositToken;
        address[] assets;
        IStrategy strategy;
        uint depositAmount;
        uint[] swapAmounts;
    }

    function setUp() public {
        _init();
        _deployVaults();
        zap = IZap(platform.zap());
    }

    function testZapReal() public {
        address vault = factory.deployedVault(0);

        ZapTestVars memory v;
        v.strategy = IVault(vault).strategy();
        v.assets = v.strategy.assets();
        v.depositToken = RealLib.TOKEN_USDC;
        v.depositAmount = 1000e6;
        (, v.swapAmounts) = zap.getDepositSwapAmounts(vault, v.depositToken, v.depositAmount);

        // need to swap v.swapAmounts[0] USDC to arcUSD by agg
        bytes[] memory swapData = new bytes[](2);
        swapData[0] = abi.encodeCall(ISwapper.swap, (v.depositToken, v.assets[0], v.swapAmounts[0], 1_000));
        // swapData[0] = abi.encodePacked(
        //   hex"fe029156000000000000000000000000c518a88c67ceca8b3f24c4562cb71deeb2af86b7000000000000000000000000aec9e50e3397f9ddc635c6c429c8c7eca418a14300000000000000000000000000000000000000000000000000000000009896800000000000000000000000000000000000000000000000000000000000002710"
        // );

        deal(v.depositToken, address(this), v.depositAmount);
        IERC20(v.depositToken).approve(address(zap), v.depositAmount);
        zap.deposit(vault, v.depositToken, v.depositAmount, platform.swapper(), swapData, 1, address(this));

        assertGt(IERC20(vault).balanceOf(address(this)), 0);
    }

    function _deployVaults() public {
        deal(platform.buildingPayPerVaultToken(), address(this), 100e6);
        IERC20(platform.buildingPayPerVaultToken()).approve(address(factory), 100e6);

        address[] memory vaultInitAddresses = new address[](0);
        uint[] memory vaultInitNums = new uint[](0);
        address[] memory initStrategyAddresses = new address[](0);
        uint[] memory initStrategyNums = new uint[](1);
        int24[] memory initStrategyTicks = new int24[](0);
        // farmId
        initStrategyNums[0] = 0; // arcUSD-USDC
        factory.deployVaultAndStrategy(
            VaultTypeLib.COMPOUNDING,
            StrategyIdLib.TRIDENT_PEARL_FARM,
            vaultInitAddresses,
            vaultInitNums,
            initStrategyAddresses,
            initStrategyNums,
            initStrategyTicks
        );
    }
}
