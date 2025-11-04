// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {
    OAppUpgradeable,
    Origin,
    MessagingFee
} from "@layerzerolabs/oapp-evm-upgradeable/contracts/oapp/OAppUpgradeable.sol";
import {IControllable, Controllable} from "../core/base/Controllable.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {OAppEncodingLib} from "./libs/OAppEncodingLib.sol";
import {IPriceAggregatorQApp} from "../interfaces/IPriceAggregatorQApp.sol";
import {IPriceAggregator} from "../interfaces/IPriceAggregator.sol";

/// @notice Get price of given entity (vault or asset) from PriceAggregator
/// and send it to BridgetPriceOracle on the given chain through LayerZero OApp
/// by command of whitelisted address (backend). Each call sends single price
/// as packet of price value (usd, decimals 18) and timestamp of the price update.
contract PriceAggregatorQApp is Controllable, OAppUpgradeable, IPriceAggregatorQApp {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.PriceAggregatorQApp")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant _PRICE_AGGREGATOR_QAPP_STORAGE_LOCATION =
        0x4ae4669e0847cbd8ac112b506c168d94d95debd740cba7df24fb81bf6d925200;

    /// @custom:storage-location erc7201:stability.PriceAggregatorQApp
    struct PriceAggregatorQAppStorage {
        address entity;

        /// @notice All users trusted to send price updates
        mapping(address sender => bool) whitelist;
    }

    //region --------------------------------- Initializers
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initialize with Endpoint V2
    constructor(address lzEndpoint_) OAppUpgradeable(lzEndpoint_) {
        _disableInitializers();
    }

    function initialize(address platform_, address entity_) public initializer {
        address _delegate = IPlatform(platform_).multisig();

        __Controllable_init(platform_);
        __OApp_init(_delegate);
        __Ownable_init(_delegate);

        getPriceAggregatorQAppStorage().entity = entity_;
    }

    //endregion --------------------------------- Initializers

    //region --------------------------------- View
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                             VIEW                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IPriceAggregatorQApp
    function entity() external view returns (address) {
        return getPriceAggregatorQAppStorage().entity;
    }

    /// @inheritdoc IPriceAggregatorQApp
    function isWhitelisted(address caller) external view returns (bool) {
        PriceAggregatorQAppStorage storage $ = getPriceAggregatorQAppStorage();
        return $.whitelist[caller];
    }

    /// @inheritdoc IPriceAggregatorQApp
    function quotePriceMessage(
        uint32 dstEid_,
        bytes memory options_,
        bool payInLzToken_
    ) public view returns (MessagingFee memory fee) {
        PriceAggregatorQAppStorage storage $ = getPriceAggregatorQAppStorage();
        // combineOptions (from OAppOptionsType3) merges enforced options set by the contract owner
        // with any additional execution options provided by the caller
        (bytes memory message,,) = _getPriceMessage($.entity);
        fee = _quote(dstEid_, message, options_, payInLzToken_);
    }

    //endregion --------------------------------- View

    //region --------------------------------- Actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   Restricted actions                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IPriceAggregatorQApp
    function changeWhitelist(address caller, bool whitelisted) external onlyOperator {
        PriceAggregatorQAppStorage storage $ = getPriceAggregatorQAppStorage();
        $.whitelist[caller] = whitelisted;

        emit ChangeWhitelist(caller, whitelisted);
    }

    /// @inheritdoc IPriceAggregatorQApp
    function sendPriceMessage(uint32 dstEid_, bytes memory options_, MessagingFee memory fee_) external payable {
        PriceAggregatorQAppStorage storage $ = getPriceAggregatorQAppStorage();
        require($.whitelist[msg.sender], NotWhitelisted());

        (bytes memory message, uint price, uint timestamp) = _getPriceMessage($.entity);
        _lzSend(dstEid_, message, options_, fee_, payable(msg.sender));

        emit SendPriceMessage(dstEid_, price, timestamp);
    }

    //endregion --------------------------------- Actions

    //region --------------------------------- Overrides
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      Overrides                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev This QApp does not expect to receive messages
    function _lzReceive(
        Origin calldata,
        /*_origin*/
        bytes32,
        /*_guid*/
        bytes calldata,
        /*_message*/
        address,
        /*_executor*/
        bytes calldata /*_extraData*/
    ) internal pure override {
        revert UnsupportedOperation();
    }

    //endregion --------------------------------- Overrides

    //region --------------------------------- Internal logic
    function getPriceAggregatorQAppStorage() internal pure returns (PriceAggregatorQAppStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _PRICE_AGGREGATOR_QAPP_STORAGE_LOCATION
        }
    }

    function _getPriceMessage(address entity_)
        internal
        view
        returns (bytes memory message, uint price, uint timestamp)
    {
        // slither-disable-next-line unused-return
        (price, timestamp,) = IPriceAggregator(IPlatform(platform()).priceAggregator()).price(entity_);
        return (OAppEncodingLib.packPriceUsd18(price, timestamp), price, timestamp);
    }
    //endregion --------------------------------- Internal logic
}
