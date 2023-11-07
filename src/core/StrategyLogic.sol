// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

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
contract StrategyLogic is Controllable, ERC721EnumerableUpgradeable, IStrategyLogic {

    /// @dev Version of StrategyLogic implementation
    string internal constant _VERSION = '0.1.0';

    /// @dev Mapping between tokens and strategy logic ID
    mapping (uint tokenId => string strategyLogicId) public tokenStrategyLogic;

    mapping (uint tokenId => address account) internal _revenueReceiver;

    /// @dev This empty reserved space is put in place to allow future versions to add new.
    /// variables without shifting down storage in the inheritance chain.
    /// Total gap == 50 - storage slots used.
    uint[50 - 2] private __gap;

    function init(address platform_) external initializer {
        __Controllable_init(platform_);
        __ERC721_init("Strategy Logic", "STRATEGY");
    }

    function mint(address to, string memory strategyLogicId) external onlyFactory returns (uint tokenId) {
        tokenId = totalSupply();
        tokenStrategyLogic[tokenId] = strategyLogicId;
        _mint(to, tokenId);
    }

    function setRevenueReceiver(uint tokenId, address receiver) external {
        require(_ownerOf(tokenId) == msg.sender, "StrategyLogic: not owner");
        _revenueReceiver[tokenId] = receiver;
        emit SetRevenueReceiver(tokenId, receiver);
    }

    /// @inheritdoc IControllable
    function version() external pure returns (string memory) {
        return _VERSION;
    }

    function getRevenueReceiver(uint tokenId) external view returns (address receiver) {
        receiver = _revenueReceiver[tokenId];
        if (receiver == address(0)) {
            receiver = _ownerOf(tokenId);
        }
    }

    /// @dev Returns current token URI metadata
    /// @param tokenId Token ID to fetch URI for.
    function tokenURI(uint tokenId) public view override (ERC721Upgradeable, IERC721Metadata) returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "StrategyLogic: TOKEN_NOT_EXIST");
        StrategyData memory strategyData;
        strategyData.strategyId = tokenStrategyLogic[tokenId];
        IPlatform _platform = IPlatform(platform());
        IFactory factory = IFactory(_platform.factory());
        address implementation;
        (,implementation,,,,strategyData.strategyTokenId) = factory.strategyLogicConfig(keccak256(bytes(strategyData.strategyId)));
        strategyData.strategyExtra = IStrategy(implementation).extra();
        return StrategyLogicLib.tokenURI(strategyData, _platform.PLATFORM_VERSION(), _platform.getPlatformSettings());
    }
}
