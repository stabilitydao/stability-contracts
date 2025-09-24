// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../chains/sonic/SonicLib.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IUniswapV3Pool} from "../../src/integrations/uniswapv3/IUniswapV3Pool.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {RecoveryLib} from "../../src/tokenomics/libs/RecoveryLib.sol";
import {Recovery} from "../../src/tokenomics/Recovery.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Test} from "forge-std/Test.sol";
import {UniswapV3Callee} from "../../src/test/UniswapV3Callee.sol";
import {console} from "forge-std/console.sol";

contract RecoverySonicTest is Test {
    uint public constant FORK_BLOCK = 47854805; // Sep-23-2025 04:02:39 AM +UTC
    address multisig;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();
    }

    //region --------------------------------- Data types
    struct SingleTestCase {
        address recoveryPool;
        address asset;
    }

    struct SingleState {
        int24 tick;
        uint sqrtPriceX96;
        uint128 liquidity;
        uint balanceRecoveryTokenUser;
        uint balanceMetaVaultTokenUser;
        uint balanceMetaVaultTokenInRecovery;
        uint balanceRecoveryTokenInRecovery;
    }

    struct MultipleTestCase {
        address[] pools;
        uint[] amounts;
        address[] inputAssets;
        uint[] inputAmounts;
    }

    struct MultipleState {
        int24[] ticks;
        uint[] sqrtPriceX96s;
        uint128[] liquidity;
        uint[] balanceRecoveryTokenUsers;
        uint[] balanceMetaVaultTokenUsers;
        uint[] balanceMetaVaultTokenInRecovery;
        uint[] balanceRecoveryTokenInRecovery;
    }
    //endregion --------------------------------- Data types

    //region --------------------------------- Unit tests
    function testRecoveryStorageLocation() public pure {
        assertEq(
            keccak256(abi.encode(uint(keccak256("erc7201:stability.Recovery")) - 1)) & ~bytes32(uint(0xff)),
            RecoveryLib._RECOVERY_STORAGE_LOCATION,
            "_RECOVERY_STORAGE_LOCATION"
        );
    }
    //endregion --------------------------------- Unit tests

    //region --------------------------------- Use Recovery with single recovery token
    function fixtureSingle() public pure returns (SingleTestCase[] memory) {
        SingleTestCase[] memory cases = new SingleTestCase[](3); // todo 6: we need to add liquidity
        cases[0] = SingleTestCase({
            recoveryPool: SonicConstantsLib.RECOVERY_POOL_CREDIX_METAUSD,
            asset: SonicConstantsLib.WRAPPED_METAVAULT_METAUSD
        });
        cases[1] = SingleTestCase({
            recoveryPool: SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAUSD,
            asset: SonicConstantsLib.TOKEN_USDC
        });
        cases[2] = SingleTestCase({
            recoveryPool: SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAS,
            asset: SonicConstantsLib.WRAPPED_METAVAULT_METAS
        });
//        cases[3] = SingleTestCase({
//            recoveryPool: SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAUSDC
//        });
//        cases[4] = SingleTestCase({
//            recoveryPool: SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETASCUSD
//        });
//        cases[5] = SingleTestCase({
//            recoveryPool: SonicConstantsLib.RECOVERY_POOL_CREDIX_METAS
//        });

        return cases;
    }

    function tableSingleTest(SingleTestCase memory single) public {
        _testSinglePoolSingleUserSwapsAll(single.recoveryPool, single.asset);
    }

    function _testSinglePoolSingleUserSwapsAll(address pool, address asset) internal {
        ISwapper swapper = ISwapper(IPlatform(SonicConstantsLib.PLATFORM).swapper());

        // assume here that recovery tokens are always set as token 0
        address recoveryToken = IUniswapV3Pool(pool).token0();
        // assume here that meta-vault tokens are always set as token 1
        address metaVaultToken = IUniswapV3Pool(pool).token1();

        uint amountRecoveryTokenToSwap = 10e18;
        uint amountAssetToPutOnRecovery = 100e18;

        SingleState[4] memory states;

        // ------------------------- Prepare user balances
        address user1 = makeAddr("user1");
        deal(recoveryToken, user1, amountRecoveryTokenToSwap * 2);

        vm.prank(user1);
        IERC20(recoveryToken).approve(address(swapper), type(uint).max);

        _addPoolsForRecoveryTokens();

        // ------------------------- Setup
        Recovery recovery;
        {
            Proxy proxy = new Proxy();
            proxy.initProxy(address(new Recovery()));
            recovery = Recovery(address(proxy));
            recovery.initialize(SonicConstantsLib.PLATFORM);
        }
        {
            address[] memory pools = new address[](1);
            pools[0] = pool;

            vm.prank(multisig);
            recovery.addRecoveryPools(pools);
        }

        // ------------------------- User makes first swap
        states[0] = getState(IUniswapV3Pool(pool), user1, recovery);
        vm.prank(user1);
        swapper.swap(recoveryToken, metaVaultToken, amountRecoveryTokenToSwap, 100_000);

        // ------------------------- Put some tokens on Recovery balance and register them
        address[] memory tokens = new address[](1);
        tokens[0] = asset;

        deal(metaVaultToken, address(recovery), amountAssetToPutOnRecovery);

        vm.prank(multisig);
        recovery.registerAssets(tokens);
        states[1] = getState(IUniswapV3Pool(pool), user1, recovery);

        assertLt(states[1].sqrtPriceX96, states[0].sqrtPriceX96, "price should go down");
        assertLt(states[1].balanceRecoveryTokenUser, states[0].balanceRecoveryTokenUser, "user should spent recovery tokens");
        assertGt(states[1].balanceMetaVaultTokenUser, states[0].balanceMetaVaultTokenUser, "user should receive meta vault tokens");

        // ------------------------- Swap assets for recovery tokens
        vm.prank(multisig);
        recovery.swapAssetsToRecoveryTokens(0);
        states[2] = getState(IUniswapV3Pool(pool), user1, recovery);

        assertEq(states[2].sqrtPriceX96, states[0].sqrtPriceX96, "price should return to initial 1");
        assertGt(states[1].balanceMetaVaultTokenInRecovery, states[0].balanceMetaVaultTokenInRecovery, "Recovery should spent meta vault tokens");
        assertEq(states[1].balanceRecoveryTokenInRecovery, 0, "all recovery tokens should be burnt");

        // ------------------------- User makes second swap
        vm.prank(user1);
        swapper.swap(recoveryToken, metaVaultToken, amountRecoveryTokenToSwap, 100_000);
        states[3] = getState(IUniswapV3Pool(pool), user1, recovery);

        assertEq(states[3].sqrtPriceX96, states[1].sqrtPriceX96, "price should chane to the same value as after first swap");
        assertEq(states[3].balanceRecoveryTokenUser, 0, "user should spent all recovery tokens");
        assertEq(states[3].balanceMetaVaultTokenUser, 2 * states[1].balanceMetaVaultTokenUser, "user should receive same amount of meta vault tokens as in first swap");
        assertApproxEqAbs(states[3].balanceMetaVaultTokenUser, states[0].balanceRecoveryTokenUser, states[0].balanceRecoveryTokenUser * 12 / 100, "user should exchange tokens near to 1:1 (delta 12% max)");

    }

    //endregion --------------------------------- Use Recovery with single recovery token

    //region --------------------------------- Use Recovery with multiple recovery tokens
    function fixtureMultiple() public pure returns (MultipleTestCase[] memory) {
        address[] memory recoveryPools0 = new address[](3);
        recoveryPools0[0] = SonicConstantsLib.RECOVERY_POOL_CREDIX_METAUSD;
        recoveryPools0[1] = SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAUSD;
        recoveryPools0[2] = SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAS;

        uint[] memory amounts0 = new uint[](3);
        amounts0[0] = 10e18;
        amounts0[1] = 20e18;
        amounts0[2] = 30e18;

        address[] memory inputAssets0 = new address[](2);
        inputAssets0[0] = SonicConstantsLib.WRAPPED_METAVAULT_METAUSD;
        inputAssets0[1] = SonicConstantsLib.TOKEN_USDC;

        uint[] memory inputAmounts0 = new uint[](2);
        inputAmounts0[0] = 100e18;
        inputAmounts0[1] = 200e18;

        MultipleTestCase[] memory cases = new MultipleTestCase[](1);
        cases[0] = MultipleTestCase({
            pools: recoveryPools0,
            amounts: amounts0,
            inputAssets: inputAssets0,
            inputAmounts: inputAmounts0
        });

        return cases;
    }

    function tableMultipleTest(MultipleTestCase memory multiple) public {
        _testMultiplePoolsSingleUserSwapsAll(multiple);
    }

    function _testMultiplePoolsSingleUserSwapsAll(MultipleTestCase memory multiple) internal {
        SingleState[4][] memory states = new SingleState[4][](multiple.pools.length);
        address user1 = makeAddr("user1");
        ISwapper swapper = ISwapper(IPlatform(SonicConstantsLib.PLATFORM).swapper());

        for (uint i; i < multiple.pools.length; ++i) {
            // assume here that recovery tokens are always set as token 0
            address recoveryToken = IUniswapV3Pool(multiple.pools[i]).token0();

            // ------------------------- Prepare user balances
            deal(recoveryToken, user1, multiple.amounts[i] * 2);

            vm.prank(user1);
            IERC20(recoveryToken).approve(address(swapper), type(uint).max);
        }

        _addPoolsForRecoveryTokens();

        // ------------------------- Setup
        Recovery recovery;
        {
            Proxy proxy = new Proxy();
            proxy.initProxy(address(new Recovery()));
            recovery = Recovery(address(proxy));
            recovery.initialize(SonicConstantsLib.PLATFORM);
        }

        vm.prank(multisig);
        recovery.addRecoveryPools(multiple.pools);

        // ------------------------- User makes first swap
        for (uint i; i < multiple.pools.length; ++i) {
            address recoveryToken = IUniswapV3Pool(multiple.pools[i]).token0();
            address metaVaultToken = IUniswapV3Pool(multiple.pools[i]).token1();

            states[i][0] = getState(IUniswapV3Pool(multiple.pools[i]), user1, recovery);

            vm.prank(user1);
            swapper.swap(recoveryToken, metaVaultToken, multiple.amounts[i], 100_000);
        }

        // ------------------------- Put some tokens on Recovery balance and register them
        for (uint i; i < multiple.inputAssets.length; ++i) {
            deal(multiple.inputAssets[i], address(recovery), multiple.inputAmounts[i]);
        }

        vm.prank(multisig);
        recovery.registerAssets(multiple.inputAssets);
        for (uint i; i < multiple.pools.length; ++i) {
            states[i][1] = getState(IUniswapV3Pool(multiple.pools[i]), user1, recovery);
// todo
//            assertLt(states[1].sqrtPriceX96, states[0].sqrtPriceX96, "price should go down");
//            assertLt(states[1].balanceRecoveryTokenUser, states[0].balanceRecoveryTokenUser, "user should spent recovery tokens");
//            assertGt(states[1].balanceMetaVaultTokenUser, states[0].balanceMetaVaultTokenUser, "user should receive meta vault tokens");
        }

        // ------------------------- Swap assets for recovery tokens
        vm.prank(multisig);
        recovery.swapAssetsToRecoveryTokens(0);
        for (uint i; i < multiple.pools.length; ++i) {
            states[i][2] = getState(IUniswapV3Pool(multiple.pools[i]), user1, recovery);
//            assertEq(states[2].sqrtPriceX96, states[0].sqrtPriceX96, "price should return to initial 1");
//            assertGt(states[1].balanceMetaVaultTokenInRecovery, states[0].balanceMetaVaultTokenInRecovery, "Recovery should spent meta vault tokens");
//            assertEq(states[1].balanceRecoveryTokenInRecovery, 0, "all recovery tokens should be burnt");
        }


        // ------------------------- User makes second swap
        for (uint i; i < multiple.pools.length; ++i) {
            address recoveryToken = IUniswapV3Pool(multiple.pools[i]).token0();
            address metaVaultToken = IUniswapV3Pool(multiple.pools[i]).token1();

            vm.prank(user1);
            swapper.swap(recoveryToken, metaVaultToken, multiple.amounts[i], 100_000);

            states[i][3] = getState(IUniswapV3Pool(multiple.pools[i]), user1, recovery);
//            assertEq(states[3].sqrtPriceX96, states[1].sqrtPriceX96, "price should chane to the same value as after first swap");
//            assertEq(states[3].balanceRecoveryTokenUser, 0, "user should spent all recovery tokens");
//            assertEq(states[3].balanceMetaVaultTokenUser, 2 * states[1].balanceMetaVaultTokenUser, "user should receive same amount of meta vault tokens as in first swap");
//            assertApproxEqAbs(states[3].balanceMetaVaultTokenUser, states[0].balanceRecoveryTokenUser, states[0].balanceRecoveryTokenUser * 12 / 100, "user should exchange tokens near to 1:1 (delta 12% max)");
        }


    }
    //endregion --------------------------------- Use Recovery with multiple recovery tokens

    //region --------------------------------- Uniswap v3 utils
    function _openPosition(address user, IUniswapV3Pool pool) internal {
        UniswapV3Callee callee = new UniswapV3Callee();

        IERC20 recoveryToken = IERC20(pool.token0());
        uint recoveryAmount = IERC20(recoveryToken).balanceOf(user);

        vm.prank(user);
        recoveryToken.transfer(address(callee), recoveryAmount);

        vm.prank(address(callee));
        recoveryToken.approve(address(pool), recoveryAmount);

        (, int24 tick, , , , , ) = pool.slot0();

        int24 tickSpacing = pool.tickSpacing();
        int24 tickLower = (tick / tickSpacing) * tickSpacing;
        int24 tickUpper = tickLower + tickSpacing;

        vm.prank(user);
        callee.mint(address(pool), user, tickLower, tickUpper, uint128(recoveryAmount));
    }
    //endregion --------------------------------- Uniswap v3 utils

    //region --------------------------------- Utils
    function _addPoolsForRecoveryTokens() internal {
        ISwapper swapper = ISwapper(IPlatform(SonicConstantsLib.PLATFORM).swapper());

        ISwapper.AddPoolData[] memory pools = new ISwapper.AddPoolData[](6);
        pools[0] = SonicLib._makePoolData(
            SonicConstantsLib.RECOVERY_POOL_CREDIX_METAUSD,
            AmmAdapterIdLib.UNISWAPV3,
            SonicConstantsLib.RECOVERY_TOKEN_CREDIX_METAUSD,
            SonicConstantsLib.WRAPPED_METAVAULT_METAUSD
        );
        pools[1] = SonicLib._makePoolData(
            SonicConstantsLib.RECOVERY_POOL_CREDIX_METAS,
            AmmAdapterIdLib.UNISWAPV3,
            SonicConstantsLib.RECOVERY_TOKEN_CREDIX_METAS,
            SonicConstantsLib.WRAPPED_METAVAULT_METAS
        );
        pools[2] = SonicLib._makePoolData(
            SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAS,
            AmmAdapterIdLib.UNISWAPV3,
            SonicConstantsLib.RECOVERY_TOKEN_CREDIX_WMETAS,
            SonicConstantsLib.WRAPPED_METAVAULT_METAS
        );
        pools[3] = SonicLib._makePoolData(
            SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETASCUSD,
            AmmAdapterIdLib.UNISWAPV3,
            SonicConstantsLib.RECOVERY_TOKEN_CREDIX_WMETASCUSD,
            SonicConstantsLib.WRAPPED_METAVAULT_METAUSD
        );
        pools[4] = SonicLib._makePoolData(
            SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAUSD,
            AmmAdapterIdLib.UNISWAPV3,
            SonicConstantsLib.RECOVERY_TOKEN_CREDIX_WMETAUSD,
            SonicConstantsLib.WRAPPED_METAVAULT_METAUSD
        );
        pools[5] = SonicLib._makePoolData(
            SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAUSDC,
            AmmAdapterIdLib.UNISWAPV3,
            SonicConstantsLib.RECOVERY_TOKEN_CREDIX_WMETAUSDC,
            SonicConstantsLib.WRAPPED_METAVAULT_METAUSD
        );

        vm.prank(multisig);
        swapper.addPools(pools, false);
    }

    function getState(IUniswapV3Pool pool, address user, Recovery recovery) internal view returns (SingleState memory dest){
        address token0 = pool.token0();
        address token1 = pool.token1();

        (dest.sqrtPriceX96, dest.tick, , , , , ) = pool.slot0();
        dest.liquidity = pool.liquidity();
        dest.balanceRecoveryTokenUser = IERC20(token0).balanceOf(user);
        dest.balanceMetaVaultTokenUser = IERC20(token1).balanceOf(user);
        dest.balanceMetaVaultTokenInRecovery = IERC20(token1).balanceOf(address(recovery));
        dest.balanceRecoveryTokenInRecovery = IERC20(token0).balanceOf(address(recovery));

        console.log("Pool", address(pool));
        console.log("  tick", dest.tick);
        console.log("  sqrtPriceX96", dest.sqrtPriceX96);
        console.log("  liquidity", dest.liquidity);
        console.log("user balance recovery token", dest.balanceRecoveryTokenUser);
        console.log("user balance meta vault token", dest.balanceMetaVaultTokenUser);
        console.log("recovery balance meta vault token", dest.balanceMetaVaultTokenInRecovery);
        console.log("recovery balance recovery token", dest.balanceRecoveryTokenInRecovery);

        return dest;
    }
    //endregion --------------------------------- Utils
}
