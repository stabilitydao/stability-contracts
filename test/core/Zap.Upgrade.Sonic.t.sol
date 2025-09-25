// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {Zap} from "../../src/core/Zap.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IZap} from "../../src/interfaces/IZap.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";

contract ZapUpgradeSonic is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    struct ZapTestVars {
        address depositToken;
        address[] assets;
        IStrategy strategy;
        uint depositAmount;
        uint[] swapAmounts;
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(3032000); // Jan-08-2025 08:39:58 PM +UTC
    }

    function testZapUpgrade() public {
        address multisig = IPlatform(PLATFORM).multisig();
        IZap zap = IZap(IPlatform(PLATFORM).zap());
        address swapper = IPlatform(PLATFORM).swapper();
        // C-wSSACRA-ISF
        address vault = 0x3037a9ec06c25a2190794B533703755cDD137079;

        ZapTestVars memory v;
        v.strategy = IVault(vault).strategy();
        v.assets = v.strategy.assets();
        v.depositToken = SonicConstantsLib.TOKEN_USDC;
        v.depositAmount = 100e6;
        (, v.swapAmounts) = zap.getDepositSwapAmounts(vault, v.depositToken, v.depositAmount);
        //console.log(v.swapAmounts[0],v.swapAmounts[1]);

        bytes[] memory swapData = new bytes[](2);
        swapData[1] = abi.encodeCall(ISwapper.swap, (v.depositToken, v.assets[1], v.swapAmounts[1], 1_000));
        deal(v.depositToken, address(this), v.depositAmount);
        IERC20(v.depositToken).approve(address(zap), v.depositAmount);
        vm.expectRevert();
        zap.deposit(vault, v.depositToken, v.depositAmount, swapper, swapData, 1, address(this));

        address newZapImplementation = address(new Zap());
        address[] memory proxies = new address[](1);
        proxies[0] = address(address(zap));
        address[] memory implementations = new address[](1);
        implementations[0] = newZapImplementation;
        vm.startPrank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.01.1-alpha", proxies, implementations);
        skip(1 days);
        IPlatform(PLATFORM).upgrade();
        vm.stopPrank();

        zap.deposit(vault, v.depositToken, v.depositAmount, swapper, swapData, 1, address(this));
    }
}
