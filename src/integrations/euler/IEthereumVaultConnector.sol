// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// restored from https://sonicscan.org/address/0x4860c903f6ad709c3eda46d3d502943f184d4315#code
interface IEthereumVaultConnector {
  error EVC_BatchPanic();
  error EVC_ChecksReentrancy();
  error EVC_ControlCollateralReentrancy();
  error EVC_ControllerViolation();
  error EVC_EmptyError();
  error EVC_InvalidAddress();
  error EVC_InvalidData();
  error EVC_InvalidNonce();
  error EVC_InvalidOperatorStatus();
  error EVC_InvalidTimestamp();
  error EVC_InvalidValue();
  error EVC_LockdownMode();
  error EVC_NotAuthorized();
  error EVC_OnBehalfOfAccountNotAuthenticated();
  error EVC_PermitDisabledMode();
  error EVC_RevertedBatchResult(
    IEVC.BatchItemResult[] batchItemsResult,
    IEVC.StatusCheckResult[] accountsStatusResult,
    IEVC.StatusCheckResult[] vaultsStatusResult
  );
  error EVC_SimulationBatchNested();
  error InvalidIndex();
  error TooManyElements();
  event AccountStatusCheck(
    address indexed account,
    address indexed controller
  );
  event CallWithContext(
    address indexed caller,
    bytes19 indexed onBehalfOfAddressPrefix,
    address onBehalfOfAccount,
    address indexed targetContract,
    bytes4 selector
  );
  event CollateralStatus(
    address indexed account,
    address indexed collateral,
    bool enabled
  );
  event ControllerStatus(
    address indexed account,
    address indexed controller,
    bool enabled
  );
  event LockdownModeStatus(bytes19 indexed addressPrefix, bool enabled);
  event NonceStatus(
    bytes19 indexed addressPrefix,
    uint256 indexed nonceNamespace,
    uint256 oldNonce,
    uint256 newNonce
  );
  event NonceUsed(
    bytes19 indexed addressPrefix,
    uint256 indexed nonceNamespace,
    uint256 nonce
  );
  event OperatorStatus(
    bytes19 indexed addressPrefix,
    address indexed operator,
    uint256 accountOperatorAuthorized
  );
  event OwnerRegistered(bytes19 indexed addressPrefix, address indexed owner);
  event PermitDisabledModeStatus(bytes19 indexed addressPrefix, bool enabled);
  event VaultStatusCheck(address indexed vault);

  function areChecksDeferred() external view returns (bool);

  function areChecksInProgress() external view returns (bool);

  function batch(IEVC.BatchItem[] memory items) external payable;

  function batchRevert(IEVC.BatchItem[] memory items) external payable;

  function batchSimulation(IEVC.BatchItem[] memory items)
  external
  payable
  returns (
    IEVC.BatchItemResult[] memory batchItemsResult,
    IEVC.StatusCheckResult[] memory accountsStatusCheckResult,
    IEVC.StatusCheckResult[] memory vaultsStatusCheckResult
  );

  function call(
    address targetContract,
    address onBehalfOfAccount,
    uint256 value,
    bytes memory data
  ) external payable returns (bytes memory result);

  function controlCollateral(
    address targetCollateral,
    address onBehalfOfAccount,
    uint256 value,
    bytes memory data
  ) external payable returns (bytes memory result);

  function disableCollateral(address account, address vault) external payable;

  function disableController(address account) external payable;

  function enableCollateral(address account, address vault) external payable;

  function enableController(address account, address vault) external payable;

  function forgiveAccountStatusCheck(address account) external payable;

  function forgiveVaultStatusCheck() external payable;

  function getAccountOwner(address account) external view returns (address);

  function getAddressPrefix(address account) external pure returns (bytes19);

  function getCollaterals(address account)
  external
  view
  returns (address[] memory);

  function getControllers(address account)
  external
  view
  returns (address[] memory);

  function getCurrentOnBehalfOfAccount(address controllerToCheck)
  external
  view
  returns (address onBehalfOfAccount, bool controllerEnabled);

  function getLastAccountStatusCheckTimestamp(address account)
  external
  view
  returns (uint256);

  function getNonce(bytes19 addressPrefix, uint256 nonceNamespace)
  external
  view
  returns (uint256);

  function getOperator(bytes19 addressPrefix, address operator)
  external
  view
  returns (uint256);

  function getRawExecutionContext() external view returns (uint256 context);

  function haveCommonOwner(address account, address otherAccount)
  external
  pure
  returns (bool);

  function isAccountOperatorAuthorized(address account, address operator)
  external
  view
  returns (bool);

  function isAccountStatusCheckDeferred(address account)
  external
  view
  returns (bool);

  function isCollateralEnabled(address account, address vault)
  external
  view
  returns (bool);

  function isControlCollateralInProgress() external view returns (bool);

  function isControllerEnabled(address account, address vault)
  external
  view
  returns (bool);

  function isLockdownMode(bytes19 addressPrefix) external view returns (bool);

  function isOperatorAuthenticated() external view returns (bool);

  function isPermitDisabledMode(bytes19 addressPrefix)
  external
  view
  returns (bool);

  function isSimulationInProgress() external view returns (bool);

  function isVaultStatusCheckDeferred(address vault)
  external
  view
  returns (bool);

  function name() external view returns (string memory);

  function permit(
    address signer,
    address sender,
    uint256 nonceNamespace,
    uint256 nonce,
    uint256 deadline,
    uint256 value,
    bytes memory data,
    bytes memory signature
  ) external payable;

  function reorderCollaterals(
    address account,
    uint8 index1,
    uint8 index2
  ) external payable;

  function requireAccountAndVaultStatusCheck(address account)
  external
  payable;

  function requireAccountStatusCheck(address account) external payable;

  function requireVaultStatusCheck() external payable;

  function setAccountOperator(
    address account,
    address operator,
    bool authorized
  ) external payable;

  function setLockdownMode(bytes19 addressPrefix, bool enabled)
  external
  payable;

  function setNonce(
    bytes19 addressPrefix,
    uint256 nonceNamespace,
    uint256 nonce
  ) external payable;

  function setOperator(
    bytes19 addressPrefix,
    address operator,
    uint256 operatorBitField
  ) external payable;

  function setPermitDisabledMode(bytes19 addressPrefix, bool enabled)
  external
  payable;

  receive() external payable;
}

interface IEVC {
  struct BatchItemResult {
    bool success;
    bytes result;
  }

  struct StatusCheckResult {
    address checkedAddress;
    bool isValid;
    bytes result;
  }

  struct BatchItem {
    address targetContract;
    address onBehalfOfAccount;
    uint256 value;
    bytes data;
  }
}
