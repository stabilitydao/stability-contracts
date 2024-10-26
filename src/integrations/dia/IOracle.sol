// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Oracle Interface
 * @notice Interface for oracle contracts providing external asset price data.
 * @dev This interface defines functions for fetching latest prices and converting values and amounts
 *      based on these prices. It includes mechanisms for handling rounding and price capping.
 *      Oracles implementing this interface are essential in DeFi applications for price-sensitive operations.
 * @author SeaZarrgh LaBuoy
 */
interface IOracle {
    /**
     * @notice Error indicating that the fetched price is older than the acceptable maximum age.
     * @param price The stale price value.
     * @param maxAge The maximum acceptable age for a price.
     * @param age The actual age of the price.
     */
    error StalePrice(uint256 price, uint256 maxAge, uint256 age);

    /**
     * @notice Converts a value in the base currency to an amount in the oracle's asset, applying a specified rounding
     *         method.
     * @dev Function to calculate the amount of asset corresponding to a given value, with rounding.
     * @param value The value to convert.
     * @param rounding The rounding method to be used (up, down, or closest).
     * @return amount The calculated amount in the oracle's asset.
     */
    function amountOf(uint256 value, Math.Rounding rounding) external view returns (uint256 amount);

    /**
     * @notice Converts a value in the base currency to an amount in the oracle's asset, ensuring that the price data is
     * not older than maxAge.
     * @dev Function to calculate the amount of asset corresponding to a given value, with rounding, while ensuring the
     * latest price is fresh.
     * @param value The value to convert.
     * @param maxAge The maximum acceptable age for the price data (in seconds).
     * @param rounding The rounding method to be used (up, down, or closest).
     * @return amount The calculated amount in the oracle's asset.
     */
    function amountOf(uint256 value, uint256 maxAge, Math.Rounding rounding) external view returns (uint256 amount);

    /**
     * @notice Converts a value in the base currency to an amount in the oracle's asset at a specific price, applying a
     *         specified rounding method.
     * @dev Calculates the equivalent amount of the oracle's asset for a given value using a specified price.
     *      This function is useful for scenarios where a specific price point is considered instead of the latest price
     *      from the oracle.
     * @param value The value in the base currency to be converted.
     * @param price The specific price to use for the conversion.
     * @param rounding The rounding method to be used (up, down, or closest).
     * @return amount The calculated amount in the oracle's asset at the specified price.
     */
    function amountOfAtPrice(uint256 value, uint256 price, Math.Rounding rounding)
    external
    view
    returns (uint256 amount);

    /**
     * @notice Fetches the latest price from the oracle.
     * @dev Function to get the most recent price data.
     * @return price The latest price.
     */
    function latestPrice() external view returns (uint256 price);

    /**
     * @notice Fetches the latest price from the oracle, ensuring it is not older than a specified maximum age.
     * @dev Function to get the latest price, with a constraint on the maximum age of the price data.
     * @param maxAge The maximum acceptable age for the price data.
     * @return price The latest price, if it is within the maximum age limit.
     */
    function latestPrice(uint256 maxAge) external view returns (uint256 price);

    /**
     * @notice Converts an amount in the oracle's asset to a value in the base currency, applying a specified rounding
     *         method.
     * @dev Function to calculate the value of a given amount in the base currency, with rounding.
     * @param amount The amount to convert.
     * @param rounding The rounding method to be used (up, down, or closest).
     * @return value The calculated value in the base currency.
     */
    function valueOf(uint256 amount, Math.Rounding rounding) external view returns (uint256 value);

    /**
     * @notice Converts an amount in the oracle's asset to a value in the base currency, ensuring that the price data is
     * not older than maxAge.
     * @dev Function to calculate the value of a given amount, while ensuring the latest price is not stale.
     * @param amount The amount to convert.
     * @param maxAge The maximum acceptable age for the price data (in seconds).
     * @param rounding The rounding method to be used.
     * @return value The calculated value in the base currency.
     */
    function valueOf(uint256 amount, uint256 maxAge, Math.Rounding rounding) external view returns (uint256 value);

    /**
     * @notice Converts an amount in the oracle's asset to a value in the base currency at a specific price, applying a
     *         specified rounding method.
     * @dev Calculates the equivalent value in the base currency for a given amount of the oracle's asset using a
     *      specified price.
     *      This function allows for value calculations based on a specific price, rather than relying solely on the
     *      latest price from the oracle.
     * @param amount The amount of the oracle's asset to be converted.
     * @param price The specific price to use for the conversion.
     * @param rounding The rounding method to be used (up, down, or closest).
     * @return value The calculated value in the base currency at the specified price.
     */
    function valueOfAtPrice(uint256 amount, uint256 price, Math.Rounding rounding)
    external
    view
    returns (uint256 value);
}
