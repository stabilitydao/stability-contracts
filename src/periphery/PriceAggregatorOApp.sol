// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    OAppUpgradeable,
    Origin,
    MessagingFee
} from "@layerzerolabs/oapp-evm-upgradeable/contracts/oapp/OAppUpgradeable.sol";
import {IControllable, Controllable} from "../core/base/Controllable.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {OAppEncodingLib} from "./libs/OAppEncodingLib.sol";
import {IPriceAggregatorOApp} from "../interfaces/IPriceAggregatorOApp.sol";
import {IPriceAggregator} from "../interfaces/IPriceAggregator.sol";

/// @notice Get price of given entity (vault or asset) from PriceAggregator
/// and send it to BridgetPriceOracle on the given chain through LayerZero OApp
/// by command of whitelisted address (backend). Each call sends single price
/// as packet of price value (usd, decimals 18) and timestamp of the price update.
contract PriceAggregatorOApp is Controllable, OAppUpgradeable, IPriceAggregatorOApp {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.PriceAggregatorOApp")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant _PRICE_AGGREGATOR_OAPP_STORAGE_LOCATION =
        0x03c24ae0f93ab26cb98c742598023b6422f9f4ca86d7754aa8be1070fd418e00;

    /// @custom:storage-location erc7201:stability.PriceAggregatorOApp
    struct PriceAggregatorOAppStorage {
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

    /// @inheritdoc IPriceAggregatorOApp
    function initialize(address platform_, address entity_, address delegate_) public initializer {
        address _owner = IPlatform(platform_).multisig();

        __Controllable_init(platform_);
        __OApp_init(delegate_ == address(0) ? _owner : delegate_);
        __Ownable_init(_owner);

        getPriceAggregatorOAppStorage().entity = entity_;
    }

    //endregion --------------------------------- Initializers

    //region --------------------------------- View
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                             VIEW                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IPriceAggregatorOApp
    function entity() external view returns (address) {
        return getPriceAggregatorOAppStorage().entity;
    }

    /// @inheritdoc IPriceAggregatorOApp
    function isWhitelisted(address caller) external view returns (bool) {
        PriceAggregatorOAppStorage storage $ = getPriceAggregatorOAppStorage();
        return $.whitelist[caller];
    }

    /// @inheritdoc IPriceAggregatorOApp
    function quotePriceMessage(
        uint32 dstEid_,
        bytes memory options_,
        bool payInLzToken_
    ) public view returns (MessagingFee memory fee) {
        PriceAggregatorOAppStorage storage $ = getPriceAggregatorOAppStorage();
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

    /// @inheritdoc IPriceAggregatorOApp
    function changeWhitelist(address caller, bool whitelisted) external onlyGovernanceOrMultisig {
        PriceAggregatorOAppStorage storage $ = getPriceAggregatorOAppStorage();
        $.whitelist[caller] = whitelisted;

        emit ChangeWhitelist(caller, whitelisted);
    }

    /// @inheritdoc IPriceAggregatorOApp
    function sendPriceMessage(uint32 dstEid_, bytes memory options_, MessagingFee memory fee_) external payable {
        PriceAggregatorOAppStorage storage $ = getPriceAggregatorOAppStorage();
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
    function getPriceAggregatorOAppStorage() internal pure returns (PriceAggregatorOAppStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _PRICE_AGGREGATOR_OAPP_STORAGE_LOCATION
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
