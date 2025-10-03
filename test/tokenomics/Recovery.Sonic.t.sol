// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import {console} from "forge-std/console.sol";
import {SonicLib} from "../../chains/sonic/SonicLib.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IUniswapV3Pool} from "../../src/integrations/uniswapv3/IUniswapV3Pool.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {RecoveryLib} from "../../src/tokenomics/libs/RecoveryLib.sol";
import {Recovery} from "../../src/tokenomics/Recovery.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {console, Test} from "forge-std/Test.sol";

contract RecoverySonicTest is Test {
    uint public constant FORK_BLOCK = 47854805; // Sep-23-2025 04:02:39 AM +UTC
    address internal multisig;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();
    }

    //region --------------------------------- Data types
    struct SingleTestCase {
        address pool;
        address asset;
        uint amountRecoveryTokenToSwap;
        uint amountAssetToPutOnRecovery;
    }

    struct SingleState {
        int24 tick;
        uint sqrtPriceX96;
        uint128 liquidity;
        uint balanceUserRecoveryToken;
        uint balanceUserMetaVault;
        uint balanceMetaVaultTokenInRecovery;
        uint balanceRecoveryTokenInRecovery;
        uint totalSupplyRecoveryToken;
        uint balancePoolRecoveryToken;
        uint balancePoolMetaVault;
        uint balanceRecoveryUsdc;
        uint balanceRecoveryWs;
    }

    struct MultipleTestCase {
        address targetPool;
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

    struct SelectedPoolTestCase {
        uint index;
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

    function testAddRemoveRecoveryPools() public {
        Recovery recovery = createRecoveryInstance();

        // ------------------------- Add pools
        address[] memory pools = new address[](2);
        pools[0] = SonicConstantsLib.RECOVERY_POOL_CREDIX_METAUSD;
        pools[1] = SonicConstantsLib.RECOVERY_POOL_CREDIX_METAS;

        vm.expectRevert(IControllable.NotMultisig.selector);
        vm.prank(address(this));
        recovery.addRecoveryPools(pools);

        vm.prank(multisig);
        recovery.addRecoveryPools(pools);

        assertEq(recovery.recoveryPools().length, 2, "pools count 2");
        assertEq(recovery.recoveryPools()[0], SonicConstantsLib.RECOVERY_POOL_CREDIX_METAUSD, "pool address 0");
        assertEq(recovery.recoveryPools()[1], SonicConstantsLib.RECOVERY_POOL_CREDIX_METAS, "pool address 1");

        {
            address[] memory pools2 = new address[](2);
            pools2[0] = SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETASCUSD;
            pools2[1] = SonicConstantsLib.RECOVERY_POOL_CREDIX_METAS; // already exists

            vm.expectRevert(RecoveryLib.AlreadyExists.selector);
            vm.prank(multisig);
            recovery.addRecoveryPools(pools2);
        }

        // ------------------------- Remove pools
        vm.expectRevert(IControllable.NotMultisig.selector);
        vm.prank(address(this));
        recovery.removeRecoveryPool(SonicConstantsLib.RECOVERY_POOL_CREDIX_METAUSD);

        vm.expectRevert(RecoveryLib.NotFound.selector);
        vm.prank(multisig);
        recovery.removeRecoveryPool(SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAUSDC);

        vm.prank(multisig);
        recovery.removeRecoveryPool(SonicConstantsLib.RECOVERY_POOL_CREDIX_METAUSD);

        assertEq(recovery.recoveryPools().length, 1, "pools count 1");
        assertEq(recovery.recoveryPools()[0], SonicConstantsLib.RECOVERY_POOL_CREDIX_METAS, "pool address 2");
    }

    function testSetThreshold() public {
        Recovery recovery = createRecoveryInstance();

        address[] memory assets = new address[](2);
        assets[0] = SonicConstantsLib.TOKEN_USDC;
        assets[1] = SonicConstantsLib.TOKEN_WS;

        uint[] memory thresholds = new uint[](2);
        thresholds[0] = 1e6; // usdc
        thresholds[1] = 1e18; // ws

        assertEq(recovery.threshold(assets[0]), 0, "usdc threshold is zero by default");
        assertEq(recovery.threshold(assets[1]), 0, "ws threshold is zero by default");

        vm.expectRevert(IControllable.NotMultisig.selector);
        vm.prank(address(this));
        recovery.setThresholds(assets, thresholds);

        vm.prank(multisig);
        recovery.setThresholds(assets, thresholds);

        assertEq(recovery.threshold(assets[0]), thresholds[0], "usdc threshold 1");
        assertEq(recovery.threshold(assets[1]), thresholds[1], "ws threshold 1");

        thresholds[0] = 2e6; // usdc
        thresholds[1] = 0; // ws

        vm.prank(multisig);
        recovery.setThresholds(assets, thresholds);

        assertEq(recovery.threshold(assets[0]), thresholds[0], "usdc threshold 2");
        assertEq(recovery.threshold(assets[1]), thresholds[1], "ws threshold 2");
    }

    function testChangeWhitelist() public {
        Recovery recovery = createRecoveryInstance();

        address operator1 = makeAddr("operator1");
        address operator2 = makeAddr("operator2");

        assertEq(recovery.whitelisted(multisig), true, "multisig is whitelisted by default");
        assertEq(recovery.whitelisted(operator1), false, "operator1 is not whitelisted by default");
        assertEq(recovery.whitelisted(operator2), false, "operator2 is not whitelisted by default");

        vm.expectRevert(IControllable.NotMultisig.selector);
        vm.prank(address(this));
        recovery.changeWhitelist(operator1, true);

        vm.prank(multisig);
        recovery.changeWhitelist(operator1, true);

        assertEq(recovery.whitelisted(operator1), true, "operator1 is whitelisted");
        assertEq(recovery.whitelisted(operator2), false, "operator2 is not whitelisted");

        vm.prank(multisig);
        recovery.changeWhitelist(operator2, true);

        assertEq(recovery.whitelisted(operator2), true, "operator2 is whitelisted");

        vm.prank(multisig);
        recovery.changeWhitelist(operator1, false);

        assertEq(recovery.whitelisted(operator1), false, "operator1 is not whitelisted");
        assertEq(recovery.whitelisted(operator2), true, "operator2 is whitelisted");
    }

    function testRegisterAssetsBadPaths() public {
        Recovery recovery = createRecoveryInstance();

        address[] memory tokens = new address[](2);
        tokens[0] = SonicConstantsLib.TOKEN_USDC;
        tokens[1] = SonicConstantsLib.TOKEN_WS;

        assertEq(recovery.isTokenRegistered(tokens[0]), false, "usdc not registered");
        assertEq(recovery.isTokenRegistered(tokens[1]), false, "ws not registered");

        vm.expectRevert(RecoveryLib.NotWhitelisted.selector);
        vm.prank(address(this));
        recovery.registerAssets(tokens);

        vm.prank(multisig);
        recovery.registerAssets(tokens);

        assertEq(recovery.isTokenRegistered(tokens[0]), true, "usdc is registered");
        assertEq(recovery.isTokenRegistered(tokens[1]), true, "ws is registered");

        tokens[0] = SonicConstantsLib.TOKEN_USDT;
        tokens[1] = SonicConstantsLib.TOKEN_USDC;

        vm.prank(multisig);
        recovery.changeWhitelist(address(this), true);

        vm.prank(address(this));
        recovery.registerAssets(tokens);

        assertEq(recovery.isTokenRegistered(tokens[0]), true, "usdt is registered");
        assertEq(recovery.isTokenRegistered(tokens[1]), true, "usdc is registered");
    }

    function testGetListTokensToSwap() public {
        Recovery recovery = createRecoveryInstance();

        address[] memory tokens = new address[](3);
        tokens[0] = SonicConstantsLib.TOKEN_USDC;
        tokens[1] = SonicConstantsLib.TOKEN_WS;
        tokens[2] = SonicConstantsLib.TOKEN_USDT;

        vm.prank(multisig);
        recovery.registerAssets(tokens);

        address[] memory list = recovery.getListTokensToSwap();
        assertEq(list.length, 0, "no tokens to swap");

        // ------------------------- Put some assets on balance of Recovery
        deal(SonicConstantsLib.TOKEN_USDC, address(recovery), 1e6);
        deal(SonicConstantsLib.TOKEN_USDT, address(recovery), 2e6);

        list = recovery.getListTokensToSwap();
        assertEq(list.length, 2, "2 tokens to swap A");
        assertEq(list[0], SonicConstantsLib.TOKEN_USDC, "token 0 is usdc A");
        assertEq(list[1], SonicConstantsLib.TOKEN_USDT, "token 1 is usdt A");

        // ------------------------- Set high threshold for USDC
        address[] memory assets = new address[](1);
        assets[0] = SonicConstantsLib.TOKEN_USDC;

        uint[] memory thresholds = new uint[](1);
        thresholds[0] = 1e6; // usdc

        vm.prank(multisig);
        recovery.setThresholds(assets, thresholds);

        list = recovery.getListTokensToSwap();
        assertEq(list.length, 1, "1 token to swap B");
        assertEq(list[0], SonicConstantsLib.TOKEN_USDT, "token 0 is usdt B");

        // ------------------------- Add meta vaults on balance
        _getMetaUsdOnBalance(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, address(recovery), 100e18, true);
        _getMetaUsdOnBalance(SonicConstantsLib.WRAPPED_METAVAULT_METAS, address(recovery), 100e18, true);

        tokens = new address[](2);
        tokens[0] = SonicConstantsLib.WRAPPED_METAVAULT_METAUSD;
        tokens[1] = SonicConstantsLib.WRAPPED_METAVAULT_METAS;

        vm.prank(multisig);
        recovery.registerAssets(tokens);

        address[] memory pools = new address[](2);
        pools[0] = SonicConstantsLib.RECOVERY_POOL_CREDIX_METAUSD;
        pools[1] = SonicConstantsLib.RECOVERY_POOL_CREDIX_METAS;

        vm.prank(multisig);
        recovery.addRecoveryPools(pools);

        // ------------------------- Ensure that getListTokensToSwap doesn't return meta vaults
        list = recovery.getListTokensToSwap();
        assertEq(list.length, 1, "1 token to swap B");
        assertEq(list[0], SonicConstantsLib.TOKEN_USDT, "token 0 is usdt B");
    }

    function testSwapAssetsBadPaths() public {
        address[] memory tokens = new address[](1);
        tokens[0] = SonicConstantsLib.TOKEN_USDC;

        Recovery recovery = createRecoveryInstance();

        vm.expectRevert(RecoveryLib.NotWhitelisted.selector);
        vm.prank(address(this));
        recovery.swapAssets(tokens, 0);

        vm.prank(multisig);
        recovery.swapAssets(tokens, 0); // no recovery pool here

        vm.prank(multisig);
        recovery.changeWhitelist(address(this), true);

        vm.prank(address(this));
        recovery.swapAssets(tokens, 0);

        {
            address[] memory pools = new address[](1);
            pools[0] = SonicConstantsLib.RECOVERY_POOL_CREDIX_METAS;

            vm.prank(multisig);
            recovery.addRecoveryPools(pools);
        }

        vm.expectRevert(RecoveryLib.WrongRecoveryPoolIndex.selector);
        vm.prank(address(this));
        recovery.swapAssets(tokens, 20000);

        // try to emulate swap failing (there is no path to swap recovery token)
        {
            vm.prank(multisig);
            recovery.changeWhitelist(address(this), true);

            vm.prank(multisig);
            IMetaVault(SonicConstantsLib.METAVAULT_METAUSD).changeWhitelist(address(recovery), true);

            vm.prank(multisig);
            IMetaVault(SonicConstantsLib.METAVAULT_METAS).changeWhitelist(address(recovery), true);

            deal(SonicConstantsLib.RECOVERY_TOKEN_CREDIX_METAS, address(recovery), 1e18);

            address[] memory unknownTokens = new address[](1);
            unknownTokens[0] = SonicConstantsLib.RECOVERY_TOKEN_CREDIX_METAS;

            vm.prank(multisig);
            recovery.registerAssets(unknownTokens);

            vm.prank(multisig);
            recovery.swapAssets(unknownTokens, 1); // no revert, but no swaps too
        }
    }

    function testFillRecoveryPoolsBadPaths() public {
        address[] memory tokens = new address[](1);
        tokens[0] = SonicConstantsLib.TOKEN_USDC;

        Recovery recovery = createRecoveryInstance();

        vm.expectRevert(RecoveryLib.NotWhitelisted.selector);
        vm.prank(address(this));
        recovery.fillRecoveryPools(SonicConstantsLib.METAVAULT_METAUSD, 0, 0);

        vm.prank(multisig);
        recovery.fillRecoveryPools(SonicConstantsLib.METAVAULT_METAUSD, 0, 0); // no recovery pool here

        vm.prank(multisig);
        recovery.changeWhitelist(address(this), true);

        vm.prank(address(this));
        recovery.fillRecoveryPools(SonicConstantsLib.METAVAULT_METAUSD, 0, 0);

        {
            address[] memory pools = new address[](1);
            pools[0] = SonicConstantsLib.RECOVERY_POOL_CREDIX_METAS;

            vm.prank(multisig);
            recovery.addRecoveryPools(pools);
        }

        vm.prank(address(this)); // empty balance, no revert
        recovery.fillRecoveryPools(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, 20000, 1000);

        _getMetaUsdOnBalance(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, address(recovery), 1e18, true);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSD).changeWhitelist(address(recovery), true);

        vm.expectRevert(RecoveryLib.WrongRecoveryPoolIndex.selector);
        vm.prank(address(this));
        recovery.fillRecoveryPools(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, 20000, 1000);
    }

    function testSelectPool() public view {
        address[] memory recoveryPools = new address[](6);
        recoveryPools[0] = SonicConstantsLib.RECOVERY_POOL_CREDIX_METAUSD;
        recoveryPools[1] = SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAUSD;
        recoveryPools[2] = SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAS;
        recoveryPools[3] = SonicConstantsLib.RECOVERY_POOL_CREDIX_METAS;
        recoveryPools[4] = SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETASCUSD;
        recoveryPools[5] = SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAUSDC;

        uint[] memory selected = new uint[](6);

        for (uint i; i < 255; ++i) {
            uint index0 = RecoveryLib.selectPool(i, recoveryPools);
            selected[index0]++;
        }

        // at the initial block all pools have same price 1, so distribution should be smooth
        // typical values:
        //        0 35
        //        1 41
        //        2 46
        //        3 46
        //        4 44
        //        5 43
        for (uint i; i < 6; ++i) {
            // console.log(i, selected[i]);
            assertApproxEqAbs(selected[i], selected[0], selected[i] / 4, "smooth distribution");
        }

        for (uint i; i < 6; ++i) {
            assertEq(selected[i] != 0, true, string(abi.encodePacked("pool ", vm.toString(i), " was never selected")));
        }
    }
    //endregion --------------------------------- Unit tests

    //region --------------------------------- Use Recovery with EACH single recovery token
    function fixtureSingle() public pure returns (SingleTestCase[] memory) {
        SingleTestCase[] memory cases = new SingleTestCase[](6);
        cases[0] = SingleTestCase({
            pool: SonicConstantsLib.RECOVERY_POOL_CREDIX_METAUSD,
            asset: SonicConstantsLib.WRAPPED_METAVAULT_METAUSD,
            amountRecoveryTokenToSwap: 20e18,
            amountAssetToPutOnRecovery: 100e18
        });
        cases[1] = SingleTestCase({
            pool: SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAUSD,
            asset: SonicConstantsLib.TOKEN_USDC,
            amountRecoveryTokenToSwap: 20e18,
            amountAssetToPutOnRecovery: 1000e6
        });
        cases[2] = SingleTestCase({
            pool: SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAS,
            asset: SonicConstantsLib.WRAPPED_METAVAULT_METAS,
            amountRecoveryTokenToSwap: 20e18,
            amountAssetToPutOnRecovery: 100e18
        });
        cases[3] = SingleTestCase({
            pool: SonicConstantsLib.RECOVERY_POOL_CREDIX_METAS,
            asset: SonicConstantsLib.TOKEN_WS,
            amountRecoveryTokenToSwap: 20e18,
            amountAssetToPutOnRecovery: 100e18
        });
        cases[4] = SingleTestCase({
            pool: SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETASCUSD,
            asset: SonicConstantsLib.TOKEN_USDC,
            amountRecoveryTokenToSwap: 20e6,
            amountAssetToPutOnRecovery: 100e6
        });
        cases[5] = SingleTestCase({
            pool: SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAUSDC,
            asset: SonicConstantsLib.TOKEN_USDC,
            amountRecoveryTokenToSwap: 20e6,
            amountAssetToPutOnRecovery: 100e6
        });

        return cases;
    }

    function tableSingleTest(SingleTestCase memory single) public {
        SingleState[4] memory states = _testSinglePoolThreeSwaps(single);

        assertLt(states[1].sqrtPriceX96, states[0].sqrtPriceX96, "price should go down");
        assertEq(
            states[0].balanceUserRecoveryToken - states[1].balanceUserRecoveryToken,
            states[1].balancePoolRecoveryToken - states[0].balancePoolRecoveryToken,
            "user should spent recovery tokens"
        );
        assertEq(
            states[1].balanceUserMetaVault - states[0].balanceUserMetaVault,
            states[0].balancePoolMetaVault - states[1].balancePoolMetaVault,
            "user should receive expected amount of meta vault tokens"
        );
        if (single.asset == SonicConstantsLib.TOKEN_USDC) {
            assertNotEq(states[1].balanceRecoveryUsdc, 0, "We put some USDC on Recovery");
        }
        if (single.asset == SonicConstantsLib.TOKEN_WS) {
            assertNotEq(states[1].balanceRecoveryWs, 0, "We put some WS on Recovery");
        }

        assertEq(states[2].sqrtPriceX96, states[0].sqrtPriceX96, "price should return to initial 1");
        if (single.asset == SonicConstantsLib.TOKEN_USDC) {
            assertEq(states[2].balanceRecoveryUsdc, 0, "USDC were swapped");
        }
        if (single.asset == SonicConstantsLib.TOKEN_WS) {
            assertEq(states[2].balanceRecoveryWs, 0, "WS were swapped");
        }

        assertEq(
            states[3].sqrtPriceX96, states[1].sqrtPriceX96, "price should change to the same value as after first swap"
        );
        assertEq(states[3].balanceUserRecoveryToken, 0, "user should spent all recovery tokens");
        assertEq(
            states[3].balanceUserMetaVault,
            2 * states[1].balanceUserMetaVault,
            "user should receive same amount of meta vault tokens as in first swap"
        );

        address recoveryToken = IUniswapV3Pool(single.pool).token0();
        uint balanceUserRecoveryToken18 =
            states[0].balanceUserRecoveryToken * 1e18 / (10 ** (IERC20Metadata(recoveryToken).decimals()));

        assertApproxEqAbs(
            states[3].balanceUserMetaVault,
            balanceUserRecoveryToken18,
            balanceUserRecoveryToken18 * 12 / 100,
            "user should exchange tokens near to 1:1 (delta 12% max)"
        );

        assertEq(
            states[0].totalSupplyRecoveryToken,
            states[3].totalSupplyRecoveryToken
                + (states[0].balanceUserRecoveryToken - states[3].balanceUserRecoveryToken)
                - (states[3].balancePoolRecoveryToken - states[0].balancePoolRecoveryToken),
            "all recovery tokens that were spent by user were burnt"
        );
    }

    //endregion --------------------------------- Use Recovery with EACH single recovery token

    //region --------------------------------- Use Recovery with multiple recovery tokens
    function fixtureMultiple() public pure returns (MultipleTestCase[] memory) {
        MultipleTestCase[] memory cases = new MultipleTestCase[](3);

        address[] memory recoveryPools = new address[](6);
        recoveryPools[0] = SonicConstantsLib.RECOVERY_POOL_CREDIX_METAUSD;
        recoveryPools[1] = SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAUSD;
        recoveryPools[2] = SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAS;
        recoveryPools[3] = SonicConstantsLib.RECOVERY_POOL_CREDIX_METAS;
        recoveryPools[4] = SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETASCUSD;
        recoveryPools[5] = SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAUSDC;

        uint[] memory amounts = new uint[](6);
        amounts[0] = 10e18;
        amounts[1] = 20e18;
        amounts[2] = 30e18;
        amounts[3] = 40e18;
        amounts[4] = 12e6;
        amounts[5] = 14e6;

        address[] memory inputAssets0 = new address[](3);
        inputAssets0[0] = SonicConstantsLib.WRAPPED_METAVAULT_METAUSD;
        inputAssets0[1] = SonicConstantsLib.TOKEN_USDC;
        inputAssets0[2] = SonicConstantsLib.WRAPPED_METAVAULT_METAS;

        uint[] memory inputAmounts0 = new uint[](3);
        inputAmounts0[0] = 1000e18;
        inputAmounts0[1] = 2000e6;
        inputAmounts0[2] = 3000e18;

        // ------------------------- Target pool has meta-vault-token WMETA_USD
        cases[0] = MultipleTestCase({
            targetPool: SonicConstantsLib.RECOVERY_POOL_CREDIX_METAUSD,
            pools: recoveryPools,
            amounts: amounts,
            inputAssets: inputAssets0,
            inputAmounts: inputAmounts0
        });
        // ------------------------- Target pool has meta-vault-token WMETA_S
        cases[1] = MultipleTestCase({
            targetPool: SonicConstantsLib.RECOVERY_POOL_CREDIX_METAS,
            pools: recoveryPools,
            amounts: amounts,
            inputAssets: inputAssets0,
            inputAmounts: inputAmounts0
        });
        // ------------------------- Target pool is the last pool in the list
        cases[2] = MultipleTestCase({
            targetPool: SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAUSDC,
            pools: recoveryPools,
            amounts: amounts,
            inputAssets: inputAssets0,
            inputAmounts: inputAmounts0
        });
        return cases;
    }

    /// @notice We use test instead of table because coverage doesn't take into account all table-calls, only single one
    function testMultiple0() public {
        _testMultiple(fixtureMultiple()[0]);
    }

    function testMultiple1() public {
        _testMultiple(fixtureMultiple()[1]);
    }

    function testMultiple2() public {
        _testMultiple(fixtureMultiple()[2]);
    }

    function tableMultipleUnitPrice(MultipleTestCase memory multiple) public {
        Recovery recovery = createRecoveryInstance();

        uint160[] memory unitPrices = new uint160[](multiple.pools.length);
        for (uint i; i < multiple.pools.length; ++i) {
            address token0 = IUniswapV3Pool(multiple.pools[i]).token0();
            address token1 = IUniswapV3Pool(multiple.pools[i]).token1();
            unitPrices[i] = RecoveryLib._sqrtPriceLimitX96(token0, token1);
        }

        // Recovery gets some assets but it is not able to make any swaps in pools
        // All swapped amounts are kept on balance of Recovery
        SingleState[4][] memory states = _testMultiplePoolsTwoSwaps(recovery, multiple, false, false);

        // users don't make any swaps
        for (uint i; i < multiple.pools.length; ++i) {
            assertEq(states[i][0].sqrtPriceX96, unitPrices[i], "assume that initial price should be 1:1");
            assertEq(states[i][3].sqrtPriceX96, states[i][0].sqrtPriceX96, "price should not change");
        }

        // all assets were swapped and amount of meta-vault-tokens on balance of Recovery was increased
        for (uint i; i < multiple.inputAssets.length; ++i) {
            assertEq(states[i][3].balanceRecoveryUsdc, 0, "all USDC were swapped");
            assertEq(states[i][3].balanceRecoveryWs, 0, "all WS were swapped");
            assertGt(
                states[i][3].balanceMetaVaultTokenInRecovery,
                states[i][0].balanceMetaVaultTokenInRecovery,
                "amount of meta-vault-tokens in Recovery was increased"
            );
        }
    }

    function testMultipleHighInputAssetThresholds() public {
        Recovery recovery = createRecoveryInstance();
        MultipleTestCase memory multiple = fixtureMultiple()[0];

        {
            multiple.inputAssets = new address[](2);
            multiple.inputAssets[0] = SonicConstantsLib.TOKEN_USDC;
            multiple.inputAssets[1] = SonicConstantsLib.TOKEN_WS;

            multiple.inputAmounts = new uint[](2);
            multiple.inputAmounts[0] = 10e6;
            multiple.inputAmounts[1] = 10e18;

            uint[] memory thresholds = new uint[](2);
            thresholds[0] = 11e6; // (!) above input amount
            thresholds[1] = 11e18; // (!) above input amount

            vm.prank(multisig);
            recovery.setThresholds(multiple.inputAssets, thresholds);
        }

        // Recovery gets some assets but it is not able to make any swaps in pools
        // because all received amounts are below thresholds
        SingleState[4][] memory states = _testMultiplePoolsTwoSwaps(recovery, multiple, true, false);

        // Recovery doesn't get any recovery tokens
        for (uint i; i < multiple.pools.length; ++i) {
            assertEq(states[i][3].sqrtPriceX96, states[i][1].sqrtPriceX96, "price should not change");
            assertEq(
                states[i][3].totalSupplyRecoveryToken,
                states[i][1].totalSupplyRecoveryToken,
                "no recovery tokens were burnt"
            );
        }

        assertEq(states[0][3].balanceRecoveryUsdc, multiple.inputAmounts[0], "no USDC were swapped");
        assertEq(states[0][3].balanceRecoveryWs, multiple.inputAmounts[1], "no Ws were swapped");
        assertEq(
            states[0][3].balanceMetaVaultTokenInRecovery,
            states[0][0].balanceMetaVaultTokenInRecovery,
            "amount of meta-vault-tokens in Recovery was not changed"
        );
    }

    function testMultipleHighMetaVaultThresholds() public {
        Recovery recovery = createRecoveryInstance();
        MultipleTestCase memory multiple = fixtureMultiple()[0];

        {
            multiple.inputAssets = new address[](4);
            multiple.inputAssets[0] = SonicConstantsLib.TOKEN_USDC;
            multiple.inputAssets[1] = SonicConstantsLib.TOKEN_WS;
            multiple.inputAssets[2] = SonicConstantsLib.WRAPPED_METAVAULT_METAUSD;
            multiple.inputAssets[3] = SonicConstantsLib.WRAPPED_METAVAULT_METAS;

            multiple.inputAmounts = new uint[](4);
            multiple.inputAmounts[0] = 10e6;
            multiple.inputAmounts[1] = 10e18;
            multiple.inputAmounts[2] = 1e18;
            multiple.inputAmounts[3] = 1e18;

            uint[] memory thresholds = new uint[](4);
            thresholds[0] = 1e6; // (!) below input amount
            thresholds[1] = 118; // (!) below input amount
            thresholds[2] = 1000000e18; // (!) above input amount + swap results
            thresholds[3] = 1000000e18; // (!) above input amount + swap results

            vm.prank(multisig);
            recovery.setThresholds(multiple.inputAssets, thresholds);
        }

        // Recovery gets some assets but it is not able to make any swaps in pools
        // because all received amounts are below thresholds
        SingleState[4][] memory states = _testMultiplePoolsTwoSwaps(recovery, multiple, true, false);

        // Recovery doesn't get any recovery tokens
        for (uint i; i < multiple.pools.length; ++i) {
            assertEq(states[i][3].sqrtPriceX96, states[i][1].sqrtPriceX96, "price should not change");
            assertEq(
                states[i][3].totalSupplyRecoveryToken,
                states[i][1].totalSupplyRecoveryToken,
                "no recovery tokens were burnt"
            );
        }

        assertEq(states[0][3].balanceRecoveryUsdc, 0, "all USDC were swapped");
        assertEq(states[0][3].balanceRecoveryWs, 0, "all Ws were swapped");
        assertGt(
            states[0][3].balanceMetaVaultTokenInRecovery,
            states[0][0].balanceMetaVaultTokenInRecovery,
            "balance of meta-vault-token in Recovery should be increased"
        );
    }
    //endregion --------------------------------- Use Recovery with multiple recovery tokens

    //region --------------------------------- Selected pool tests
    function fixtureSelectedPoolCase() public pure returns (SelectedPoolTestCase[] memory) {
        SelectedPoolTestCase[] memory cases = new SelectedPoolTestCase[](6);
        for (uint i; i < cases.length; ++i) {
            cases[i] = SelectedPoolTestCase({index: i});
        }
        return cases;
    }

    function tableSelectedPool(SelectedPoolTestCase memory selectedPoolCase) public {
        Recovery recovery = createRecoveryInstance();
        MultipleTestCase memory multiple = fixtureMultiple()[0];
        multiple.targetPool = multiple.pools[selectedPoolCase.index];

        address user1 = makeAddr("user1");

        ISwapper swapper = ISwapper(IPlatform(SonicConstantsLib.PLATFORM).swapper());
        _addRoutesForRecoveryTokens();

        for (uint i; i < multiple.pools.length; ++i) {
            // assume here that recovery tokens are always set as token 0
            address recoveryToken = IUniswapV3Pool(multiple.pools[i]).token0();

            // ------------------------- Prepare user balances
            deal(recoveryToken, user1, multiple.amounts[i] * 2);

            vm.prank(user1);
            IERC20(recoveryToken).approve(address(swapper), type(uint).max);
        }

        // ------------------------- Setup Recovery
        _whiteListRecovery(recovery);

        vm.prank(multisig);
        recovery.addRecoveryPools(multiple.pools);

        // ------------------------- User makes first swap
        for (uint i; i < multiple.pools.length; ++i) {
            address recoveryToken = IUniswapV3Pool(multiple.pools[i]).token0();
            address metaVaultToken = IUniswapV3Pool(multiple.pools[i]).token1();

            // price in the selected pool will be reduced more than in other pools
            uint amountToSwap = i == selectedPoolCase.index ? multiple.amounts[i] : multiple.amounts[i] / 100;

            vm.prank(user1);
            swapper.swap(recoveryToken, metaVaultToken, amountToSwap, 100_000);
        }

        // -------------------------- Grab statistics
        uint[] memory count = new uint[](multiple.pools.length);
        for (uint i; i < 255; ++i) {
            uint index = RecoveryLib.selectPool(i, multiple.pools);
            count[index]++;
        }

        uint indexMax;
        SingleState[] memory states = new SingleState[](multiple.pools.length);
        for (uint i; i < multiple.pools.length; ++i) {
            states[i] = getState(IUniswapV3Pool(multiple.pools[i]), user1, recovery);
            if (count[i] > count[indexMax]) {
                indexMax = i;
            }
        }

        //        for (uint i; i < multiple.pools.length; ++i) {
        //            console.log(i, count[i], states[i].sqrtPriceX96, RecoveryLib.getNormalizedSqrtPrice(multiple.pools[i]));
        //        }

        assertEq(indexMax, selectedPoolCase.index, "most selected pool is the target pool");
    }
    //endregion --------------------------------- Selected pool tests

    //region --------------------------------- Tests implementations

    function _testMultiple(MultipleTestCase memory multiple) internal {
        Recovery recovery = createRecoveryInstance();
        SingleState[4][] memory states = _testMultiplePoolsTwoSwaps(recovery, multiple, true, false);

        address targetMetaVaultToken = IUniswapV3Pool(multiple.targetPool).token1();
        for (uint i; i < multiple.pools.length; ++i) {
            // console.log(i, states[i][0].sqrtPriceX96, states[i][1].sqrtPriceX96, states[i][2].sqrtPriceX96);
            if (IUniswapV3Pool(multiple.pools[i]).token1() == targetMetaVaultToken) {
                assertLt(states[i][1].sqrtPriceX96, states[i][0].sqrtPriceX96, "price should go down");
                assertEq(
                    states[i][2].sqrtPriceX96,
                    states[i][0].sqrtPriceX96,
                    "price should be restored to initial value (pool was used to swap assets to recovery tokens)"
                );
            } else {
                assertLt(states[i][1].sqrtPriceX96, states[i][0].sqrtPriceX96, "price should go down");
                assertEq(
                    states[i][2].sqrtPriceX96,
                    states[i][1].sqrtPriceX96,
                    "price is not change (pool was not used to swap assets to recovery tokens)"
                );
            }
        }
    }

    /// @notice Make following actions:
    /// 1. User swaps half of his recovery tokens
    /// 2. Add some meta vault tokens to Recovery and swap them to recovery tokens
    /// 3. User swaps second half of his recovery tokens
    function _testSinglePoolThreeSwaps(SingleTestCase memory single) internal returns (SingleState[4] memory states) {
        ISwapper swapper = ISwapper(IPlatform(SonicConstantsLib.PLATFORM).swapper());
        _addRoutesForRecoveryTokens();

        // assume here that recovery tokens are always set as token 0
        address recoveryToken = IUniswapV3Pool(single.pool).token0();
        // assume here that meta-vault tokens are always set as token 1
        address metaVaultToken = IUniswapV3Pool(single.pool).token1();

        // ------------------------- Prepare user balances
        address user1 = makeAddr("user1");
        deal(recoveryToken, user1, single.amountRecoveryTokenToSwap);

        vm.prank(user1);
        IERC20(recoveryToken).approve(address(swapper), type(uint).max);

        // ------------------------- Setup Recovery with single recovery pool
        Recovery recovery = createRecoveryInstance();
        {
            address[] memory pools = new address[](1);
            pools[0] = single.pool;

            vm.prank(multisig);
            recovery.addRecoveryPools(pools);
        }
        _whiteListRecovery(recovery);

        // ------------------------- User makes first swap
        states[0] = getState(IUniswapV3Pool(single.pool), user1, recovery);

        vm.prank(user1);
        swapper.swap(recoveryToken, metaVaultToken, single.amountRecoveryTokenToSwap / 2, 100_000);
        vm.roll(block.number + 6);

        // ------------------------- Put some tokens on Recovery balance and register them
        address[] memory tokens = new address[](1);
        tokens[0] = single.asset;

        deal(single.asset, address(recovery), single.amountAssetToPutOnRecovery);

        vm.prank(multisig);
        recovery.registerAssets(tokens);
        vm.roll(block.number + 6);

        states[1] = getState(IUniswapV3Pool(single.pool), user1, recovery);

        // ------------------------- Swap assets to recovery tokens
        address[] memory tokensToSwap = recovery.getListTokensToSwap();

        vm.prank(multisig);
        recovery.swapAssets(tokensToSwap, 0);
        vm.roll(block.number + 6);

        vm.prank(multisig);
        recovery.fillRecoveryPools(metaVaultToken, 1, 1);
        vm.roll(block.number + 6);

        states[2] = getState(IUniswapV3Pool(single.pool), user1, recovery);

        // ------------------------- User makes second swap
        vm.prank(user1);
        swapper.swap(recoveryToken, metaVaultToken, single.amountRecoveryTokenToSwap / 2, 100_000);
        vm.roll(block.number + 6);

        states[3] = getState(IUniswapV3Pool(single.pool), user1, recovery);

        return states;
    }

    /// @notice Full up all pools that have same token1 as the target pool
    /// Make following actions:
    /// 1. User swaps all his recovery tokens in each pool and reduce the price in the pools
    /// 2. Add some meta vault tokens to Recovery, swap them to recovery tokens and restore price to 1
    /// Only pools with token1 same as in targetPool are used to swap assets to recovery tokens
    function _testMultiplePoolsTwoSwaps(
        Recovery recovery,
        MultipleTestCase memory multiple,
        bool makeFirstSwap,
        bool makeSecondSwap
    ) internal returns (SingleState[4][] memory states) {
        states = new SingleState[4][](multiple.pools.length);

        address user1 = makeAddr("user1");

        ISwapper swapper = ISwapper(IPlatform(SonicConstantsLib.PLATFORM).swapper());
        _addRoutesForRecoveryTokens();

        for (uint i; i < multiple.pools.length; ++i) {
            // assume here that recovery tokens are always set as token 0
            address recoveryToken = IUniswapV3Pool(multiple.pools[i]).token0();

            // ------------------------- Prepare user balances
            deal(recoveryToken, user1, multiple.amounts[i] * 2);

            vm.prank(user1);
            IERC20(recoveryToken).approve(address(swapper), type(uint).max);
        }

        // ------------------------- Setup Recovery
        _whiteListRecovery(recovery);

        vm.prank(multisig);
        recovery.addRecoveryPools(multiple.pools);

        // ------------------------- User makes first swap
        // get initial state
        for (uint i; i < multiple.pools.length; ++i) {
            states[i][0] = getState(IUniswapV3Pool(multiple.pools[i]), user1, recovery);
        }
        if (makeFirstSwap) {
            for (uint i; i < multiple.pools.length; ++i) {
                address recoveryToken = IUniswapV3Pool(multiple.pools[i]).token0();
                address metaVaultToken = IUniswapV3Pool(multiple.pools[i]).token1();

                vm.prank(user1);
                swapper.swap(recoveryToken, metaVaultToken, multiple.amounts[i] / 2, 100_000);
            }
        }

        // ------------------------- Put some tokens on Recovery balance and register them
        for (uint i; i < multiple.inputAssets.length; ++i) {
            deal(multiple.inputAssets[i], address(recovery), multiple.inputAmounts[i]);
        }

        vm.prank(multisig);
        recovery.registerAssets(multiple.inputAssets);

        // get state after user swaps and putting asset on Recovery balance
        for (uint i; i < multiple.pools.length; ++i) {
            states[i][1] = getState(IUniswapV3Pool(multiple.pools[i]), user1, recovery);
        }

        // ------------------------- Swap assets for recovery tokens
        {
            uint index0;
            for (uint i; i < multiple.pools.length; ++i) {
                if (multiple.pools[i] == multiple.targetPool) {
                    index0 = i;
                    break;
                }
            }

            address[] memory tokens = recovery.getListTokensToSwap();

            address metaVaultToken = IUniswapV3Pool(multiple.targetPool).token1();

            vm.prank(multisig);
            recovery.swapAssets(tokens, index0 + 1);
            vm.roll(block.number + 6);

            vm.prank(multisig);
            recovery.fillRecoveryPools(metaVaultToken, index0 + 1, 0);
        }

        // get state after calling swapAssetsToRecoveryTokens
        for (uint i; i < multiple.pools.length; ++i) {
            states[i][2] = getState(IUniswapV3Pool(multiple.pools[i]), user1, recovery);
        }

        // ------------------------- User makes second swap
        if (makeSecondSwap) {
            for (uint i; i < multiple.pools.length; ++i) {
                address recoveryToken = IUniswapV3Pool(multiple.pools[i]).token0();
                address metaVaultToken = IUniswapV3Pool(multiple.pools[i]).token1();

                vm.prank(user1);
                swapper.swap(recoveryToken, metaVaultToken, multiple.amounts[i] / 2, 100_000);
            }
        }
        // final state
        for (uint i; i < multiple.pools.length; ++i) {
            states[i][3] = getState(IUniswapV3Pool(multiple.pools[i]), user1, recovery);
        }
    }
    //endregion --------------------------------- Tests implementations

    //region --------------------------------- Utils
    function _addRoutesForRecoveryTokens() internal {
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

    function _whiteListRecovery(Recovery recovery_) internal {
        vm.startPrank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSD).changeWhitelist(address(recovery_), true);
        IMetaVault(SonicConstantsLib.METAVAULT_METAS).changeWhitelist(address(recovery_), true);
        IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD).changeWhitelist(address(recovery_), true);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).changeWhitelist(address(recovery_), true);
        vm.stopPrank();
    }

    function getState(
        IUniswapV3Pool pool,
        address user,
        Recovery recovery
    ) internal view returns (SingleState memory dest) {
        address token0 = pool.token0();
        address token1 = pool.token1();

        (dest.sqrtPriceX96, dest.tick,,,,,) = pool.slot0();
        dest.liquidity = pool.liquidity();
        dest.balanceUserRecoveryToken = IERC20(token0).balanceOf(user);
        dest.balanceUserMetaVault = IERC20(token1).balanceOf(user);
        dest.balanceMetaVaultTokenInRecovery = IERC20(token1).balanceOf(address(recovery));
        dest.balanceRecoveryTokenInRecovery = IERC20(token0).balanceOf(address(recovery));
        dest.totalSupplyRecoveryToken = IERC20(token0).totalSupply();
        dest.balancePoolRecoveryToken = IERC20(token0).balanceOf(address(pool));
        dest.balancePoolMetaVault = IERC20(token1).balanceOf(address(pool));
        dest.balanceRecoveryUsdc = IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(address(recovery));
        dest.balanceRecoveryWs = IERC20(SonicConstantsLib.TOKEN_WS).balanceOf(address(recovery));
        //
        //        console.log("Pool", address(pool));
        //        console.log("  tick", dest.tick);
        //        console.log("  sqrtPriceX96", dest.sqrtPriceX96);
        //        console.log("  liquidity", dest.liquidity);
        //        console.log("  user.RecoveryToken", dest.balanceUserRecoveryToken);
        //        console.log("  user.MetaVault", dest.balanceUserMetaVault);
        //        console.log("  Recovery.RecoveryToken", dest.balanceRecoveryTokenInRecovery);
        //        console.log("  Recovery.MetaVault", dest.balanceMetaVaultTokenInRecovery);
        //        console.log("  Recovery.USDC", dest.balanceRecoveryUsdc);
        //        console.log("  Recovery.WS", dest.balanceRecoveryWs);
        //        console.log("  pool.RecoveryToken", dest.balancePoolRecoveryToken);
        //        console.log("  pool.MetaVault", dest.balancePoolMetaVault);
        //        console.log("  TotalSupply.RecoveryToken", dest.totalSupplyRecoveryToken);

        return dest;
    }

    function createRecoveryInstance() internal returns (Recovery) {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new Recovery()));
        Recovery recovery = Recovery(address(proxy));
        recovery.initialize(SonicConstantsLib.PLATFORM);

        _whiteListInPriceReader(address(recovery));

        return recovery;
    }

    function _getMetaUsdOnBalance(address wrapped, address user, uint amountMetaVaultTokens, bool wrap) internal {
        IWrappedMetaVault wrappedMetaVault = IWrappedMetaVault(wrapped);
        IMetaVault metaVault = IMetaVault(wrappedMetaVault.metaVault());

        // we don't know exact amount of USDC required to receive exact amountMetaVaultTokens
        // so we deposit a bit large amount of USDC
        address[] memory _assets = metaVault.assetsForDeposit();
        uint[] memory amountsMax = new uint[](1);
        address asset = _assets[0];
        amountsMax[0] = 2 * amountMetaVaultTokens * (10 ** IERC20Metadata(asset).decimals()) / 1e18;

        deal(asset, user, amountsMax[0]);

        vm.startPrank(user);
        IERC20(asset).approve(address(metaVault), IERC20(asset).balanceOf(user));
        metaVault.depositAssets(_assets, amountsMax, 0, user);
        vm.roll(block.number + 6);
        vm.stopPrank();

        if (wrap) {
            vm.startPrank(user);
            metaVault.approve(address(wrappedMetaVault), metaVault.balanceOf(user));
            wrappedMetaVault.deposit(metaVault.balanceOf(user), user, 0);
            vm.stopPrank();

            vm.roll(block.number + 6);
        }
    }

    function _whiteListInPriceReader(address recovery_) internal {
        IPriceReader priceReader = IPriceReader(IPlatform(SonicConstantsLib.PLATFORM).priceReader());

        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(recovery_, true);
    }
    //endregion --------------------------------- Utils
}
