// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console, Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {SiloAdvancedLib} from "../../src/strategies/libs/SiloAdvancedLib.sol";
import {ISilo} from "../../src/integrations/silo/ISilo.sol";
import {ISiloConfig} from "../../src/integrations/silo/ISiloConfig.sol";
import {SiloLeverageStrategy} from "../../src/strategies/SiloLeverageStrategy.sol";

contract SiloAdvancedLeveragePriceOracleTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STRATEGY = 0xDf077C7ffFa6B140d76dE75c792F49D6cB62AE19;
    address public vault;
    IPriceReader public priceReader;
    address public lendingVault;
    address public borrowingVault;
    address public collateralAsset;
    address public borrowAsset;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(13624880); // Mar-14-2025 07:49:27 AM +UTC
        vault = IStrategy(STRATEGY).vault();
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        
        // Get vault addresses from strategy
        ILeverageLendingStrategy strategy = ILeverageLendingStrategy(STRATEGY);
        strategy.health(); // Call health() but ignore all return values
        
        // Get vault addresses from strategy's description
        string memory desc = IStrategy(STRATEGY).description();
        console.log("Strategy description:", desc);
        
        // For now, use hardcoded addresses from the test environment
        lendingVault = 0x1234567890123456789012345678901234567890; // Replace with actual address
        borrowingVault = 0x0987654321098765432109876543210987654321; // Replace with actual address
        
        // Get asset addresses from vaults
        collateralAsset = ISilo(lendingVault).asset();
        borrowAsset = ISilo(borrowingVault).asset();
    }

    function testPriceNormalization() public view {
        // Get prices and decimals
        (uint collateralPrice,) = priceReader.getPrice(collateralAsset);
        (uint borrowPrice,) = priceReader.getPrice(borrowAsset);
        uint8 collateralDecimals = IERC20Metadata(collateralAsset).decimals();
        uint8 borrowDecimals = IERC20Metadata(borrowAsset).decimals();

        // Test normalization with different amounts
        uint[] memory testAmounts = new uint[](3);
        testAmounts[0] = 1e18; // 1 token
        testAmounts[1] = 100e18; // 100 tokens
        testAmounts[2] = 1000e18; // 1000 tokens

        for (uint i = 0; i < testAmounts.length; i++) {
            uint normalizedCollateral = SiloAdvancedLib.calculateNormalizedValue(
                testAmounts[i],
                collateralPrice,
                collateralDecimals
            );
            uint normalizedBorrow = SiloAdvancedLib.calculateNormalizedValue(
                testAmounts[i],
                borrowPrice,
                borrowDecimals
            );

            // Verify normalization results
            assertGt(normalizedCollateral, 0, "Normalized collateral should be greater than 0");
            assertGt(normalizedBorrow, 0, "Normalized borrow should be greater than 0");
            
            console.log(string.concat(
                "Amount: ", vm.toString(testAmounts[i]),
                " | Collateral Normalized: ", vm.toString(normalizedCollateral),
                " | Borrow Normalized: ", vm.toString(normalizedBorrow)
            ));
        }
    }

    function testTotalValueCalculation() public view {
        ILeverageLendingStrategy strategy = ILeverageLendingStrategy(STRATEGY);
        (,,, uint collateralAmount, uint debtAmount,) = strategy.health();
        
        // Calculate total value
        uint totalValue = SiloAdvancedLib.calcTotalWithPrices(
            PLATFORM,
            ILeverageLendingStrategy.LeverageLendingAddresses({
                collateralAsset: collateralAsset,
                borrowAsset: borrowAsset,
                lendingVault: lendingVault,
                borrowingVault: borrowingVault
            })
        );

        // Verify total value is reasonable
        assertGt(totalValue, 0, "Total value should be greater than 0");
        
        console.log(string.concat(
            "Initial Collateral: ", vm.toString(collateralAmount),
            " | Initial Borrow: ", vm.toString(debtAmount),
            " | Total Value: ", vm.toString(totalValue)
        ));
    }

    function testFlashLoanAmountCalculation() public view {
        // Get prices and decimals
        (uint collateralPrice,) = priceReader.getPrice(collateralAsset);
        uint8 collateralDecimals = IERC20Metadata(collateralAsset).decimals();
        
        // Test different deposit amounts and leverage values
        uint[] memory testAmounts = new uint[](3);
        testAmounts[0] = 1e18;
        testAmounts[1] = 10e18;
        testAmounts[2] = 100e18;
        
        uint[] memory testLeverages = new uint[](3);
        testLeverages[0] = 150_00; // 1.5x
        testLeverages[1] = 200_00; // 2x
        testLeverages[2] = 300_00; // 3x
        
        for (uint i = 0; i < testAmounts.length; i++) {
            for (uint j = 0; j < testLeverages.length; j++) {
                uint flashAmount = SiloAdvancedLib.calculateDepositFlashLoanAmount(
                    testAmounts[i],
                    testLeverages[j],
                    90_00, // depositParam0 = 90%
                    collateralPrice,
                    collateralDecimals
                );
                
                // Verify flash loan amount is reasonable
                assertGt(flashAmount, 0, "Flash loan amount should be greater than 0");
                
                console.log(string.concat(
                    "Deposit Amount: ", vm.toString(testAmounts[i]),
                    " | Leverage: ", vm.toString(testLeverages[j]),
                    " | Flash Amount: ", vm.toString(flashAmount)
                ));
            }
        }
    }

    function testValueDifferenceCalculation() public pure {
        // Test different scenarios for value difference calculation
        uint[] memory testValues = new uint[](3);
        testValues[0] = 100e18;
        testValues[1] = 1000e18;
        testValues[2] = 10000e18;
        
        for (uint i = 0; i < testValues.length; i++) {
            // Test profit scenario
            uint profitValue = SiloAdvancedLib.calculateValueDifference(
                testValues[i] * 2, // valueNow is double
                testValues[i],     // valueWas
                testValues[i]      // original amount
            );
            
            // Test loss scenario
            uint lossValue = SiloAdvancedLib.calculateValueDifference(
                testValues[i] / 2, // valueNow is half
                testValues[i],     // valueWas
                testValues[i]      // original amount
            );
            
            assertGt(profitValue, testValues[i], "Profit value should be greater than original amount");
            assertLt(lossValue, testValues[i], "Loss value should be less than original amount");
            
            console.log(string.concat(
                "Original Amount: ", vm.toString(testValues[i]),
                " | Profit Value: ", vm.toString(profitValue),
                " | Loss Value: ", vm.toString(lossValue)
            ));
        }
    }
} 