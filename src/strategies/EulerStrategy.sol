// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./base/ERC4626StrategyBase.sol";
import "./base/EulerLib.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {IVault} from "../interfaces/IVault.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {StrategyLib} from "./libs/StrategyLib.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";

/// @title Earns APR by lending assets on Euler
/// @author dvpublic (https://github.com/dvpublic)
contract EulerStrategy is ERC4626StrategyBase {
  using SafeERC20 for IERC20;

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                         CONSTANTS                          */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @inheritdoc IControllable
  string public constant VERSION = "1.0.0";

  // keccak256(abi.encode(uint256(keccak256("erc7201:stability.EulerStrategy")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 private constant EULER_STRATEGY_STORAGE_LOCATION =
  0x86c37fbe4b124a45ab9f98437f581e711a86ea1d20d8d21943d427c270d25e00; // todo

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                       INITIALIZATION                       */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @inheritdoc IStrategy
  function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
    if (addresses.length != 3 || nums.length != 0 || ticks.length != 0) {
      revert IControllable.IncorrectInitParams();
    }
    __ERC4626StrategyBase_init(StrategyIdLib.SILO, addresses[0], addresses[1], addresses[2]);
  }

  //region ----------------------- View functions
  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                       VIEW FUNCTIONS                       */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @inheritdoc IStrategy
  function strategyLogicId() public pure override returns (string memory) {
    return StrategyIdLib.EULER;
  }

  /// @inheritdoc IStrategy
  function description() external view returns (string memory) {
    StrategyBaseStorage storage $base = _getStrategyBaseStorage();
    return EulerLib.generateDescription($base._underlying);
  }

  /// @inheritdoc IStrategy
  function extra() external pure returns (bytes32) {
    //slither-disable-next-line too-many-digits
    return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x00d395), bytes3(0x000000)));
  }

  /// @inheritdoc IStrategy
  function getSpecificName() external view override returns (string memory, bool) {
    StrategyBaseStorage storage $base = _getStrategyBaseStorage();
    string memory shortAddr = EulerLib.shortAddress($base._underlying);
    return (string.concat(IERC20Metadata(IEulerVault($base._underlying).asset()).symbol(), " ", shortAddr), true);
  }

  /// @inheritdoc IStrategy
  function supportedVaultTypes() external pure override returns (string[] memory types) {
    types = new string[](1);
    types[0] = VaultTypeLib.COMPOUNDING;
  }

  /// @inheritdoc IStrategy
  function initVariants(address platform_)
  public
  view
  returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
  {
    IFactory.StrategyAvailableInitParams memory params =
                IFactory(IPlatform(platform_).factory()).strategyAvailableInitParams(keccak256(bytes(strategyLogicId())));
    uint len = params.initAddresses.length;
    variants = new string[](len);
    addresses = new address[](len);
    nums = new uint[](0);
    ticks = new int24[](0);
    for (uint i; i < len; ++i) {
      variants[i] = EulerLib.generateDescription(params.initAddresses[i]);
      addresses[i] = params.initAddresses[i];
    }
  }

  /// @inheritdoc IStrategy
  function isHardWorkOnDepositAllowed() external pure returns (bool) {
    return true;
  }

  //endregion ----------------------- View functions

  //region ----------------------- Strategy base
  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                       STRATEGY BASE                        */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @inheritdoc ERC4626StrategyBase
  //slither-disable-next-line unused-return
  function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
    StrategyBaseStorage storage $base = _getStrategyBaseStorage();
    address u = $base._underlying;
    ERC4626StrategyBaseStorage storage $ = _getERC4626StrategyBaseStorage();
    if ($.lastSharePrice == 0) {
      $.lastSharePrice = _getSharePrice(u);
    }
    IEulerVault eulerVault = IEulerVault(u);
    value = eulerVault.deposit(amounts[0], address(this));
  }

  /// @inheritdoc ERC4626StrategyBase
  //slither-disable-next-line unused-return
  function _withdrawAssets(
    address[] memory,
    uint value,
    address receiver
  ) internal override returns (uint[] memory amountsOut) {
    amountsOut = new uint[](1);
    StrategyBaseStorage storage $base = _getStrategyBaseStorage();
    IEulerVault eulerVault = IEulerVault($base._underlying);
    amountsOut[0] = eulerVault.redeem(value, receiver, address(this));
  }
  //endregion ----------------------- Strategy base

  //region ----------------------- Internal logic
  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                       INTERNAL LOGIC                       */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

// todo
//  function _getRevenue(
//    uint newPrice,
//    address u
//  ) internal view returns (address[] memory __assets, uint[] memory amounts) {
//    return super._getRevenue(newPrice, u);
//  }
  //endregion ----------------------- Internal logic
}
