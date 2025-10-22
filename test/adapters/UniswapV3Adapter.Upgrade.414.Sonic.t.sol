// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UniswapV3Adapter} from "../../src/adapters/UniswapV3Adapter.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {SonicSetup, SonicConstantsLib, IERC20} from "../base/chains/SonicSetup.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";

contract MetaVaultAdapterUpgrade101Test is SonicSetup {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    uint public constant FORK_BLOCK = 51512001; // Oct-22-2025 08:40:54 AM +UTC

    UniswapV3Adapter public adapter;
    address public multisig;

    constructor() {
        vm.rollFork(FORK_BLOCK);
        _init();

        adapter = UniswapV3Adapter(IPlatform(PLATFORM).ammAdapter(keccak256(bytes(AmmAdapterIdLib.UNISWAPV3))).proxy);
        multisig = IPlatform(PLATFORM).multisig();

        _upgradePlatform();
    }

    //region ------------------------------------ Tests


    //endregion ------------------------------------ Tests


    //region ------------------------------------ Helper functions
    function _upgradePlatform() internal {
        // we need to skip 1 day to update the swapper
        // but we cannot simply skip 1 day, because the silo oracle will start to revert with InvalidPrice
        // vm.warp(block.timestamp - 86400);
        rewind(86400);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        proxies[0] = platform.ammAdapter(keccak256(bytes(AmmAdapterIdLib.UNISWAPV3))).proxy;
        implementations[0] = address(new UniswapV3Adapter());

        vm.startPrank(multisig);
        platform.announcePlatformUpgrade("2025.08.0-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }
    //endregion ------------------------------------ Helper functions
}