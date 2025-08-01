// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";
import "../core/base/Controllable.sol";

contract StabilityOFT is Controllable, OFTUpgradeable {
    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    //region --------------------------------- Initializers
    constructor(address lzEndpoint_) OFTUpgradeable(lzEndpoint_) {
        _disableInitializers();
    }

    function initialize(address platform_, string memory _name, string memory _symbol) public initializer {
        address _delegate = IPlatform(platform_).governance(); // todo

        __Controllable_init(platform_);
        __OFT_init(_name, _symbol, _delegate);
        __Ownable_init(_delegate);
    }
    //endregion --------------------------------- Initializers

    function _checkOwner() internal view override {
        _requireGovernanceOrMultisig(); // todo
    }
}
