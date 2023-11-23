// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../core/base/Controllable.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IPriceReader.sol";

contract MockVaultUpgrade is Controllable, ERC20Upgradeable, IVault {
    using SafeERC20 for IERC20;

    string public constant VERSION = '10.99.99';
    address internal constant DEAD_ADDRESS = 0xdEad000000000000000000000000000000000000;

    IStrategy public strategy;
    uint public maxSupply;
    uint public tokenId;

    // add this to be excluded from coverage report
    function test() public {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        VaultInitializationData memory vaultInitializationData
    ) initializer public {}

    function extra() external view returns (bytes32) {}

    function VAULT_TYPE() external view returns (string memory) {}

    function UNIQUE_INIT_ADDRESSES() external view returns (uint) {}

    function UNIQUE_INIT_NUMS() external view returns (uint) {}

    function price() external view returns (uint price_, bool trusted_) {}

    function tvl() external view returns (uint tvl_, bool trusted_) {}

    function minTVL() external view returns (uint) {}

    function setMaxSupply(uint maxShares) external {}

    function doHardWorkOnDeposit() external view returns(bool) {}

    function previewDepositAssets(address[] memory assets_, uint[] memory amounts) external pure returns (uint[] memory amountsConsumed, uint sharesOut, uint valueOut) {}

    function getApr() external view returns (uint totalApr, uint strategyApr, address[] memory assetsWithApr, uint[] memory assetsAprs) {}

    function depositAssets(address[] memory assets_, uint[] memory amounts, uint minSharesOut, address receiver) external {}

    function depositUnderlying(uint amount, uint minSharesOut) external {}

    function withdrawAssets(address[] memory assets_, uint amount, uint[] memory minAssetAmountsOut) external {}

    function withdrawUnderlying(uint amountShares, uint minAmountOut) external {}

    function doHardWork() external {}

    /// @inheritdoc IVault
    function setDoHardWorkOnDeposit(bool value) external onlyGovernanceOrMultisig {}

    function setMinTVL(uint value) external {}

    function _mintShares(uint totalSupply_, uint value_, uint totalValue_, uint[] memory amountsConsumed, uint minSharesOut) internal returns (uint mintAmount) {}

    function _calcMintShares(uint totalSupply_, uint value_, uint totalValue_, uint[] memory amountsConsumed) internal view returns (uint mintAmount, uint initialShares) {}
}
