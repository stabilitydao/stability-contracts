// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IStakedBUSD {

    function UPGRADE_INTERFACE_VERSION() external view returns (string memory);

    function accrualTimestamp() external view returns (uint256);

    function accrueInterest() external;

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function decimals() external view returns (uint8);

    function depositReward(uint256 amount) external;

    function exchangeRateCurrent() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function initialize(address initialOwner, uint256 rewardDuration_, uint256 reserveFactorMantissa_) external;

    function mint(uint256 mintAmount) external;

    function name() external view returns (string memory);

    function owner() external view returns (address);

    function pendingReward() external view returns (uint256);

    function proxiableUUID() external view returns (bytes32);

    function redeem(uint256 redeemTokens) external;

    function reduceReserves(uint256 reduceAmount) external;

    function renounceOwnership() external;

    function reserveFactorMantissa() external view returns (uint256);

    function rewardDistributionEnd() external view returns (uint256);

    function rewardDuration() external view returns (uint256);

    function rewardManager() external view returns (address);

    function rewardRatePerSecond() external view returns (uint256);

    function setReserveFactorMantissa(uint256 newReserveFactorMantissa) external;

    function setRewardDuration(uint256 newDuration) external;

    function setRewardManager(address newRewardManager) external;

    function symbol() external view returns (string memory);

    function totalReserves() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(address from, address to, uint256 value) external returns (bool);

    function transferOwnership(address newOwner) external;

    function underlyingAsset() external view returns (address);

    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}