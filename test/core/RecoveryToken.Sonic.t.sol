// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IMetaProxy} from "../../src/interfaces/IMetaProxy.sol";
import {MetaVaultFactory, IMetaVaultFactory} from "../../src/core/MetaVaultFactory.sol";
import {RecoveryToken, IRecoveryToken, IControllable} from "../../src/core/vaults/RecoveryToken.sol";

contract RecoveryTokenSonicTest is Test {
    uint public constant FORK_BLOCK = 42789000; // Aug-13-2025 10:30:56 AM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    bytes32 public constant SALT = 0xf7d97ca0d2c29912ea70ac9c5152ddcb9b06dee7964dd262ed7eacee5964b107;
    address public constant PREDICTED_ADDRESS = 0x000078392f3cF4262500FFeB7d803F90477ECC11;
    address public multisig;
    IMetaVaultFactory public metaVaultFactory;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
    }

    function setUp() public {
        multisig = IPlatform(PLATFORM).multisig();
        metaVaultFactory = IMetaVaultFactory(SonicConstantsLib.METAVAULT_FACTORY);

        // _upgradePlatform();
        _setupMetaVaultFactory();
    }

    function test_RecoveryToken() public {
        vm.prank(multisig);
        IRecoveryToken recToken =
            IRecoveryToken(metaVaultFactory.deployRecoveryToken(SALT, SonicConstantsLib.METAVAULT_metaUSD));
        assertEq(recToken.target(), SonicConstantsLib.METAVAULT_metaUSD);
        assertEq(address(recToken), PREDICTED_ADDRESS);

        // mint
        vm.expectRevert(IControllable.IncorrectMsgSender.selector);
        recToken.mint(address(1), 1);

        vm.prank(recToken.target());
        recToken.mint(address(1), 1);

        vm.prank(recToken.target());
        recToken.mint(address(3), 10);

        // pause
        vm.expectRevert(IControllable.IncorrectMsgSender.selector);
        recToken.setAddressPaused(address(1), true);

        vm.prank(recToken.target());
        recToken.setAddressPaused(address(1), true);

        vm.prank(multisig);
        recToken.setAddressPaused(address(2), true);

        // transfer
        vm.prank(address(3));
        IERC20(address(recToken)).transfer(address(10), 5);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(IRecoveryToken.TransfersPausedForAccount.selector, address(1)));
        IERC20(address(recToken)).transfer(address(10), 1);

        vm.prank(multisig);
        recToken.setAddressPaused(address(1), false);

        vm.prank(address(1));
        IERC20(address(recToken)).transfer(address(10), 1);
    }

    function test_RecoveryToken_upgrade() public {
        vm.prank(multisig);
        IRecoveryToken recToken =
            IRecoveryToken(metaVaultFactory.deployRecoveryToken(0x00, SonicConstantsLib.METAVAULT_metaUSD));

        address recoveryTokenImplementation = address(new RecoveryToken());

        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        metaVaultFactory.setRecoveryTokenImplementation(recoveryTokenImplementation);

        vm.prank(multisig);
        metaVaultFactory.setRecoveryTokenImplementation(recoveryTokenImplementation);

        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(recToken);
        vm.prank(multisig);
        metaVaultFactory.upgradeMetaProxies(metaProxies);
        assertEq(IMetaProxy(address(recToken)).implementation(), recoveryTokenImplementation);

        vm.prank(recToken.target());
        recToken.mint(address(1), 1);
    }

    function test_RecoveryToken_bulkTransferFrom() public {
        vm.prank(multisig);
        IRecoveryToken recToken =
            IRecoveryToken(metaVaultFactory.deployRecoveryToken(0x00, SonicConstantsLib.METAVAULT_metaUSD));

        vm.prank(recToken.target());
        recToken.mint(address(1), 100);

        address[] memory to = new address[](3);
        to[0] = address(10);
        to[1] = address(11);
        to[2] = address(12);
        uint[] memory amounts = new uint[](3);
        amounts[0] = 2;
        amounts[1] = 2;
        amounts[2] = 3;
        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        recToken.bulkTransferFrom(address(1), to, amounts);

        vm.prank(multisig);
        recToken.bulkTransferFrom(address(1), to, amounts);
        assertEq(IERC20(address(recToken)).balanceOf(address(1)), 93);
        assertEq(IERC20(address(recToken)).balanceOf(address(11)), 2);

        vm.prank(recToken.target());
        recToken.setAddressPaused(address(1), true);

        vm.prank(multisig);
        recToken.bulkTransferFrom(address(1), to, amounts);
        assertEq(recToken.paused(address(1)), true);
    }

    function _upgradePlatform() internal {
        address[] memory proxies = new address[](1);
        proxies[0] = address(metaVaultFactory);

        address[] memory implementations = new address[](1);
        implementations[0] = address(new MetaVaultFactory());

        vm.prank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.08.0-alpha", proxies, implementations);

        skip(1 days);

        vm.prank(multisig);
        IPlatform(PLATFORM).upgrade();
    }

    function _setupMetaVaultFactory() internal {
        address recoveryTokenImplementation = address(new RecoveryToken());
        vm.prank(multisig);
        metaVaultFactory.setRecoveryTokenImplementation(recoveryTokenImplementation);
    }
}
