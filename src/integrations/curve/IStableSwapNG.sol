// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IStableSwapNG {
    function N_COINS() external view returns (uint);

    function BASE_POOL() external view returns (address);

    function BASE_N_COINS() external view returns (uint);

    function stored_rates() external view returns (uint[] memory);

    function balances(uint i) external view returns (uint);

    function get_balances() external view returns (uint[] memory);

    function fee() external view returns (uint);

    function get_dy(int128 i, int128 j, uint dx) external view returns (uint);

    function A() external view returns (uint);

    function calc_withdraw_one_coin(uint _token_amount, int128 i) external view returns (uint);

    /// @notice The total supply of pool LP tokens
    /// @return self.total_supply, 18 decimals.
    function totalSupply() external view returns (uint);

    function calc_token_amount(uint[] memory amounts, bool deposit) external view returns (uint);

    function offpeg_fee_multiplier() external view returns (uint);
}
