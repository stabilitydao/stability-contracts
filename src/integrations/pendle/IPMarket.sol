// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {IStandardizedYield} from "./IStandardizedYield.sol";
import {IPPrincipalToken} from "./IPPrincipalToken.sol";
import {IPYieldToken} from "./IPYieldToken.sol";

struct MarketState {
    int totalPt;
    int totalSy;
    int totalLp;
    address treasury;
    /// immutable variables ///
    int scalarRoot;
    uint expiry;
    /// fee data ///
    uint lnFeeRateRoot;
    uint reserveFeePercent; // base 100
    /// last trade data ///
    uint lastLnImpliedRate;
}

interface IPMarket {
    event Mint(address indexed receiver, uint netLpMinted, uint netSyUsed, uint netPtUsed);

    event Burn(address indexed receiverSy, address indexed receiverPt, uint netLpBurned, uint netSyOut, uint netPtOut);

    event Swap(
        address indexed caller, address indexed receiver, int netPtOut, int netSyOut, uint netSyFee, uint netSyToReserve
    );

    event UpdateImpliedRate(uint indexed timestamp, uint lnLastImpliedRate);

    event IncreaseObservationCardinalityNext(
        uint16 observationCardinalityNextOld, uint16 observationCardinalityNextNew
    );

    function mint(
        address receiver,
        uint netSyDesired,
        uint netPtDesired
    ) external returns (uint netLpOut, uint netSyUsed, uint netPtUsed);

    function burn(
        address receiverSy,
        address receiverPt,
        uint netLpToBurn
    ) external returns (uint netSyOut, uint netPtOut);

    function swapExactPtForSy(
        address receiver,
        uint exactPtIn,
        bytes calldata data
    ) external returns (uint netSyOut, uint netSyFee);

    function swapSyForExactPt(
        address receiver,
        uint exactPtOut,
        bytes calldata data
    ) external returns (uint netSyIn, uint netSyFee);

    function redeemRewards(address user) external returns (uint[] memory);

    function readState(address router) external view returns (MarketState memory market);

    function observe(uint32[] memory secondsAgos) external view returns (uint216[] memory lnImpliedRateCumulative);

    function increaseObservationsCardinalityNext(uint16 cardinalityNext) external;

    function readTokens() external view returns (IStandardizedYield _SY, IPPrincipalToken _PT, IPYieldToken _YT);

    function getRewardTokens() external view returns (address[] memory);

    function isExpired() external view returns (bool);

    function expiry() external view returns (uint);

    function observations(uint index)
        external
        view
        returns (uint32 blockTimestamp, uint216 lnImpliedRateCumulative, bool initialized);

    function _storage()
        external
        view
        returns (
            int128 totalPt,
            int128 totalSy,
            uint96 lastLnImpliedRate,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext
        );
}
