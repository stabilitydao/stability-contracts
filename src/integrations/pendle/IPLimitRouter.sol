// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

interface IPLimitOrderType {
    enum OrderType {
        SY_FOR_PT,
        PT_FOR_SY,
        SY_FOR_YT,
        YT_FOR_SY
    }

    // Fixed-size order part with core information
    struct StaticOrder {
        uint salt;
        uint expiry;
        uint nonce;
        OrderType orderType;
        address token;
        address YT;
        address maker;
        address receiver;
        uint makingAmount;
        uint lnImpliedRate;
        uint failSafeRate;
    }

    struct FillResults {
        uint totalMaking;
        uint totalTaking;
        uint totalFee;
        uint totalNotionalVolume;
        uint[] netMakings;
        uint[] netTakings;
        uint[] netFees;
        uint[] notionalVolumes;
    }
}

struct Order {
    uint salt;
    uint expiry;
    uint nonce;
    IPLimitOrderType.OrderType orderType;
    address token;
    address YT;
    address maker;
    address receiver;
    uint makingAmount;
    uint lnImpliedRate;
    uint failSafeRate;
    bytes permit;
}

struct FillOrderParams {
    Order order;
    bytes signature;
    uint makingAmount;
}

interface IPLimitRouterCallback is IPLimitOrderType {
    function limitRouterCallback(
        uint actualMaking,
        uint actualTaking,
        uint totalFee,
        bytes memory data
    ) external returns (bytes memory);
}

interface IPLimitRouter is IPLimitOrderType {
    struct OrderStatus {
        uint128 filledAmount;
        uint128 remaining;
    }

    event OrderCanceled(address indexed maker, bytes32 indexed orderHash);

    event OrderFilledV2(
        bytes32 indexed orderHash,
        OrderType indexed orderType,
        address indexed YT,
        address token,
        uint netInputFromMaker,
        uint netOutputToMaker,
        uint feeAmount,
        uint notionalVolume,
        address maker,
        address taker
    );

    // event added on 2/1/2025
    event LnFeeRateRootsSet(address[] YTs, uint[] lnFeeRateRoots);

    // @dev actualMaking, actualTaking are in the SY form
    function fill(
        FillOrderParams[] memory params,
        address receiver,
        uint maxTaking,
        bytes calldata optData,
        bytes calldata callback
    ) external returns (uint actualMaking, uint actualTaking, uint totalFee, bytes memory callbackReturn);

    function feeRecipient() external view returns (address);

    function hashOrder(Order memory order) external view returns (bytes32);

    function cancelSingle(Order calldata order) external;

    function cancelBatch(Order[] calldata orders) external;

    function orderStatusesRaw(bytes32[] memory orderHashes)
        external
        view
        returns (uint[] memory remainingsRaw, uint[] memory filledAmounts);

    function orderStatuses(bytes32[] memory orderHashes)
        external
        view
        returns (uint[] memory remainings, uint[] memory filledAmounts);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function simulate(address target, bytes calldata data) external payable;

    function WNATIVE() external view returns (address);

    function _checkSig(
        Order memory order,
        bytes memory signature
    )
        external
        view
        returns (
            bytes32,
            /*orderHash*/
            uint,
            /*remainingMakerAmount*/
            uint
        ); /*filledMakerAmount*/

    /* --- Deprecated events --- */

    // deprecate on 7/1/2024, prior to official launch
    event OrderFilled(
        bytes32 indexed orderHash,
        OrderType indexed orderType,
        address indexed YT,
        address token,
        uint netInputFromMaker,
        uint netOutputToMaker,
        uint feeAmount,
        uint notionalVolume
    );
}
