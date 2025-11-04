// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;
import {Test} from "forge-std/Test.sol";
import {OAppEncodingLib} from "../../../src/periphery/libs/OAppEncodingLib.sol";

contract OAppEncodingLibWrapper {
    // внешний метод принимает bytes calldata и просто вызывает реализацию библиотеки
    function unpackPriceUsd18Ext(bytes calldata message)
        external
        pure
        returns (uint16 format, uint160 price, uint64 timestamp)
    {
        return OAppEncodingLib.unpackPriceUsd18(message);
    }
}

contract OAppEncodingLibTest is Test {
    function testPackUnpack_price1() public {
        uint price = 1;
        uint timestamp = 1761918746;
        bytes memory message = OAppEncodingLib.packPriceUsd18(price, timestamp);

        assertEq(message.length, 32);
        OAppEncodingLibWrapper wrapper = new OAppEncodingLibWrapper();
        (uint16 format, uint160 priceOut, uint64 tsOut) = wrapper.unpackPriceUsd18Ext(message);

        assertEq(uint(format), 1);
        assertEq(uint(priceOut), price);
        assertEq(uint64(tsOut), uint64(timestamp));
    }

    function testPackUnpack_price5999e15() public {
        uint price = 5999000000000000000; // 5.999e18
        uint timestamp = 33318827546;
        bytes memory message = OAppEncodingLib.packPriceUsd18(price, timestamp);

        assertEq(message.length, 32);
        OAppEncodingLibWrapper wrapper = new OAppEncodingLibWrapper();
        (uint16 format, uint160 priceOut, uint64 tsOut) = wrapper.unpackPriceUsd18Ext(message);

        assertEq(uint(format), 1);
        assertEq(uint(priceOut), price);
        assertEq(uint64(tsOut), uint64(timestamp));
    }

    function testPackUnpack_price1234e33() public {
        uint price = 1234 * 10 ** 33; // 1.234e36
        uint timestamp = 1670000002;
        bytes memory message = OAppEncodingLib.packPriceUsd18(price, timestamp);

        assertEq(message.length, 32);
        OAppEncodingLibWrapper wrapper = new OAppEncodingLibWrapper();
        (uint16 format, uint160 priceOut, uint64 tsOut) = wrapper.unpackPriceUsd18Ext(message);

        assertEq(uint(format), 1);
        assertEq(uint(priceOut), price);
        assertEq(uint64(tsOut), uint64(timestamp));
    }
}
