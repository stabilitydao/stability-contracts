// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {PlasmaLib, PlasmaConstantsLib, AmmAdapterIdLib, IBalancerAdapter} from "../../chains/plasma/PlasmaLib.sol";
import {IAmmAdapter} from "../../src/interfaces/IAmmAdapter.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {PlasmaSetup} from "../base/chains/PlasmaSetup.sol";

contract BalancerV3ReCLAMMAdapterTest is PlasmaSetup {
    bytes32 public _hash;
    IAmmAdapter public adapter;

    constructor() {
        _init();
        _hash = keccak256(bytes(AmmAdapterIdLib.BALANCER_V3_RECLAMM));
        adapter = IAmmAdapter(platform.ammAdapter(_hash).proxy);
        //console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.BalancerV3ReClammAdapter")) - 1)) & ~bytes32(uint256(0xff)));
    }

    function testIBalancerAdapter() public {
        IBalancerAdapter balancerAdapter = IBalancerAdapter(address(adapter));
        vm.expectRevert(IControllable.AlreadyExist.selector);
        balancerAdapter.setupHelpers(address(1));

        address pool = PlasmaConstantsLib.POOL_BALANCER_V3_RECLAMM_WXPL_USDT0;
        uint[] memory amounts = new uint[](2);
        amounts[0] = 100e18;
        amounts[1] = 100e6;
        vm.expectRevert();
        balancerAdapter.getLiquidityForAmountsWrite(pool, amounts);
    }

    function testSwaps() public {
        // todo
    }

    function testViewMethods() public view {
        assertEq(keccak256(bytes(adapter.ammAdapterId())), _hash);

        address pool = PlasmaConstantsLib.POOL_BALANCER_V3_RECLAMM_WXPL_USDT0;
        address[] memory tokens = adapter.poolTokens(pool);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], PlasmaConstantsLib.TOKEN_WXPL);
        assertEq(tokens[1], PlasmaConstantsLib.TOKEN_USDT0);

        uint[] memory props = adapter.getProportions(pool);
        //assertEq(props[0], 8e17);
        //assertEq(props[1], 2e17);
        //console.log(props[0]);
        //console.log(props[1]);

        /*uint price;
        price = adapter.getPrice(pool, PlasmaConstantsLib.TOKEN_WXPL, PlasmaConstantsLib.TOKEN_USDT0, 1e18);
        assertGt(price, 1e8);*/
        // console.log(price);

        assertEq(adapter.supportsInterface(type(IAmmAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IBalancerAdapter).interfaceId), true);
        assertEq(adapter.supportsInterface(type(IERC165).interfaceId), true);
    }
}
