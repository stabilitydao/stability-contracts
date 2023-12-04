// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "./base/Controllable.sol";
import "./libs/StrategyLogicLib.sol";
import "../interfaces/IStrategyLogic.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/IStrategy.sol";

/// @notice The developed strategy logic is tokenized into StrategyLogic NFT.
///         The holders of these tokens receive a share of the revenue received in all vaults using this strategy logic.
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
contract StrategyLogic is Controllable, ERC721EnumerableUpgradeable, IStrategyLogic {
    //region ----- Constants -----

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.StrategyLogic")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant STRATEGYLOGIC_STORAGE_LOCATION =
        0x6e9c56d392637a53a86185fd13e3616947723bd87b0aa4ceb3748b95873c8c00;

    //endregion ----- Constants -----

    //region ----- Storage -----

    /// @custom:storage-location erc7201:stability.StrategyLogic
    struct StrategyLogicStorage {
        /// @dev Mapping between tokens and strategy logic ID
        mapping(uint tokenId => string strategyLogicId) tokenStrategyLogic;
        mapping(uint tokenId => address account) _revenueReceiver;
    }

    //endregion ----- Storage -----

    function init(address platform_) external initializer {
        __Controllable_init(platform_);
        __ERC721_init("Strategy Logic", "STRATEGY");
    }

    /// @inheritdoc IStrategyLogic
    function mint(address to, string memory strategyLogicId) external onlyFactory returns (uint tokenId) {
        StrategyLogicStorage storage $ = _getStorage();
        tokenId = totalSupply();
        $.tokenStrategyLogic[tokenId] = strategyLogicId;
        _mint(to, tokenId);
    }

    /// @inheritdoc IStrategyLogic
    function setRevenueReceiver(uint tokenId, address receiver) external {
        if (_ownerOf(tokenId) != msg.sender) {
            revert NotTheOwner();
        }
        StrategyLogicStorage storage $ = _getStorage();
        $._revenueReceiver[tokenId] = receiver;
        emit SetRevenueReceiver(tokenId, receiver);
    }

    /// @inheritdoc IStrategyLogic
    function getRevenueReceiver(uint tokenId) external view returns (address receiver) {
        StrategyLogicStorage storage $ = _getStorage();
        receiver = $._revenueReceiver[tokenId];
        if (receiver == address(0)) {
            receiver = _ownerOf(tokenId);
        }
    }

    /// @dev Returns current token URI metadata
    /// @param tokenId Token ID to fetch URI for.
    function tokenURI(uint tokenId) public view override(ERC721Upgradeable, IERC721Metadata) returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) {
            revert NotExist();
        }
        StrategyLogicStorage storage $ = _getStorage();
        //slither-disable-next-line uninitialized-local
        StrategyData memory strategyData;
        strategyData.strategyId = $.tokenStrategyLogic[tokenId];
        IPlatform _platform = IPlatform(platform());
        IFactory factory = IFactory(_platform.factory());
        IFactory.StrategyLogicConfig memory strategyConfig =
            factory.strategyLogicConfig(keccak256(bytes(strategyData.strategyId)));
        address implementation = strategyConfig.implementation;
        strategyData.strategyTokenId = strategyConfig.tokenId;
        strategyData.strategyExtra = IStrategy(implementation).extra();
        return StrategyLogicLib.tokenURI(strategyData, _platform.platformVersion(), _platform.getPlatformSettings());
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721EnumerableUpgradeable, IERC165, Controllable)
        returns (bool)
    {
        return interfaceId == type(IStrategyLogic).interfaceId || interfaceId == type(IControllable).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IStrategyLogic
    function tokenStrategyLogic(uint tokenId) external view returns (string memory strategyLogicId) {
        StrategyLogicStorage storage $ = _getStorage();
        strategyLogicId = $.tokenStrategyLogic[tokenId];
    }

    //region ----- Internal logic -----

    function _getStorage() private pure returns (StrategyLogicStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := STRATEGYLOGIC_STORAGE_LOCATION
        }
    }

    //endregion ----- Internal logic -----
}
