// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILbPairV2 {
    function approveForAll(address spender, bool approved) external;

    function balanceOf(address account, uint256 id)
    external
    view
    returns (uint256);

    function balanceOfBatch(address[] memory accounts, uint256[] memory ids)
    external
    view
    returns (uint256[] memory batchBalances);

    function batchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts
    ) external;

    function burn(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amountsToBurn
    ) external returns (bytes32[] memory amounts);

    function collectProtocolFees()
    external
    returns (bytes32 collectedProtocolFees);

    function flashLoan(
        address receiver,
        bytes32 amounts,
        bytes memory data
    ) external;

    function forceDecay() external;

    function getActiveId() external view returns (uint24 activeId);

    function getBin(uint24 id)
    external
    view
    returns (uint128 binReserveX, uint128 binReserveY);

    function getBinStep() external pure returns (uint16);

    function getFactory() external view returns (address factory);

    function getIdFromPrice(uint256 price) external pure returns (uint24 id);

    function getLBHooksParameters() external view returns (bytes32);

    function getNextNonEmptyBin(bool swapForY, uint24 id)
    external
    view
    returns (uint24 nextId);

    function getOracleParameters()
    external
    view
    returns (
        uint8 sampleLifetime,
        uint16 size,
        uint16 activeSize,
        uint40 lastUpdated,
        uint40 firstTimestamp
    );

    function getOracleSampleAt(uint40 lookupTimestamp)
    external
    view
    returns (
        uint64 cumulativeId,
        uint64 cumulativeVolatility,
        uint64 cumulativeBinCrossed
    );

    function getPriceFromId(uint24 id) external pure returns (uint256 price);

    function getProtocolFees()
    external
    view
    returns (uint128 protocolFeeX, uint128 protocolFeeY);

    function getReserves()
    external
    view
    returns (uint128 reserveX, uint128 reserveY);

    function getStaticFeeParameters()
    external
    view
    returns (
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulator
    );

    function getSwapIn(uint128 amountOut, bool swapForY)
    external
    view
    returns (
        uint128 amountIn,
        uint128 amountOutLeft,
        uint128 fee
    );

    function getSwapOut(uint128 amountIn, bool swapForY)
    external
    view
    returns (
        uint128 amountInLeft,
        uint128 amountOut,
        uint128 fee
    );

    function getTokenX() external view returns (address tokenX);

    function getTokenY() external view returns (address tokenY);

    function getVariableFeeParameters()
    external
    view
    returns (
        uint24 volatilityAccumulator,
        uint24 volatilityReference,
        uint24 idReference,
        uint40 timeOfLastUpdate
    );

    function implementation() external view returns (address);

    function increaseOracleLength(uint16 newLength) external;

    function initialize(
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulator,
        uint24 activeId
    ) external;

    function isApprovedForAll(address owner, address spender)
    external
    view
    returns (bool);

    function mint(
        address to,
        bytes32[] memory liquidityConfigs,
        address refundTo
    )
    external
    returns (
        bytes32 amountsReceived,
        bytes32 amountsLeft,
        uint256[] memory liquidityMinted
    );

    function name() external view returns (string memory);

    function setHooksParameters(
        bytes32 hooksParameters,
        bytes memory onHooksSetData
    ) external;

    function setStaticFeeParameters(
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulator
    ) external;

    function swap(bool swapForY, address to)
    external
    returns (bytes32 amountsOut);

    function symbol() external view returns (string memory);

    function totalSupply(uint256 id) external view returns (uint256);
}
