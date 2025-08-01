// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTAdapterUpgradeable.sol";
import "../core/base/Controllable.sol";

contract StabilityOFTAdapter is Controllable, OFTAdapterUpgradeable {
    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    //region --------------------------------- Initializers
    constructor(address token_, address lzEndpoint_) OFTAdapterUpgradeable(token_, lzEndpoint_) {
        _disableInitializers();
    }

    function initialize(address platform_) public initializer {
        address _delegate = IPlatform(platform_).governance(); // todo

        __Controllable_init(platform_);
        __OFTAdapter_init(_delegate);
        __Ownable_init(_delegate);
    }
    //endregion --------------------------------- Initializers

    function _checkOwner() internal view override {
        _requireGovernanceOrMultisig(); // todo
    }
}
