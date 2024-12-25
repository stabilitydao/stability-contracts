// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console, Vm} from "forge-std/Test.sol";
import {FullMockSetup} from "../base/FullMockSetup.sol";
import {Builder} from "../../src/core/Builder.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

contract BuilderTest is Test, FullMockSetup {
    Builder public builder;

    function setUp() public {
        Proxy proxy = new Proxy();
        address implementation = address(new Builder());
        proxy.initProxy(implementation);
        builder = Builder(address(proxy));
        builder.initialize(address(platform));

        tokenA.mint(25e18);
        tokenA.approve(address(builder), 25e18);
    }

    function testInvest() public {
        builder.invest(address(tokenA), 11e18);
    }

    function testERC165() public {
        assertEq(builder.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(builder.supportsInterface(type(IERC721).interfaceId), true);
        assertEq(builder.supportsInterface(type(IERC721Metadata).interfaceId), true);
        assertEq(builder.supportsInterface(type(IControllable).interfaceId), true);
    }
}
