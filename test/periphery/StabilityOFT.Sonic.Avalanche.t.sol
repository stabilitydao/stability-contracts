// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {Platform} from "../../src/core/Platform.sol";
import {Frontend} from "../../src/periphery/Frontend.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IVaultManager} from "../../src/interfaces/IVaultManager.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StabilityOFTAdapter} from "../../src/periphery/StabilityOFTAdapter.sol";
import {StabilityOFT} from "../../src/periphery/StabilityOFT.sol";
import {console, Test} from "forge-std/Test.sol";
import {AvalancheLib} from "../../chains/AvalancheLib.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";

contract StabilityOFTSonicAvalanche is Test {
    address public constant SONIC_PLATFORM = SonicConstantsLib.PLATFORM;
    address public multisig;
    uint public forkSonicId;
    uint public forkAvalancheId;

    uint public constant SONIC_FORK_BLOCK = 41181557; // Aug-01-2025 09:47:16 AM +UTC
    uint public constant AVALANCHE_FORK_BLOCK = 41682430; // Aug 01, 2025 09:59:06 GMT

    StabilityOFT internal oft;
    StabilityOFTAdapter internal oftAdapter;

    constructor() {
        forkSonicId = vm.createFork(vm.envString("SONIC_RPC_URL"));
        forkAvalancheId = vm.createFork(vm.envString("AVALANCHE_RPC_URL"));

        vm.selectFork(forkSonicId);
        vm.rollFork(SONIC_FORK_BLOCK);

        vm.selectFork(forkAvalancheId);
        vm.rollFork(AVALANCHE_FORK_BLOCK);
    }

    function setUp() public {
        _setUpSonic();
        _setUpAvalanche();
    }

    function _setUpSonic() internal {
        console.log("_setUpSonic");
        vm.selectFork(forkSonicId);
        multisig = IPlatform(SONIC_PLATFORM).multisig();

        Proxy proxy = new Proxy();
        proxy.initProxy(
            address(
                new StabilityOFTAdapter(SonicConstantsLib.METAVAULT_metaUSD, SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT)
            )
        );
        oftAdapter = proxy;
    }

    function _setUpAvalanche() internal {
        console.log("_setUpAvalanche");
        vm.selectFork(forkAvalancheId);

        Proxy proxyPlatform = new Proxy();
        proxyPlatform.initProxy(address(new Platform()));

        Platform platform = Platform(address(proxyPlatform));
        platform.initialize(address(this), "25.08.0-dev");

        platform.setup(
            IPlatform.SetupAddresses({
                factory: address(0),
                priceReader: address(0),
                swapper: address(1), // todo
                buildingPermitToken: address(0),
                buildingPayPerVaultToken: address(AvalancheLib.TOKEN_WAVAX),
                vaultManager: address(0),
                strategyLogic: address(0),
                aprOracle: address(10),
                targetExchangeAsset: address(0),
                hardWorker: address(0),
                zap: address(0),
                revenueRouter: address(0)
            }),
            IPlatform.PlatformSettings({
                networkName: "Avalanche probe",
                networkExtra: CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x7746d7), bytes3(0x040206))),
                fee: 6_000,
                feeShareVaultManager: 30_000,
                feeShareStrategyLogic: 30_000,
                feeShareEcosystem: 0,
                minInitialBoostPerDay: 30e18, // $30
                minInitialBoostDuration: 30 * 86400 // 30 days
            })
        );

        Proxy proxyOft = new Proxy();
        proxyOft.initProxy(address(new StabilityOFT(AvalancheLib.LAYER_ZERO_V2_ENDPOINT)));

        oft = proxyOft;
    }

    function testStabilityOFT() public {
        vm.selectFork(forkSonicId);

        // -------------------------------- set up OftAdapter on Sonic


        // -------------------------------- set up Oft on Avalanche
    }
}
