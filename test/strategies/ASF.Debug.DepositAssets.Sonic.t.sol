// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {ILPStrategy} from "../../src/interfaces/ILPStrategy.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IUniswapV3Pool} from "../../src/integrations/uniswapv3/IUniswapV3Pool.sol";

contract ASFDebugDepositAssetsTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    //address public constant STRATEGY = 0xC37F16E3E5576496d06e3Bb2905f73574d59EAF7;
    address public constant STRATEGY = 0x08ecA9d652db6E40875018ccA6e53C10bfD456CA;
    address public vault;
    address public multisig;

    uint internal constant FORK_BLOCK = 6279185; // Feb-02-2025 06:50:26 PM +UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        //vm.rollFork(6001000); // Jan-31-2025 09:52:19 AM +UTC

        vault = IStrategy(STRATEGY).vault();
        multisig = IPlatform(IControllable(STRATEGY).platform()).multisig();
    }

    function testASFPriceThreshold() public {
        /*uint price = 545499697146915917430930;
        uint priceBefore = 544565544544309436616693;
        console.log(price * 10_000 / priceBefore);
        console.log(priceBefore * 10_000 / price);*/

        address[] memory assets = IStrategy(STRATEGY).assets();
        uint[] memory amounts = new uint[](2);
        amounts[0] = 10e18;
        amounts[1] = 1e18;

        deal(assets[0], address(this), amounts[0]);
        deal(assets[1], address(this), amounts[1]);
        IERC20(assets[0]).approve(vault, type(uint).max);
        IERC20(assets[1]).approve(vault, type(uint).max);
        vm.expectRevert();
        IVault(vault).depositAssets(assets, amounts, 0, address(this));

        // this helped
        IUniswapV3Pool(ILPStrategy(STRATEGY).pool()).increaseObservationCardinalityNext(500);

        // working ok in prod
        //IVault(vault).depositAssets(assets, amounts, 0, address(this));

        /*vm.prank(multisig);
        IALM(STRATEGY).setupPriceChangeProtection(true, 600, 10020);

        IVault(vault).depositAssets(assets, amounts, 0, address(this));*/
    }
}
