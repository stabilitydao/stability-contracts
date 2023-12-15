// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "./base/Controllable.sol";
import "./libs/VaultManagerLib.sol";
import "./libs/VaultTypeLib.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/IRVault.sol";
import "../interfaces/IManagedVault.sol";

/// @notice The vaults are assembled at the factory by users through UI.
///         Deployment rights of a vault are tokenized in VaultManager NFT.
///         The holders of these tokens receive a share of the vault revenue and can manage vault if possible.
/// @dev Rewards transfers to token owner or revenue receiver address managed by token owner.
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
contract VaultManager is Controllable, ERC721EnumerableUpgradeable, IVaultManager {
    //region ----- Constants -----

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.VaultManager")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant VAULTMANAGER_STORAGE_LOCATION =
        0xdc91b926f64ceb646f47da4c796e445221faf197fcaee29e875daf63dcf64e00;

    //endregion ----- Constants -----

    //region ----- Storage -----

    /// @custom:storage-location erc7201:stability.VaultManager
    struct VaultManagerStorage {
        /// @inheritdoc IVaultManager
        mapping(uint tokenId => address vault) tokenVault;
        mapping(uint tokenId => address account) _revenueReceiver;
    }

    //endregion -- Storage -----

    function init(address platform_) external initializer {
        __Controllable_init(platform_);
        __ERC721_init("Stability Vault", "VAULT");
    }

    /// @inheritdoc IVaultManager
    //slither-disable-next-line reentrancy-events
    function changeVaultParams(uint tokenId, address[] memory addresses, uint[] memory nums) external {
        VaultManagerStorage storage $ = _getStorage();
        _requireOwner(tokenId);
        address vault = $.tokenVault[tokenId];
        IManagedVault(vault).changeParams(addresses, nums);
        emit ChangeVaultParams(tokenId, addresses, nums);
    }

    /// @inheritdoc IVaultManager
    function mint(address to, address vault) external onlyFactory returns (uint tokenId) {
        VaultManagerStorage storage $ = _getStorage();
        tokenId = totalSupply();
        $.tokenVault[tokenId] = vault;
        _mint(to, tokenId);
    }

    /// @inheritdoc IVaultManager
    function setRevenueReceiver(uint tokenId, address receiver) external {
        VaultManagerStorage storage $ = _getStorage();
        _requireOwner(tokenId);
        $._revenueReceiver[tokenId] = receiver;
        emit SetRevenueReceiver(tokenId, receiver);
    }

    /// @dev Returns current token URI metadata
    /// @param tokenId Token ID to fetch URI for.
    function tokenURI(uint tokenId) public view override(ERC721Upgradeable, IERC721Metadata) returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) {
            revert NotExist();
        }
        VaultManagerStorage storage $ = _getStorage();
        //slither-disable-next-line uninitialized-local
        VaultData memory vaultData;
        IPlatform _platform = IPlatform(platform());
        IFactory factory = IFactory(_platform.factory());
        vaultData.vault = $.tokenVault[tokenId];
        IVault vault = IVault(vaultData.vault);
        IStrategy strategy = vault.strategy();
        // slither-disable-next-line unused-return
        (vaultData.sharePrice,) = vault.price();
        // slither-disable-next-line unused-return
        (vaultData.tvl,) = vault.tvl();
        // slither-disable-next-line unused-return
        (vaultData.totalApr, vaultData.strategyApr,,) = vault.getApr();
        vaultData.vaultType = vault.vaultType();
        vaultData.name = IERC20Metadata(vaultData.vault).name();
        vaultData.vaultExtra = vault.extra();
        vaultData.strategyExtra = strategy.extra();

        address bbAsset = address(0);
        if (keccak256(bytes(vaultData.vaultType)) == keccak256(bytes(VaultTypeLib.REWARDING))) {
            address[] memory rts = IRVault(vaultData.vault).rewardTokens();
            vaultData.rewardAssetsSymbols = CommonLib.getSymbols(rts);
            bbAsset = rts[0];
        }

        // slither-disable-next-line unused-return
        (vaultData.strategyId,, vaultData.assetsSymbols, vaultData.strategySpecific, vaultData.symbol) =
            factory.getStrategyData(vaultData.vaultType, address(strategy), bbAsset);

        vaultData.strategyTokenId = factory.strategyLogicConfig(keccak256(bytes(vaultData.strategyId))).tokenId;

        return VaultManagerLib.tokenURI(vaultData, _platform.platformVersion(), _platform.getPlatformSettings());
    }

    /// @inheritdoc IVaultManager
    //slither-disable-next-line calls-loop
    function vaults()
        external
        view
        returns (
            address[] memory vaultAddress,
            string[] memory name,
            string[] memory symbol,
            string[] memory vaultType,
            string[] memory strategyId,
            uint[] memory sharePrice,
            uint[] memory tvl,
            uint[] memory totalApr,
            uint[] memory strategyApr,
            string[] memory strategySpecific
        )
    {
        VaultManagerStorage storage $ = _getStorage();
        uint len = totalSupply();
        vaultAddress = new address[](len);
        name = new string[](len);
        symbol = new string[](len);
        vaultType = new string[](len);
        strategyId = new string[](len);
        sharePrice = new uint[](len);
        totalApr = new uint[](len);
        strategyApr = new uint[](len);
        strategySpecific = new string[](len);
        tvl = new uint[](len);
        // nosemgrep
        for (uint i; i < len; ++i) {
            vaultAddress[i] = $.tokenVault[i];
            IVault vault = IVault(vaultAddress[i]);
            name[i] = IERC20Metadata(vaultAddress[i]).name();
            symbol[i] = IERC20Metadata(vaultAddress[i]).symbol();
            vaultType[i] = vault.vaultType();
            IStrategy strategy = vault.strategy();
            strategyId[i] = strategy.strategyLogicId();
            //slither-disable-next-line unused-return
            (strategySpecific[i],) = strategy.getSpecificName();
            //slither-disable-next-line unused-return
            (totalApr[i], strategyApr[i],,) = vault.getApr();
            //slither-disable-next-line unused-return
            (sharePrice[i],) = vault.price();
            //slither-disable-next-line unused-return
            (tvl[i],) = vault.tvl();
        }
    }

    /// @inheritdoc IVaultManager
    function vaultAddresses() external view returns (address[] memory vaultAddress) {
        VaultManagerStorage storage $ = _getStorage();
        uint len = totalSupply();
        vaultAddress = new address[](len);
        // nosemgrep
        for (uint i; i < len; ++i) {
            vaultAddress[i] = $.tokenVault[i];
        }
    }

    /// @inheritdoc IVaultManager
    function vaultInfo(address vault)
        external
        view
        returns (
            address strategy,
            address[] memory strategyAssets,
            address underlying,
            address[] memory assetsWithApr,
            uint[] memory assetsAprs,
            uint lastHardWork
        )
    {
        IVault v = IVault(vault);
        IStrategy s = v.strategy();
        strategy = address(s);
        strategyAssets = s.assets();
        underlying = s.underlying();
        //slither-disable-next-line unused-return
        (,, assetsWithApr, assetsAprs) = v.getApr();
        lastHardWork = s.lastHardWork();
    }

    /// @inheritdoc IVaultManager
    function getRevenueReceiver(uint tokenId) external view returns (address receiver) {
        VaultManagerStorage storage $ = _getStorage();
        receiver = $._revenueReceiver[tokenId];
        if (receiver == address(0)) {
            receiver = _ownerOf(tokenId);
        }
    }

    /// @inheritdoc IVaultManager
    function tokenVault(uint tokenId) external view returns (address vault) {
        VaultManagerStorage storage $ = _getStorage();
        vault = $.tokenVault[tokenId];
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721EnumerableUpgradeable, IERC165, Controllable)
        returns (bool)
    {
        return interfaceId == type(IVaultManager).interfaceId || interfaceId == type(IControllable).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function _requireOwner(uint tokenId) internal view {
        if (_ownerOf(tokenId) != msg.sender) {
            revert NotTheOwner();
        }
    }

    //region ----- Internal logic -----

    function _getStorage() private pure returns (VaultManagerStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := VAULTMANAGER_STORAGE_LOCATION
        }
    }

    //endregion ----- Internal logic -----
}
