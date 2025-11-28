// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library OAppEncodingLib {
    /// @notice Format of the message containing price in USD with 18 decimals
    uint16 internal constant MESSAGE_FORMAT_PRICE_USD18_1 = 1;

    function packPriceUsd18(uint price, uint timestamp) internal pure returns (bytes memory) {
        bytes32 serialized = bytes32(
            (uint(MESSAGE_FORMAT_PRICE_USD18_1) << 240) | (uint(uint160(price)) << 80) | (uint(uint64(timestamp)) << 16)
        );
        return abi.encodePacked(serialized);
    }

    /// @dev calldata is used to reduce gas consumption of lzReceive (from 29894 to 29703)
    function unpackPriceUsd18(bytes calldata message)
        internal
        pure
        returns (uint16 format, uint160 price, uint64 timestamp)
    {
        // assume here that message length >= 32 here
        bytes32 serialized = abi.decode(message, (bytes32));

        uint raw = uint(serialized);

        format = uint16(raw >> 240);
        price = uint160(raw >> 80);
        timestamp = uint64((raw >> 16) & ((uint(1) << 64) - 1));
    }
}
