// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMainstreetMinter {

    /// @dev Stores the custodian address -> used to manage the collateral collected by this contract.
    function custodian() external view returns (address);

    /// @dev Stores the whitelister address -> used to manage the whitelist status of EOAs
    function whitelister() external view returns (address);

    /// @dev If the account is whitelisted, they have the ability to call mint, requestTokens, and claimTokens.
    function isWhitelisted(address user) external view returns (bool);

    /**
     * @notice Allows the whitelister to change the whitelist status of an address.
     * @dev The whitelist status of an address allows that address to execute mint, requestTokens, and claimTokens.
     * @param account Address whitelist role is being udpated.
     * @param whitelisted Status to set whitelist role to. If true, account is whitelisted.
     */
    function modifyWhitelist(address account, bool whitelisted) external;

    /**
     * @notice Mints msUSD tokens by accepting a deposit of approved collateral assets.
     * @dev Executes the complete minting workflow: transfers collateral from user, applies fee deduction (if any),
     * calculates token output via oracle price, and distributes msUSD to the msg.sender.
     * @param asset The collateral token address used for backing the generated msUSD.
     * @param amountIn The quantity of collateral tokens to be deposited.
     * @param minAmountOut The minimum acceptable msUSD output, transaction reverts if not satisfied.
     * @return amountOut The precise quantity of msUSD issued to the caller's address.
     */
    function mint(address asset, uint256 amountIn, uint256 minAmountOut) external returns (uint256 amountOut);

    /**
     * @notice Provides a quote of msUSD tokens a user would receive if they used a specified amountIn of an asset to
     * mint msUSD.
     * @param asset The address of the supported asset to calculate the quote for.
     * @param amountIn The amount of collateral being used to mint msUSD.
     * @return amountAsset The amount of msUSD `from` would receive if they minted with `amountIn` of `asset`.
     */
    function quoteMint(address asset, uint256 amountIn) external view returns (uint256 amountAsset);
}