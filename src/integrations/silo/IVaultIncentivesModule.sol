// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IVaultIncentivesModule {
  error AddressZero();
  error AllProgramsNotStopped();
  error CantAcceptFactory();
  error CantAcceptLogic();
  error FactoryAlreadyPending();
  error FactoryAlreadyTrusted();
  error FactoryNotFound();
  error InvalidClaimingLogicsLength();
  error InvalidInitialization();
  error LogicAlreadyAdded();
  error LogicAlreadyPending();
  error LogicNotFound();
  error LogicNotPending();
  error MarketAlreadySet();
  error MarketNotConfigured();
  error NotCuratorRole();
  error NotGuardianRole();
  error NotInitializing();
  error NotOwner();
  error NotificationReceiverAlreadyAdded();
  error NotificationReceiverNotFound();
  event IncentivesClaimingLogicAdded(address indexed market, address logic);
  event IncentivesClaimingLogicRemoved(address indexed market, address logic);
  event Initialized(uint64 version);
  event NotificationReceiverAdded(address notificationReceiver);
  event NotificationReceiverRemoved(address notificationReceiver);
  event RevokePendingClaimingLogic(address indexed market, address logic);
  event SubmitIncentivesClaimingLogic(address indexed market, address logic);
  event TrustedFactoryAdded(address factory);
  event TrustedFactoryRemoved(address factory);
  event TrustedFactoryRevoked(address factory);
  event TrustedFactorySubmitted(address factory);

  function __VaultIncentivesModule_init(
    address _vault,
    address _notificationReceiver,
    address[] memory _initialClaimingLogics,
    address[] memory _initialMarketsWithIncentives,
    address[] memory _initialTrustedFactories
  ) external;

  function acceptIncentivesClaimingLogic(address _market, address _logic)
  external;

  function acceptTrustedFactory(address _factory) external;

  function addNotificationReceiver(address _notificationReceiver) external;

  function getAllIncentivesClaimingLogics()
  external
  view
  returns (address[] memory logics);

  function getConfiguredMarkets()
  external
  view
  returns (address[] memory markets);

  function getMarketIncentivesClaimingLogics(address market)
  external
  view
  returns (address[] memory logics);

  function getMarketsIncentivesClaimingLogics(address[] memory _marketsInput)
  external
  view
  returns (address[] memory logics);

  function getNotificationReceivers()
  external
  view
  returns (address[] memory receivers);

  function getTrustedFactories()
  external
  view
  returns (address[] memory factories);

  function isTrustedFactory(address _factory)
  external
  view
  returns (bool isTrusted);

  function owner() external view returns (address);

  function pendingClaimingLogics(address market, address logic)
  external
  view
  returns (uint256 validAt);

  function removeIncentivesClaimingLogic(address _market, address _logic)
  external;

  function removeNotificationReceiver(
    address _notificationReceiver,
    bool _allProgramsStopped
  ) external;

  function removeTrustedFactory(address _factory) external;

  function revokePendingClaimingLogic(address _market, address _logic)
  external;

  function revokePendingTrustedFactory(address _factory) external;

  function submitIncentivesClaimingLogic(address _market, address _logic)
  external;

  function submitTrustedFactory(address _factory) external;

  function vault() external view returns (address);
}
