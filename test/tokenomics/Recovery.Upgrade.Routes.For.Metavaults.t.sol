// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
// import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {Swapper} from "../../src/core/Swapper.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {BalancerV3StableAdapter} from "../../src/adapters/BalancerV3StableAdapter.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {IUniswapV3Pool} from "../../src/integrations/uniswapv3/IUniswapV3Pool.sol";
import {Recovery} from "../../src/tokenomics/Recovery.sol";

contract SwapperUpgradeRoutesForMetaVaultsSonicTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    constructor() {}

    // wanS: 0xfA85Fe5A8F5560e9039C04f2b0a90dE1415aBD70
    // wstkscUSD
    // wstkscETH

    function testUpgradeRoutesForWans() public {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 49150536)); // Oct-03-2025 12:00:30 AM UTC

        address multisig = IPlatform(PLATFORM).multisig();
        IRecovery recovery = IRecovery(IPlatform(PLATFORM).recovery());

        _upgradePlatform();
        _whiteListRecovery(multisig, recovery);

        uint poolIndexMetaUsd = _getPoolIndex(recovery, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);
        _testSwap(SonicConstantsLib.TOKEN_WANS, poolIndexMetaUsd, 100e18, recovery, multisig);

        uint poolIndexMetaS = _getPoolIndex(recovery, SonicConstantsLib.WRAPPED_METAVAULT_METAS);
        _testSwap(SonicConstantsLib.TOKEN_WANS, poolIndexMetaS, 100e18, recovery, multisig);
    }

    function testUpgradeRoutesForWstkscUSD() public {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 49150536)); // Oct-03-2025 12:00:30 AM UTC

        address multisig = IPlatform(PLATFORM).multisig();
        IRecovery recovery = IRecovery(IPlatform(PLATFORM).recovery());

        _upgradePlatform();
        _whiteListRecovery(multisig, recovery);

        uint poolIndexMetaUsd = _getPoolIndex(recovery, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);
        _testSwap(SonicConstantsLib.TOKEN_WSTKSCUSD, poolIndexMetaUsd, 50e6, recovery, multisig);

        uint poolIndexMetaS = _getPoolIndex(recovery, SonicConstantsLib.WRAPPED_METAVAULT_METAS);
        _testSwap(SonicConstantsLib.TOKEN_WSTKSCUSD, poolIndexMetaS, 50e6, recovery, multisig);
    }

    function testUpgradeRoutesForWstkscETH() public {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 49150536)); // Oct-03-2025 12:00:30 AM UTC

        address multisig = IPlatform(PLATFORM).multisig();
        IRecovery recovery = IRecovery(IPlatform(PLATFORM).recovery());

        _upgradePlatform();
        _whiteListRecovery(multisig, recovery);

        uint poolIndexMetaUsd = _getPoolIndex(recovery, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);
        _testSwap(SonicConstantsLib.TOKEN_WSTKSCETH, poolIndexMetaUsd, 1e18, recovery, multisig);

        // todo a path for the following swap cannot be created right now
        //        uint poolIndexMetaS = _getPoolIndex(recovery, SonicConstantsLib.WRAPPED_METAVAULT_METAS);
        //        _testSwap(SonicConstantsLib.TOKEN_WSTKSCETH, poolIndexMetaS, 1e18, recovery, multisig);
    }

    function _testSwap(address from_, uint poolIndex, uint amount_, IRecovery recovery, address multisig) internal {
        deal(from_, address(recovery), amount_);

        address[] memory tokens = new address[](1);
        tokens[0] = from_;

        address metaVaultToken = IUniswapV3Pool(recovery.recoveryPools()[poolIndex]).token1();

        uint balanceBefore = IERC20(metaVaultToken).balanceOf(address(recovery));
        uint balanceAssetBefore = IERC20(from_).balanceOf(address(recovery));
        IERC20(from_).approve(address(recovery), amount_);

        uint gasBefore = gasleft();
        vm.prank(multisig);
        recovery.swapAssets(tokens, poolIndex + 1);
        assertLt(gasBefore - gasleft(), 10e6, "gas used is ok");

        uint balanceAfter = IERC20(metaVaultToken).balanceOf(address(recovery));
        uint balanceAssetAfter = IERC20(from_).balanceOf(address(recovery));
        //        console.log("balanceBefore", balanceBefore);
        //        console.log("balanceAfter", balanceAfter);
        //        console.log("balanceAssetBefore", balanceAssetBefore);
        //        console.log("balanceAssetAfter", balanceAssetAfter);
        //        console.log("metaVaultToken", metaVaultToken);
        //        console.log("threshold for metavault", recovery.threshold(metaVaultToken));
        //        console.log("threshold for from_", recovery.threshold(from_));
        //
        assertGt(balanceAfter, balanceBefore, "get some meta vault tokens on recovery balance");
        assertGt(balanceAssetBefore, 0, "there is source asset");
        assertEq(balanceAssetAfter, 0, "spend all source asset");
    }

    //region ------------------------------------ Internal logic
    function _getPoolIndex(IRecovery recovery, address metaVaultToken) internal view returns (uint index) {
        address[] memory pools = recovery.recoveryPools();
        for (uint i; i < pools.length; i++) {
            if (IUniswapV3Pool(pools[i]).token1() == metaVaultToken) {
                return i;
            }
        }
        revert("pool not found");
    }

    //endregion ------------------------------------ Internal logic

    //region ------------------------------------ Helpers
    function _addAdapter() internal {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BalancerV3StableAdapter()));
        BalancerV3StableAdapter(address(proxy)).init(PLATFORM);
        BalancerV3StableAdapter(address(proxy)).setupHelpers(SonicConstantsLib.BEETS_V3_ROUTER);
        IPlatform(PLATFORM).addAmmAdapter(AmmAdapterIdLib.BALANCER_V3_STABLE, address(proxy));
    }

    function _upgrade(ISwapper swapper) internal {
        address newImplementation = address(new Swapper());
        address[] memory proxies = new address[](1);
        proxies[0] = address(swapper);
        address[] memory implementations = new address[](1);
        implementations[0] = newImplementation;
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.03.1-alpha", proxies, implementations);
        skip(1 days);
        IPlatform(PLATFORM).upgrade();
    }

    function _routes() internal pure returns (ISwapper.AddPoolData[] memory pools) {
        pools = new ISwapper.AddPoolData[](6);
        uint i;
        // wanS -> USDC
        pools[i++] = _makePoolData(
            SonicConstantsLib.SILO_VAULT_25_WS,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.SILO_VAULT_25_WS,
            SonicConstantsLib.TOKEN_WS
        );
        pools[i++] = _makePoolData(
            SonicConstantsLib.POOL_BEETS_V3_SILO_VAULT_25_WS_ANS,
            AmmAdapterIdLib.BALANCER_V3_STABLE,
            SonicConstantsLib.TOKEN_ANS,
            SonicConstantsLib.SILO_VAULT_25_WS
        );
        pools[i++] = _makePoolData(
            SonicConstantsLib.TOKEN_WANS,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.TOKEN_WANS,
            SonicConstantsLib.TOKEN_ANS
        );

        // wstkscUSD -> USDC
        pools[i++] = _makePoolData(
            SonicConstantsLib.TOKEN_WSTKSCUSD,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.TOKEN_STKSCUSD,
            SonicConstantsLib.TOKEN_WSTKSCUSD
        );
        /*pools[i++] = _makePoolData(
            SonicConstantsLib.POOL_SHADOW_CL_STKSCUSD_SCUSD_3000,
            AmmAdapterIdLib.UNISWAPV3,
            SonicConstantsLib.TOKEN_STKSCUSD,
            SonicConstantsLib.TOKEN_SCUSD
        );*/

        // wstksceth -> ETH
        pools[i++] = _makePoolData(
            SonicConstantsLib.TOKEN_WSTKSCETH,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.TOKEN_WSTKSCETH,
            SonicConstantsLib.TOKEN_STKSCETH
        );
        pools[i++] = _makePoolData(
            SonicConstantsLib.POOL_SHADOW_CL_SCETH_STKSCETH_250,
            AmmAdapterIdLib.UNISWAPV3,
            SonicConstantsLib.TOKEN_STKSCETH,
            SonicConstantsLib.TOKEN_SCETH
        );
    }

    function _makePoolData(
        address pool,
        string memory ammAdapterId,
        address tokenIn,
        address tokenOut
    ) internal pure returns (ISwapper.AddPoolData memory) {
        return ISwapper.AddPoolData({pool: pool, ammAdapterId: ammAdapterId, tokenIn: tokenIn, tokenOut: tokenOut});
    }

    function _upgradePlatform() internal {
        rewind(1 days);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        proxies[0] = platform.recovery();
        //        proxies[1] = platform.swapper();
        //        proxies[2] = platform.ammAdapter(keccak256(bytes(AmmAdapterIdLib.META_VAULT))).proxy;
        implementations[0] = address(new Recovery());
        //        implementations[1] = address(new Swapper());
        //        implementations[2] = address(new MetaVaultAdapter());

        vm.startPrank(platform.multisig());
        platform.announcePlatformUpgrade("2025.10.01-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }

    function _whiteListRecovery(address multisig, IRecovery recovery_) internal {
        vm.startPrank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSD).changeWhitelist(address(recovery_), true);
        IMetaVault(SonicConstantsLib.METAVAULT_METAS).changeWhitelist(address(recovery_), true);
        //        IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD).changeWhitelist(address(recovery_), true);
        //        IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).changeWhitelist(address(recovery_), true);
        vm.stopPrank();
    }
    //endregion ------------------------------------ Helpers
}
