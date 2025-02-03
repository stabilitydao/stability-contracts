// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SonicLib} from "../../chains/SonicLib.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IALM} from "../../src/interfaces/IALM.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";

contract ASFDebugDepositAssetsTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STRATEGY = 0xC37F16E3E5576496d06e3Bb2905f73574d59EAF7;
    address public vault;
    address public multisig;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(6001000); // Jan-31-2025 09:52:19 AM +UTC
        vault = IStrategy(STRATEGY).vault();
        multisig = IPlatform(IControllable(STRATEGY).platform()).multisig();
    }

    function testASFPriceThreshold() public {
        /*uint price = 545499697146915917430930;
        uint priceBefore = 544565544544309436616693;
        console.log(price * 10_000 / priceBefore);
        console.log(priceBefore * 10_000 / price);*/

        deal(SonicLib.TOKEN_wS, address(this), 10e18);
        deal(SonicLib.TOKEN_USDC, address(this), 10e6);
        IERC20(SonicLib.TOKEN_wS).approve(vault, type(uint).max);
        IERC20(SonicLib.TOKEN_USDC).approve(vault, type(uint).max);
        address[] memory assets = IStrategy(STRATEGY).assets();
        uint[] memory amounts = new uint[](2);
        amounts[0] = 10e18;
        amounts[1] = 10e6;
        vm.expectRevert();
        IVault(vault).depositAssets(assets, amounts, 0, address(this));

        vm.prank(multisig);
        IALM(STRATEGY).setupPriceChangeProtection(true, 600, 10020);

        IVault(vault).depositAssets(assets, amounts, 0, address(this));
    }
}
