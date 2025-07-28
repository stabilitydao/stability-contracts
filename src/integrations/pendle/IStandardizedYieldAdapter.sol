// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

interface IStandardizedYieldAdapter {
  /**
   * @notice Retrieves the address of the pivot token.
     * @return pivotToken The address of the pivot token.
     */
  function PIVOT_TOKEN() external view returns (address pivotToken);

  /**
   * @notice Converts a specified amount of an input token to pivotToken.
     * @dev This function should expect the token has already been transferred to the adapter.
     * @param tokenIn The address of the input token.
     * @param amountTokenIn The amount of the input token to convert.
     * @return amountOut The amount of the pivot token.
     */
  function convertToDeposit(address tokenIn, uint256 amountTokenIn) external returns (uint256 amountOut);

  /**
   * @notice Converts pivotToken to the token requested for redemption.
     * @dev This function should expect pivotToken has already been transferred to the adapter.
     * @param tokenOut The address of the output token.
     * @param amountPivotTokenIn The amount of pivot token to convert.
     * @return amountOut The amount of the output token out.
     */
  function convertToRedeem(address tokenOut, uint256 amountPivotTokenIn) external returns (uint256 amountOut);

  /**
   * @notice Previews the conversion of a specified amount of an input token to pivotToken.
     * @param tokenIn The address of the input token.
     * @param amountTokenIn The amount of the input token to convert.
     * @return amountOut The estimated amount of the pivot token.
     */
  function previewConvertToDeposit(address tokenIn, uint256 amountTokenIn) external view returns (uint256 amountOut);

  /**
   * @notice Previews the conversion of pivot token to the amount requested for redemption.
     * @param tokenOut The address of the output token.
     * @param amountPivotTokenIn The amount of pivot token to convert.
     * @return amountOut The estimated amount of the output token out.
     */
  function previewConvertToRedeem(
    address tokenOut,
    uint256 amountPivotTokenIn
  ) external view returns (uint256 amountOut);

  /**
   * @notice Retrieves the list of tokens supported for deposits by the adapter.
     * @return tokens An array of addresses of tokens supported for deposits.
     */
  function getAdapterTokensDeposit() external view returns (address[] memory tokens);

  /**
   * @notice Retrieves the list of tokens supported for redemptions by the adapter.
     * @return tokens An array of addresses of tokens supported for redemptions.
     */
  function getAdapterTokensRedeem() external view returns (address[] memory tokens);
}
