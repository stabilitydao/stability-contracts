// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Controllable, IControllable} from "../core/base/Controllable.sol";
import {IMetaVault, IStabilityVault} from "../interfaces/IMetaVault.sol";

contract MockMetaVaultUpgrade is Controllable, IMetaVault {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "99.0.1";

    /// @inheritdoc IMetaVault
    uint public constant USD_THRESHOLD = 1e13;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct DepositAssetsVars {
        address targetVault;
        uint totalSupplyBefore;
        uint totalSharesBefore;
        uint len;
        uint[] balanceBefore;
        uint[] amountsConsumed;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // add this to be excluded from coverage report
    function test() public {}

    /// @inheritdoc IMetaVault
    function initialize(
        address,
        string memory,
        address,
        string memory,
        string memory,
        address[] memory,
        uint[] memory
    ) public initializer {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMetaVault
    function setTargetProportions(uint[] memory) external {}

    /// @inheritdoc IMetaVault
    function rebalance(uint[] memory, uint[] memory) external returns (uint[] memory proportions, int cost) {}

    /// @inheritdoc IMetaVault
    function addVault(address, uint[] memory) external {}

    /// @inheritdoc IMetaVault
    function removeVault(address) external {}

    /// @inheritdoc IStabilityVault
    function setName(string calldata newName) external {}

    /// @inheritdoc IStabilityVault
    function setSymbol(string calldata newSymbol) external {}

    /// @inheritdoc IMetaVault
    function emitAPR() external returns (uint sharePrice, int apr, uint lastStoredSharePrice, uint duration) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStabilityVault
    function depositAssets(address[] memory, uint[] memory, uint, address) external {}

    /// @inheritdoc IStabilityVault
    function withdrawAssets(address[] memory, uint, uint[] memory) external returns (uint[] memory) {}

    /// @inheritdoc IStabilityVault
    function withdrawAssets(address[] memory, uint, uint[] memory, address, address) external returns (uint[] memory) {}

    /// @inheritdoc IERC20
    function approve(address, uint) external returns (bool) {}

    /// @inheritdoc IERC20
    function transfer(address, uint) external pure returns (bool) {
        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address, address, uint) public pure returns (bool) {
        return true;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function lastBlockDefenseDisabled() external view returns (bool) {}

    function setLastBlockDefenseDisabled(bool isDisabled) external {}

    /// @inheritdoc IMetaVault
    function internalSharePrice()
        public
        view
        returns (uint sharePrice, int apr, uint storedSharePrice, uint storedTime)
    {}

    /// @inheritdoc IMetaVault
    function currentProportions() public view returns (uint[] memory) {}

    /// @inheritdoc IMetaVault
    function targetProportions() public view returns (uint[] memory) {}

    /// @inheritdoc IMetaVault
    function vaultForDeposit() public view returns (address target) {}

    /// @inheritdoc IMetaVault
    function assetsForDeposit() external view returns (address[] memory) {
        return IStabilityVault(vaultForDeposit()).assets();
    }

    /// @inheritdoc IMetaVault
    function vaultForWithdraw() public view returns (address target) {}

    /// @inheritdoc IMetaVault
    function assetsForWithdraw() external view returns (address[] memory) {}

    /// @inheritdoc IMetaVault
    function maxWithdrawAmountTx() external view returns (uint maxAmount) {}

    /// @inheritdoc IMetaVault
    function pegAsset() external view returns (address) {}

    /// @inheritdoc IMetaVault
    function vaults() external view returns (address[] memory) {}

    /// @inheritdoc IStabilityVault
    function assets() external view returns (address[] memory) {}

    /// @inheritdoc IStabilityVault
    function vaultType() external view returns (string memory) {}

    /// @inheritdoc IStabilityVault
    function previewDepositAssets(
        address[] memory assets_,
        uint[] memory amountsMax
    ) external view returns (uint[] memory, uint sharesOut, uint) {}

    /// @inheritdoc IStabilityVault
    function price() public view returns (uint, bool) {}

    /// @inheritdoc IStabilityVault
    function tvl() public view returns (uint, bool) {}

    /// @inheritdoc IERC20
    function totalSupply() public view returns (uint) {}

    /// @inheritdoc IERC20
    function balanceOf(address account) public view returns (uint) {}

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) external view returns (uint) {}

    /// @inheritdoc IERC20Metadata
    function name() external view returns (string memory) {}

    /// @inheritdoc IERC20Metadata
    function symbol() external view returns (string memory) {}

    /// @inheritdoc IERC20Metadata
    function decimals() external pure returns (uint8) {
        return 18;
    }

    function maxWithdraw(address account) external view virtual returns (uint amount) {}
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _checkProportions(uint[] memory) internal pure {}

    function _update(MetaVaultStorage storage, address, address, uint) internal {}

    function _beforeDepositOrWithdraw(MetaVaultStorage storage, address) internal {}

    function _checkLastBlockProtection(MetaVaultStorage storage $, address owner) internal view {}

    function _withdrawAssets(
        address[] memory,
        uint,
        uint[] memory,
        address,
        address
    ) internal returns (uint[] memory) {}

    function _maxAmountToWithdrawFromVault(address) internal view returns (uint, uint) {}

    function _burn(MetaVaultStorage storage $, address account, uint amountToBurn, uint sharesToBurn) internal {}

    function _mint(MetaVaultStorage storage $, address account, uint mintShares, uint mintBalance) internal {}

    function _usdAmountToMetaVaultBalance(uint usdAmount) internal view returns (uint) {}

    function _metaVaultBalanceToUsdAmount(uint amount) internal view returns (uint) {}

    function _amountToShares(uint amount, uint totalShares_, uint totalSupply_) internal pure returns (uint) {}

    function _spendAllowanceOrBlock(address owner, address spender, uint amount) internal {}

    function deposit(uint, address, uint) external returns (uint) {}

    function mint(uint, address, uint) external returns (uint) {}

    function withdraw(uint, address, address, uint) external returns (uint) {}

    function redeem(uint, address, address, uint) external returns (uint) {}

    function changeWhitelist(address addr, bool addToWhitelist) external {}

    function whitelisted(address addr) external view returns (bool) {}

    function setLastBlockDefenseDisabledTx(bool isDisabled) external {}

    function maxDeposit(address account) external view returns (uint[] memory maxAmounts) {}
}
