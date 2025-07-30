// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Restored from Sonic.0xB362916fa55088149eA92e007E153976E2d9b1f1
interface IEnclabsRewardDistributor {
  error InvalidBlocksPerYear();
  error InvalidTimeBasedConfiguration();
  error MaxLoopsLimitExceeded(uint256 loopsLimit, uint256 requiredLoops);
  error Unauthorized(
    address sender,
    address calledContract,
    string methodSignature
  );
  event BorrowLastRewardingBlockTimestampUpdated(
    address indexed vToken,
    uint256 newTimestamp
  );
  event BorrowLastRewardingBlockUpdated(
    address indexed vToken,
    uint32 newBlock
  );
  event ContributorRewardTokenSpeedUpdated(
    address indexed contributor,
    uint256 newSpeed
  );
  event ContributorRewardsUpdated(
    address indexed contributor,
    uint256 rewardAccrued
  );
  event DistributedBorrowerRewardToken(
    address indexed vToken,
    address indexed borrower,
    uint256 rewardTokenDelta,
    uint256 rewardTokenTotal,
    uint256 rewardTokenBorrowIndex
  );
  event DistributedSupplierRewardToken(
    address indexed vToken,
    address indexed supplier,
    uint256 rewardTokenDelta,
    uint256 rewardTokenTotal,
    uint256 rewardTokenSupplyIndex
  );
  event Initialized(uint8 version);
  event MarketInitialized(address indexed vToken);
  event MaxLoopsLimitUpdated(
    uint256 oldMaxLoopsLimit,
    uint256 newmaxLoopsLimit
  );
  event NewAccessControlManager(
    address oldAccessControlManager,
    address newAccessControlManager
  );
  event OwnershipTransferStarted(
    address indexed previousOwner,
    address indexed newOwner
  );
  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );
  event RewardTokenBorrowIndexUpdated(
    address indexed vToken,
    Exp marketBorrowIndex
  );
  event RewardTokenBorrowSpeedUpdated(
    address indexed vToken,
    uint256 newSpeed
  );
  event RewardTokenGranted(address indexed recipient, uint256 amount);
  event RewardTokenSupplyIndexUpdated(address indexed vToken);
  event RewardTokenSupplySpeedUpdated(
    address indexed vToken,
    uint256 newSpeed
  );
  event SupplyLastRewardingBlockTimestampUpdated(
    address indexed vToken,
    uint256 newTimestamp
  );
  event SupplyLastRewardingBlockUpdated(
    address indexed vToken,
    uint32 newBlock
  );

  function INITIAL_INDEX() external view returns (uint224);

  function acceptOwnership() external;

  function accessControlManager() external view returns (address);

  function blocksOrSecondsPerYear() external view returns (uint256);

  function claimRewardToken(address holder, address[] memory vTokens)
  external;

  function claimRewardToken(address holder) external;

  function distributeBorrowerRewardToken(
    address vToken,
    address borrower,
    Exp memory marketBorrowIndex
  ) external;

  function distributeSupplierRewardToken(address vToken, address supplier)
  external;

  function getBlockNumberOrTimestamp() external view returns (uint256);

  function grantRewardToken(address recipient, uint256 amount) external;

  function initialize(
    address comptroller_,
    address rewardToken_,
    uint256 loopsLimit_,
    address accessControlManager_
  ) external;

  function initializeMarket(address vToken) external;

  function isTimeBased() external view returns (bool);

  function lastContributorBlock(address) external view returns (uint256);

  function maxLoopsLimit() external view returns (uint256);

  function owner() external view returns (address);

  function pendingOwner() external view returns (address);

  function renounceOwnership() external;

  function rewardToken() external view returns (address);

  function rewardTokenAccrued(address) external view returns (uint256);

  function rewardTokenBorrowSpeeds(address) external view returns (uint256);

  function rewardTokenBorrowState(address)
  external
  view
  returns (
    uint224 index,
    uint32 block,
    uint32 lastRewardingBlock
  );

  function rewardTokenBorrowStateTimeBased(address)
  external
  view
  returns (
    uint224 index,
    uint256 timestamp,
    uint256 lastRewardingTimestamp
  );

  function rewardTokenBorrowerIndex(address, address)
  external
  view
  returns (uint256);

  function rewardTokenContributorSpeeds(address)
  external
  view
  returns (uint256);

  function rewardTokenSupplierIndex(address, address)
  external
  view
  returns (uint256);

  function rewardTokenSupplySpeeds(address) external view returns (uint256);

  function rewardTokenSupplyState(address)
  external
  view
  returns (
    uint224 index,
    uint32 block,
    uint32 lastRewardingBlock
  );

  function rewardTokenSupplyStateTimeBased(address)
  external
  view
  returns (
    uint224 index,
    uint256 timestamp,
    uint256 lastRewardingTimestamp
  );

  function setAccessControlManager(address accessControlManager_) external;

  function setContributorRewardTokenSpeed(
    address contributor,
    uint256 rewardTokenSpeed
  ) external;

  function setLastRewardingBlockTimestamps(
    address[] memory vTokens,
    uint256[] memory supplyLastRewardingBlockTimestamps,
    uint256[] memory borrowLastRewardingBlockTimestamps
  ) external;

  function setLastRewardingBlocks(
    address[] memory vTokens,
    uint32[] memory supplyLastRewardingBlocks,
    uint32[] memory borrowLastRewardingBlocks
  ) external;

  function setMaxLoopsLimit(uint256 limit) external;

  function setRewardTokenSpeeds(
    address[] memory vTokens,
    uint256[] memory supplySpeeds,
    uint256[] memory borrowSpeeds
  ) external;

  function transferOwnership(address newOwner) external;

  function updateContributorRewards(address contributor) external;

  function updateRewardTokenBorrowIndex(
    address vToken,
    Exp memory marketBorrowIndex
  ) external;

  function updateRewardTokenSupplyIndex(address vToken) external;

  struct Exp {
    uint256 mantissa;
  }
}
