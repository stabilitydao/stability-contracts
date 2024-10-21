// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IBuilder {
    event Invested(address indexed user, uint indexed tokenId, address indexed asset, uint amount, uint48 amountUSD);

    error NotTrustedPriceFor(address asset);
    error ZeroAmountToInvest();
    error TooLittleAmountToInvest(uint amountUSD, uint minimum);

    struct TokenData {
        uint8 role;
        uint48 invested;
        uint48 bountyPending;
        uint48 bountyGot;
    }

    /// @notice Invest money in development
    /// @param asset Allowed asset
    /// @param amount Amount of asset
    /// @return amountUSD Invested USD amount with 2 decimals
    function invest(address asset, uint amount) external returns (uint48 amountUSD);
}
