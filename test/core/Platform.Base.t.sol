// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/BaseSetup.sol";

contract PlatformBaseTest is BaseSetup {
    constructor() {
        _init();

        _deal(BaseLib.TOKEN_USDC, address(this), 1e12);
    }

    function testUserBalanceBase() public view {
        (
            address[] memory token,
            uint[] memory tokenPrice,
            uint[] memory tokenUserBalance,
            address[] memory vault,
            uint[] memory vaultSharePrice,
            uint[] memory vaultUserBalance,
            address[] memory nft,
            uint[] memory nftUserBalance,
        ) = platform.getBalance(address(this));
        uint len = token.length;
        for (uint i; i < len; ++i) {
            assertNotEq(token[i], address(0));
            assertGt(tokenPrice[i], 0);
            if (token[i] == BaseLib.TOKEN_USDC) {
                assertGe(tokenUserBalance[i], 1e12);
            } else {
                assertEq(tokenUserBalance[i], 0);
            }
        }
        len = vault.length;
        for (uint i; i < len; ++i) {
            assertNotEq(vault[i], address(0));
            assertGt(vaultSharePrice[i], 0);
            assertEq(vaultUserBalance[i], 0);
        }
        len = nft.length;
        for (uint i; i < len; ++i) {
            assertEq(nftUserBalance[i], 0);
        }
        assertEq(nft[0], platform.buildingPermitToken());
        assertEq(nft[1], platform.vaultManager());
        assertEq(nft[2], platform.strategyLogic());
    }
}
