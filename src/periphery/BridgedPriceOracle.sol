// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {OAppUpgradeable, Origin} from "@layerzerolabs/oapp-evm-upgradeable/contracts/oapp/OAppUpgradeable.sol";
import {IControllable, Controllable} from "../core/base/Controllable.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {OAppEncodingLib} from "./libs/OAppEncodingLib.sol";
import {IBridgedPriceOracle} from "../interfaces/IBridgedPriceOracle.sol";
import {IAggregatorInterfaceMinimal} from "../integrations/chainlink/IAggregatorInterfaceMinimal.sol";

contract BridgedPriceOracle is Controllable, OAppUpgradeable, IBridgedPriceOracle {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.BridgedPriceOracle")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant _BRIDGED_PRICE_ORACLE_STORAGE_LOCATION =
        0x7de84bf9d24250450323fa11c7039f1c170849cf600decfdbf5e505497ab9b00;

    /// @dev Single slot
    struct PriceInfo {
        /// @notice Last price received from price aggregator in USD, 18 decimals
        uint160 price;

        /// @notice Last time of {price} update
        uint64 timestamp;
    }

    /// @custom:storage-location erc7201:stability.BridgedPriceOracle
    struct BridgedPriceOracleStorage {
        /// @notice Last stored price
        PriceInfo lastPriceInfo;
    }

    //region --------------------------------- Initializers
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initialize with Endpoint V2
    constructor(address lzEndpoint_) OAppUpgradeable(lzEndpoint_) {
        _disableInitializers();
    }

    function initialize(address platform_) public initializer {
        address _delegate = IPlatform(platform_).multisig();

        __Controllable_init(platform_);
        __OApp_init(_delegate);
        __Ownable_init(_delegate);
    }

    //endregion --------------------------------- Initializers

    //region --------------------------------- View
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                             VIEW                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBridgedPriceOracle
    function getPriceUsd18() external view returns (uint price, uint priceTimestamp) {
        PriceInfo memory priceInfo = getBridgedPriceOracleStorage().lastPriceInfo;
        return (priceInfo.price, priceInfo.timestamp);
    }

    /// @inheritdoc IAggregatorInterfaceMinimal
    function latestAnswer() external view returns (int) {
        // assume here that price aggregator always returns price in USD with 18 decimals

        // slither-disable-next-line unused-return
        uint price = getBridgedPriceOracleStorage().lastPriceInfo.price;

        return int(price / 10 ** 10);
    }

    /// @inheritdoc IAggregatorInterfaceMinimal
    function decimals() external pure returns (uint8) {
        return 8;
    }

    //endregion --------------------------------- View

    //region --------------------------------- Actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   QApp receive logic                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Invoked by OAppReceiver when EndpointV2.lzReceive is called
    /// @dev origin_ Metadata (source chain, sender address, nonce)
    /// @dev guid_ Global unique ID for tracking this message
    /// @param message_ ABI-encoded bytes (the string we sent earlier)
    /// @dev executor_ Executor address that delivered the message
    /// @dev extraData_ Additional data from the Executor (unused here)
    function _lzReceive(
        Origin calldata,
        /*origin_*/
        bytes32,
        /*guid_*/
        bytes calldata message_,
        address,
        /*executor_*/
        bytes calldata /*extraData_*/
    ) internal override {
        BridgedPriceOracleStorage storage $ = getBridgedPriceOracleStorage();
        (uint16 messageFormat, uint160 price, uint64 timestamp) = OAppEncodingLib.unpackPriceUsd18(message_);

        require(messageFormat == OAppEncodingLib.MESSAGE_FORMAT_PRICE_USD18_1, InvalidMessageFormat());

        $.lastPriceInfo = PriceInfo({price: price, timestamp: timestamp});

        emit PriceUpdated(price, block.timestamp);
    }

    //endregion --------------------------------- Actions

    //region --------------------------------- Internal logic
    function getBridgedPriceOracleStorage() internal pure returns (BridgedPriceOracleStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _BRIDGED_PRICE_ORACLE_STORAGE_LOCATION
        }
    }
    //endregion --------------------------------- Internal logic
}
