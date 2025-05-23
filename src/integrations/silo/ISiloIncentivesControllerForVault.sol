// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IDistributionManager} from "./IDistributionManager.sol";

/// @notice It's SiloIncentivesController
interface ISiloIncentivesControllerForVault {
  error AddressEmptyCode(address target);
  error ClaimerUnauthorized();
  error DifferentRewardsTokens();
  error EmissionPerSecondTooHigh();
  error FailedCall();
  error IncentivesProgramAlreadyExists();
  error IncentivesProgramNotFound();
  error IndexOverflowAtEmissionsPerSecond();
  error InsufficientBalance(uint256 balance, uint256 needed);
  error InvalidAddressString();
  error InvalidConfiguration();
  error InvalidDistributionEnd();
  error InvalidIncentivesProgramName();
  error InvalidRewardToken();
  error InvalidToAddress();
  error InvalidUserAddress();
  error OnlyNotifier();
  error OnlyNotifierOrOwner();
  error OwnableInvalidOwner(address owner);
  error OwnableUnauthorizedAccount(address account);
  error SafeERC20FailedOperation(address token);
  error StringsInsufficientHexLength(uint256 value, uint256 length);
  error TooLongProgramName();
  error ZeroAddress();
  event AssetConfigUpdated(address indexed asset, uint256 emission);
  event AssetIndexUpdated(address indexed asset, uint256 index);
  event ClaimerSet(address indexed user, address indexed claimer);
  event DistributionEndUpdated(
    string incentivesProgram,
    uint256 newDistributionEnd
  );
  event IncentivesProgramCreated(string name);
  event IncentivesProgramIndexUpdated(
    string incentivesProgram,
    uint256 newIndex
  );
  event IncentivesProgramUpdated(string name);
  event OwnershipTransferStarted(
    address indexed previousOwner,
    address indexed newOwner
  );
  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );
  event RewardsAccrued(
    address indexed user,
    address indexed rewardToken,
    string indexed programName,
    uint256 amount
  );
  event RewardsClaimed(
    address indexed user,
    address indexed to,
    address indexed rewardToken,
    bytes32 programId,
    address claimer,
    uint256 amount
  );
  event UserIndexUpdated(
    address indexed user,
    string incentivesProgram,
    uint256 newIndex
  );

  function MAX_EMISSION_PER_SECOND() external view returns (uint256);

  function NOTIFIER() external view returns (address);

  function PRECISION() external view returns (uint8);

  function TEN_POW_PRECISION() external view returns (uint256);

  function acceptOwnership() external;

  function afterTokenTransfer(
    address _sender,
    uint256 _senderBalance,
    address _recipient,
    uint256 _recipientBalance,
    uint256 _totalSupply,
    uint256 _amount
  ) external;

  function claimRewards(address _to, string[] memory _programNames)
  external
  returns (IDistributionManager.AccruedRewards[] memory accruedRewards);

  function claimRewards(address _to)
  external
  returns (IDistributionManager.AccruedRewards[] memory accruedRewards);

  function claimRewardsOnBehalf(
    address _user,
    address _to,
    string[] memory _programNames
  )
  external
  returns (IDistributionManager.AccruedRewards[] memory accruedRewards);

  function createIncentivesProgram(
    /* DistributionTypes. */ IncentivesProgramCreationInput
    memory _incentivesProgramInput
  ) external;

  function getAllProgramsNames()
  external
  view
  returns (string[] memory programsNames);

  function getClaimer(address _user) external view returns (address);

  function getDistributionEnd(string memory _incentivesProgram)
  external
  view
  returns (uint256);

  function getProgramId(string memory _programName)
  external
  pure
  returns (bytes32);

  function getProgramName(bytes32 _programId)
  external
  pure
  returns (string memory);

  function getRewardsBalance(address _user, string[] memory _programNames)
  external
  view
  returns (uint256 unclaimedRewards);

  function getRewardsBalance(address _user, string memory _programName)
  external
  view
  returns (uint256 unclaimedRewards);

  function getUserData(address _user, string memory _incentivesProgram)
  external
  view
  returns (uint256);

  function getUserUnclaimedRewards(address _user, string memory _programName)
  external
  view
  returns (uint256);

  function immediateDistribution(address _tokenToDistribute, uint104 _amount)
  external;

  function incentivesProgram(string memory _incentivesProgram)
  external
  view
  returns (IDistributionManager.IncentiveProgramDetails memory details);

  function incentivesPrograms(bytes32)
  external
  view
  returns (
    uint256 index,
    address rewardToken,
    uint104 emissionPerSecond,
    uint40 lastUpdateTimestamp,
    uint40 distributionEnd
  );

  function owner() external view returns (address);

  function pendingOwner() external view returns (address);

  function renounceOwnership() external;

  function rescueRewards(address _rewardToken) external;

  function setClaimer(address _user, address _caller) external;

  function setDistributionEnd(
    string memory _incentivesProgram,
    uint40 _distributionEnd
  ) external;

  function transferOwnership(address newOwner) external;

  function updateIncentivesProgram(
    string memory _incentivesProgram,
    uint40 _distributionEnd,
    uint104 _emissionPerSecond
  ) external;

  struct IncentivesProgramCreationInput {
    string name;
    address rewardToken;
    uint104 emissionPerSecond;
    uint40 distributionEnd;
  }
}



