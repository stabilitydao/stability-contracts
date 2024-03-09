// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IOToken {
    function exercise(uint amount, uint maxPaymentAmount, address recipient) external returns (uint);

    function getDiscountedPrice(uint amount_) external view returns (uint amount);

    function discount() external view returns (uint);
}
