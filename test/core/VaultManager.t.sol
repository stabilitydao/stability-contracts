// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {LibString} from "@solady/utils/LibString.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {MockStrategy} from "../../src/test/MockStrategy.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {IVaultManager} from "../../src/interfaces/IVaultManager.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {Utils} from "../base/Utils.sol";
import {FullMockSetup} from "../base/FullMockSetup.sol";

contract VaultManagerTest is Test, FullMockSetup, Utils {
    using LibString for string;

    CVault public vault;

    function setUp() public {
        deal(address(tokenB), address(this), 1e24);
        deal(address(tokenC), address(this), 1e24);
        tokenB.approve(address(factory), 2 ** 255);
        tokenC.approve(address(factory), 2 ** 255);
        address[] memory addresses = new address[](3);
        addresses[1] = address(lp);
        addresses[2] = address(tokenA);
        uint[] memory nums = new uint[](0);
        int24[] memory ticks = new int24[](0);
        factory.deployVaultAndStrategy(
            VaultTypeLib.COMPOUNDING, StrategyIdLib.DEV, new address[](0), new uint[](0), addresses, nums, ticks
        );

        vault = CVault(payable(factory.deployedVault(0)));
    }

    function testSVG() public {
        address[] memory assets = new address[](2);
        assets[0] = address(tokenA);
        assets[1] = address(tokenB);
        uint[] memory amounts = new uint[](2);
        amounts[0] = 1000e18;
        amounts[1] = 1000e6;
        tokenA.mint(amounts[0] * 2);
        tokenB.mint(amounts[1] * 2);
        tokenA.approve(address(vault), amounts[0]);
        tokenB.approve(address(vault), amounts[1]);

        vault.depositAssets(assets, amounts, 0, address(0));

        (uint sharePrice, bool sharePriceTrusted) = vault.price();
        assertEq(sharePrice, 1e18); // $1
        assertEq(sharePriceTrusted, true);

        // increase share price
        tokenA.mint(777e18 * 2);
        /// forge-lint: disable-next-line
        tokenA.transfer(address(vault.strategy()), 777555555e12);

        // set last hardwork apr
        MockStrategy(address(vault.strategy())).setLastApr(12_387);

        // svg
        string memory name;
        string memory description;

        (name, description,) = writeNftSvgToFile(platform.vaultManager(), 0, "out/VaultManager_CVault.svg");
        assertEq(keccak256(bytes(name)), keccak256(bytes("Vault #0")));
        assertEq(
            keccak256(bytes(description)),
            keccak256(bytes("Vault Stability MOCKA-MOCKB Dev Alpha DeepSpaceSwap Farm Good Params"))
        );
        // console.log(description);
    }

    function testSetRevenueReceiver() public {
        IVaultManager vaultManager = IVaultManager(platform.vaultManager());
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotTheOwner.selector));
        vaultManager.setRevenueReceiver(0, address(1));
        //owner of tokenId 1
        vm.prank(address(this));
        vaultManager.setRevenueReceiver(0, address(1));
        assertEq(vaultManager.getRevenueReceiver(0), address(1));
    }

    function testErc165() public view {
        IVaultManager vaultManager = IVaultManager(platform.vaultManager());
        assertEq(vaultManager.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(vaultManager.supportsInterface(type(IControllable).interfaceId), true);
        assertEq(vaultManager.supportsInterface(type(IERC721).interfaceId), true);
        assertEq(vaultManager.supportsInterface(type(IERC721Enumerable).interfaceId), true);
        assertEq(vaultManager.supportsInterface(type(IVaultManager).interfaceId), true);
    }

    function testTokenURI() public {
        IVaultManager vaultManager = IVaultManager(platform.vaultManager());
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotExist.selector));
        vaultManager.tokenURI(666);
    }
}
