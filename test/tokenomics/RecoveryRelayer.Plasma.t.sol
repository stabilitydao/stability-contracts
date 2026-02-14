// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {RevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IRecoveryRelayer} from "../../src/interfaces/IRecoveryRelayer.sol";
import {IRevenueRouter} from "../../src/interfaces/IRevenueRouter.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {RecoveryRelayerLib} from "../../src/tokenomics/libs/RecoveryRelayerLib.sol";
import {RecoveryRelayer} from "../../src/tokenomics/RecoveryRelayer.sol";
import {Test} from "forge-std/Test.sol";
// import {console} from "forge-std/console.sol";

contract RecoveryRelayerPlasmaTest is Test {
    uint public constant FORK_BLOCK = 8339817; // Dec-9-2025 08:54:48 UTC
    address internal multisig;

    address public constant AMF_STRATEGY = 0x5AC5b2740F77200CCe6562795cFcf4c3c2aC3745;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("PLASMA_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(PlasmaConstantsLib.PLATFORM).multisig();
    }

    //region --------------------------------- Unit tests
    function testRecoveryStorageLocation() public pure {
        assertEq(
            keccak256(abi.encode(uint(keccak256("erc7201:stability.RecoveryRelayer")) - 1)) & ~bytes32(uint(0xff)),
            RecoveryRelayerLib._RECOVERY_RELAYER_STORAGE_LOCATION,
            "_RECOVERY_RELAYER_STORAGE_LOCATION"
        );
    }

    function testSetThreshold() public {
        RecoveryRelayer recoveryRelayer = createRecoveryRelayerInstance();

        address[] memory assets = new address[](2);
        assets[0] = PlasmaConstantsLib.TOKEN_USDT0;
        assets[1] = PlasmaConstantsLib.TOKEN_WXPL;

        uint[] memory thresholds = new uint[](2);
        thresholds[0] = 1e6; // usdt
        thresholds[1] = 1e18; // wxpl

        assertEq(recoveryRelayer.threshold(assets[0]), 0, "usdt threshold is zero by default");
        assertEq(recoveryRelayer.threshold(assets[1]), 0, "wxpl threshold is zero by default");

        vm.expectRevert(IControllable.NotOperator.selector);
        vm.prank(address(this));
        recoveryRelayer.setThresholds(assets, thresholds);

        vm.prank(multisig);
        recoveryRelayer.setThresholds(assets, thresholds);

        assertEq(recoveryRelayer.threshold(assets[0]), thresholds[0], "usdt threshold 1");
        assertEq(recoveryRelayer.threshold(assets[1]), thresholds[1], "wxpl threshold 1");

        thresholds[0] = 2e6; // usdt
        thresholds[1] = 0; // wxpl

        vm.prank(multisig);
        recoveryRelayer.setThresholds(assets, thresholds);

        assertEq(recoveryRelayer.threshold(assets[0]), thresholds[0], "usdt threshold 2");
        assertEq(recoveryRelayer.threshold(assets[1]), thresholds[1], "wxpl threshold 2");
    }

    function testChangeWhitelist() public {
        RecoveryRelayer recoveryRelayer = createRecoveryRelayerInstance();

        address operator1 = makeAddr("operator1");
        address operator2 = makeAddr("operator2");

        assertEq(recoveryRelayer.whitelisted(multisig), true, "multisig is whitelisted by default");
        assertEq(recoveryRelayer.whitelisted(operator1), false, "operator1 is not whitelisted by default");
        assertEq(recoveryRelayer.whitelisted(operator2), false, "operator2 is not whitelisted by default");

        vm.expectRevert(IControllable.NotOperator.selector);
        vm.prank(address(this));
        recoveryRelayer.changeWhitelist(operator1, true);

        vm.prank(multisig);
        recoveryRelayer.changeWhitelist(operator1, true);

        assertEq(recoveryRelayer.whitelisted(operator1), true, "operator1 is whitelisted");
        assertEq(recoveryRelayer.whitelisted(operator2), false, "operator2 is not whitelisted");

        vm.prank(multisig);
        recoveryRelayer.changeWhitelist(operator2, true);

        assertEq(recoveryRelayer.whitelisted(operator2), true, "operator2 is whitelisted");

        vm.prank(multisig);
        recoveryRelayer.changeWhitelist(operator1, false);

        assertEq(recoveryRelayer.whitelisted(operator1), false, "operator1 is not whitelisted");
        assertEq(recoveryRelayer.whitelisted(operator2), true, "operator2 is whitelisted");
    }

    function testRegisterAssetsBadPaths() public {
        RecoveryRelayer recoveryRelayer = createRecoveryRelayerInstance();

        address[] memory tokens = new address[](2);
        tokens[0] = PlasmaConstantsLib.TOKEN_USDT0;
        tokens[1] = PlasmaConstantsLib.TOKEN_WXPL;

        assertEq(recoveryRelayer.isTokenRegistered(tokens[0]), false, "usdt not registered");
        assertEq(recoveryRelayer.isTokenRegistered(tokens[1]), false, "wxpl not registered");

        vm.expectRevert(RecoveryRelayerLib.NotWhitelisted.selector);
        vm.prank(address(this));
        recoveryRelayer.registerAssets(tokens);

        vm.prank(multisig);
        recoveryRelayer.registerAssets(tokens);

        assertEq(recoveryRelayer.isTokenRegistered(tokens[0]), true, "usdt is registered");
        assertEq(recoveryRelayer.isTokenRegistered(tokens[1]), true, "wxpl is registered");

        tokens[0] = PlasmaConstantsLib.TOKEN_USDE;
        tokens[1] = PlasmaConstantsLib.TOKEN_USDT0;

        vm.prank(multisig);
        recoveryRelayer.changeWhitelist(address(this), true);

        vm.prank(address(this));
        recoveryRelayer.registerAssets(tokens);

        assertEq(recoveryRelayer.isTokenRegistered(tokens[0]), true, "usde is registered");
        assertEq(recoveryRelayer.isTokenRegistered(tokens[1]), true, "usdc is registered");
    }

    function testGetListTokensToSwap() public {
        RecoveryRelayer recoveryRelayer = createRecoveryRelayerInstance();

        address[] memory tokens = new address[](3);
        tokens[0] = PlasmaConstantsLib.TOKEN_USDT0;
        tokens[1] = PlasmaConstantsLib.TOKEN_WXPL;
        tokens[2] = PlasmaConstantsLib.TOKEN_USDE;

        vm.prank(multisig);
        recoveryRelayer.registerAssets(tokens);

        address[] memory list = recoveryRelayer.getListTokensToSwap();
        assertEq(list.length, 0, "no tokens to swap");

        // ------------------------- Put some assets on balance of Recovery
        deal(PlasmaConstantsLib.TOKEN_USDT0, address(recoveryRelayer), 1e6);
        deal(PlasmaConstantsLib.TOKEN_USDE, address(recoveryRelayer), 2e6);

        list = recoveryRelayer.getListTokensToSwap();
        assertEq(list.length, 2, "2 tokens to swap A");
        assertEq(list[0], PlasmaConstantsLib.TOKEN_USDT0, "token 0 is usdc A");
        assertEq(list[1], PlasmaConstantsLib.TOKEN_USDE, "token 1 is usdt A");

        // ------------------------- Set high threshold for USDT
        address[] memory assets = new address[](1);
        assets[0] = PlasmaConstantsLib.TOKEN_USDT0;

        uint[] memory thresholds = new uint[](1);
        thresholds[0] = 1e6; // usdt

        vm.prank(multisig);
        recoveryRelayer.setThresholds(assets, thresholds);

        list = recoveryRelayer.getListTokensToSwap();
        assertEq(list.length, 1, "1 token to swap B");
        assertEq(list[0], PlasmaConstantsLib.TOKEN_USDE, "token 0 is usde B");

        // ------------------------- Tests for auxiliary getListRegisteredTokens
        list = recoveryRelayer.getListRegisteredTokens();
        assertEq(list.length, 3);
    }

    //endregion --------------------------------- Unit tests

    /// @notice todo setup bridge on Plasma
    function testUpgrade() internal {
        // ---------------------- Setup RecoveryRelayer in the platform
        {
            Proxy proxy = new Proxy();
            address implementation = address(new RecoveryRelayer());
            proxy.initProxy(implementation);

            vm.prank(multisig);
            IPlatform(PlasmaConstantsLib.PLATFORM).setupRecovery(address(proxy));
        }

        _upgradeRevenueRouter();

        // ---------------------- Set up revenue router
        IRevenueRouter revenueRouter = IRevenueRouter(IPlatform(PlasmaConstantsLib.PLATFORM).revenueRouter());

        //        IFactory factory = IFactory(IPlatform(PlasmaConstantsLib.PLATFORM).factory());
        //        IFactory.Farm memory farm = factory.farm(0);
        //        console.log(farm.strategyLogicId); // Aave Merkl Farm
        //
        //        address[] memory vaults = factory.deployedVaults();
        //        for (uint i; i < vaults.length; ++i) {
        //            console.log("Vault:", vaults[i]);
        //        }

        // ---------------------- emulate merkl rewards
        address vault = IStrategy(AMF_STRATEGY).vault();
        deal(PlasmaConstantsLib.TOKEN_WXPL, AMF_STRATEGY, 1e18);

        // ---------------------- hardwork
        vm.prank(vault);
        IStrategy(AMF_STRATEGY).doHardWork();

        vm.prank(multisig);
        revenueRouter.processAccumulatedAssets(1);

        // ---------------------- RecoveryRelayer receives 20%
        address[] memory tokens =
            IRecoveryRelayer(IPlatform(PlasmaConstantsLib.PLATFORM).recovery()).getListRegisteredTokens();
        assertNotEq(tokens.length, 0, "RecoveryRelayer has registered tokens");
    }

    //region --------------------------------- Utils

    function createRecoveryRelayerInstance() internal returns (RecoveryRelayer) {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new RecoveryRelayer()));
        RecoveryRelayer recovery = RecoveryRelayer(address(proxy));
        recovery.initialize(PlasmaConstantsLib.PLATFORM);

        return recovery;
    }

    function _upgradeRevenueRouter() internal {
        address revenueRouter = IPlatform(PlasmaConstantsLib.PLATFORM).revenueRouter();

        address[] memory proxies = new address[](1);
        proxies[0] = address(revenueRouter);
        address[] memory implementations = new address[](1);
        implementations[0] = address(new RevenueRouter());
        vm.startPrank(multisig);
        IPlatform(PlasmaConstantsLib.PLATFORM).announcePlatformUpgrade("2025.12.0-alpha", proxies, implementations);
        skip(18 hours);
        IPlatform(PlasmaConstantsLib.PLATFORM).upgrade();
        vm.stopPrank();
        rewind(17 hours);
    }
    //endregion --------------------------------- Utils
}
