// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AvalancheSetup} from "../base/chains/AvalancheSetup.sol";
import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheConstantsLib.sol";
import {UniversalTest} from "../base/UniversalTest.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {SiloAdvancedLeverageStrategy} from "../../src/strategies/SiloAdvancedLeverageStrategy.sol";

contract SiALStrategyAvalancheTest is AvalancheSetup, UniversalTest {
    // uint public constant FORK_BLOCK_C_CHAIN = 73957229; // Dec-18-2025 06:27:32 AM +UTC
    // uint public constant FORK_BLOCK_C_CHAIN = 74277251; // Dec-23-2025 09:53:48 AM +UTC
    uint public constant FORK_BLOCK_C_CHAIN = 75107760; // Jan-05-2026 11:44:52 AM +UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("AVALANCHE_RPC_URL"), FORK_BLOCK_C_CHAIN));

        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;

        //        _upgradePlatform();
    }

    function testSiALAvalanche() public universalTest {
        // Let's test same strategy twice: with and without whitelisting
        // max ltv = 87%, liquidation threshold = 90% => max leverage = 1/(1-0.9) = 10
        _addStrategy(AvalancheConstantsLib.SILO_VAULT_142_SAVUSDC, AvalancheConstantsLib.SILO_VAULT_142_USDC, 85_00);
        //        _addStrategy(
        //            AvalancheConstantsLib.SILO_VAULT_153_SUSDP,
        //            AvalancheConstantsLib.SILO_VAULT_153_USDC,
        //            85_00
        //        );
    }

    function _preDeposit() internal override {
        // _addRoutesSUSDP();
        _addRoutesSAVUSD();
        _setFlashLoanVault(
            SiloAdvancedLeverageStrategy(payable(currentStrategy)),
            AvalancheConstantsLib.POOL_PHARAOH_V3_USDT_USDC,
            address(0),
            uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2)
        );
        // _setFlashLoanVault(SiloAdvancedLeverageStrategy(payable(currentStrategy)), AvalancheConstantsLib.BEETS_VAULT_V3, address(0), uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1));
    }

    function _addStrategy(
        address strategyInitAddress0,
        address strategyInitAddress1,
        uint targetLeveragePercent
    ) internal {
        address[] memory initStrategyAddresses = new address[](4);
        initStrategyAddresses[0] = strategyInitAddress0;
        initStrategyAddresses[1] = strategyInitAddress1;
        initStrategyAddresses[2] = AvalancheConstantsLib.BEETS_VAULT;
        initStrategyAddresses[3] = AvalancheConstantsLib.SILO_LENS;
        uint[] memory strategyInitNums = new uint[](1);
        strategyInitNums[0] = targetLeveragePercent;
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_ADVANCED_LEVERAGE,
                pool: address(0),
                farmId: type(uint).max,
                strategyInitAddresses: initStrategyAddresses,
                strategyInitNums: strategyInitNums
            })
        );
    }

    function _addRoutesSUSDP() internal {
        // add routes
        ISwapper swapper = ISwapper(IPlatform(platform).swapper());
        ISwapper.PoolData[] memory pools = new ISwapper.PoolData[](3);
        pools[0] = ISwapper.PoolData({
            pool: AvalancheConstantsLib.TOKEN_sUSDp,
            ammAdapter: (IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.ERC_4626)))).proxy,
            tokenIn: AvalancheConstantsLib.TOKEN_sUSDp,
            tokenOut: AvalancheConstantsLib.TOKEN_USDp
        });
        pools[1] = ISwapper.PoolData({
            pool: AvalancheConstantsLib.BEETS_STABLE_POOL_USDp_GAMI_USDC,
            ammAdapter: (IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.BALANCER_V3_STABLE)))).proxy,
            tokenIn: AvalancheConstantsLib.TOKEN_USDp,
            tokenOut: AvalancheConstantsLib.SILO_MANAGED_VAULT_GAMI_USDC
        });
        pools[2] = ISwapper.PoolData({
            pool: AvalancheConstantsLib.SILO_MANAGED_VAULT_GAMI_USDC,
            ammAdapter: (IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.ERC_4626)))).proxy,
            tokenIn: AvalancheConstantsLib.SILO_MANAGED_VAULT_GAMI_USDC,
            tokenOut: AvalancheConstantsLib.TOKEN_USDC
        });
        swapper.addPools(pools, false);
    }

    function _addRoutesSAVUSD() internal {
        // add routes
        ISwapper swapper = ISwapper(IPlatform(platform).swapper());
        ISwapper.PoolData[] memory pools = new ISwapper.PoolData[](2);
        pools[0] = ISwapper.PoolData({
            pool: AvalancheConstantsLib.POOL_LB_LFJ_LBPAIR_savUSDC_avUSD,
            ammAdapter: (IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.LBLFJ_V2)))).proxy,
            tokenIn: AvalancheConstantsLib.TOKEN_savUSD,
            tokenOut: AvalancheConstantsLib.TOKEN_avUSD
        });
        pools[1] = ISwapper.PoolData({
            pool: AvalancheConstantsLib.POOL_LB_LFJ_LBPAIR_avUSDC_USDC,
            ammAdapter: (IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.LBLFJ_V2)))).proxy,
            tokenIn: AvalancheConstantsLib.TOKEN_avUSD,
            tokenOut: AvalancheConstantsLib.TOKEN_USDC
        });
        swapper.addPools(pools, false);
    }

    function _upgradePlatform() internal {
        // we need to skip 1 day to update the swapper
        // but we cannot simply skip 1 day, because the silo oracle will start to revert with InvalidPrice
        // vm.warp(block.timestamp - 86400);
        rewind(86400);

        IPlatform platform = IPlatform(AvalancheConstantsLib.PLATFORM);

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        //        proxies[0] = platform.ammAdapter(keccak256(bytes(AmmAdapterIdLib.PHARAOH_V3))).proxy;
        //        implementations[0] = address(new PharaohV3Adapter());

        vm.startPrank(AvalancheConstantsLib.MULTISIG);
        platform.announcePlatformUpgrade("2025.12.2-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }

    function _setFlashLoanVault(
        SiloAdvancedLeverageStrategy strategy,
        address vaultC,
        address vaultB,
        uint kind
    ) internal {
        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();
        params[10] = kind;
        addresses[0] = vaultC;
        addresses[1] = vaultB;

        vm.prank(AvalancheConstantsLib.MULTISIG);
        strategy.setUniversalParams(params, addresses);
    }
}
