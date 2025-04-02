// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import "./IPAllActionTypeV3.sol";

/// Refer to IPAllActionTypeV3.sol for details on the parameters
interface IPActionSwapPTV3 {
    function swapExactTokenForPt(
        address receiver,
        address market,
        uint minPtOut,
        ApproxParams calldata guessPtOut,
        TokenInput calldata input,
        LimitOrderData calldata limit
    ) external payable returns (uint netPtOut, uint netSyFee, uint netSyInterm);

    function swapExactSyForPt(
        address receiver,
        address market,
        uint exactSyIn,
        uint minPtOut,
        ApproxParams calldata guessPtOut,
        LimitOrderData calldata limit
    ) external returns (uint netPtOut, uint netSyFee);

    function swapExactPtForToken(
        address receiver,
        address market,
        uint exactPtIn,
        TokenOutput calldata output,
        LimitOrderData calldata limit
    ) external returns (uint netTokenOut, uint netSyFee, uint netSyInterm);

    function swapExactPtForSy(
        address receiver,
        address market,
        uint exactPtIn,
        uint minSyOut,
        LimitOrderData calldata limit
    ) external returns (uint netSyOut, uint netSyFee);
}
