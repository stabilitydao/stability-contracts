// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Sonic 0x4451765739b2D7BCe5f8BC95Beaf966c45E1Dcc9
interface IXSilo {
  function MAX_REDEEM_DURATION_CAP() external view returns (uint256);

  function MAX_REDEEM_RATIO() external view returns (uint256);

  function acceptOwnership() external;

  function allowance(address owner, address spender) external view returns (uint256);

  function approve(address spender, uint256 value) external returns (bool);

  function asset() external view returns (address);

  function balanceOf(address account) external view returns (uint256);

  function cancelRedeem(uint256 _redeemIndex) external;

  function convertToAssets(uint256 shares) external view returns (uint256);

  function convertToShares(uint256 assets) external view returns (uint256);

  function decimals() external view returns (uint8);

  function deposit(uint256 _assets, address _receiver) external returns (uint256 shares);

  function finalizeRedeem(uint256 redeemIndex) external;

  function getAmountByVestingDuration(uint256 _xSiloAmount, uint256 _duration)
  external
  view
  returns (uint256 siloAmountAfterVesting);

  function getAmountInByVestingDuration(
    uint256 _xSiloAfterVesting,
    uint256 _duration
  ) external view returns (uint256 xSiloAmountIn);

  function getUserRedeem(address _userAddress, uint256 _redeemIndex)
  external
  view
  returns (
    uint256 currentSiloAmount,
    uint256 xSiloAmount,
    uint256 siloAmountAfterVesting,
    uint256 endTime
  );

  function getUserRedeemsBalance(address _userAddress) external view returns (uint256 redeemingSiloAmount);

  function getUserRedeemsLength(address _userAddress) external view returns (uint256);

  function getXAmountByVestingDuration(
    uint256 _xSiloAmount,
    uint256 _duration
  ) external view returns (uint256 xSiloAfterVesting);

  function maxDeposit(address) external view returns (uint256);

  function maxMint(address) external view returns (uint256);

  function maxRedeem(address _owner) external view returns (uint256 shares);

  function maxRedeemDuration() external view returns (uint256);

  function maxWithdraw(address _owner) external view returns (uint256 assets);

  function minRedeemDuration() external view returns (uint256);

  function minRedeemRatio() external view returns (uint256);

  function mint(uint256 _shares, address _receiver) external returns (uint256 assets);

  function name() external view returns (string memory);

  function notificationReceiver() external view returns (address);

  function owner() external view returns (address);

  function pendingLockedSilo() external view returns (uint256);

  function pendingOwner() external view returns (address);

  function previewDeposit(uint256 assets) external view returns (uint256);

  function previewMint(uint256 shares) external view returns (uint256);

  function previewRedeem(uint256 _shares) external view returns (uint256 assets);

  function previewWithdraw(uint256 _assets) external view returns (uint256 shares);

  function redeem(uint256 _shares, address _receiver, address _owner) external returns (uint256 assets);

  /// @notice on redeem, `_xSiloAmount` of shares are burned, so it is no longer available
  /// when cancel, `_xSiloAmount` of shares will be minted back
  function redeemSilo(uint256 _xSiloAmountToBurn, uint256 _duration) external returns (uint256 siloAmountAfterVesting);

  function renounceOwnership() external;

  function setNotificationReceiver(
    address _notificationReceiver,
    bool _allProgramsStopped
  ) external;

  function setStream(address _stream) external;

  function stream() external view returns (address);

  function symbol() external view returns (string memory);

  function totalAssets() external view returns (uint256 total);

  function totalSupply() external view returns (uint256);

  function transfer(address _to, uint256 _value) external returns (bool);

  function transferFrom(address _from, address _to, uint256 _value) external returns (bool);

  function transferOwnership(address newOwner) external;

  function updateRedeemSettings(
    uint256 _minRedeemRatio,
    uint256 _minRedeemDuration,
    uint256 _maxRedeemDuration
  ) external;

  function userRedeems(address _user) external view  returns (RedeemInfo[] memory);

  function withdraw(
    uint256 _assets,
    address _receiver,
    address _owner
  ) external returns (uint256 shares);

  struct RedeemInfo {
    uint256 currentSiloAmount;
    uint256 xSiloAmountToBurn;
    uint256 siloAmountAfterVesting;
    uint256 endTime;
  }
}

