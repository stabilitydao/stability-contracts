// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ISiloVault {
  error AboveMaxTimelock();
  error AddressEmptyCode(address target);
  error AllCapsReached();
  error AlreadyPending();
  error AlreadySet();
  error AssetLoss(uint256 loss);
  error BelowMinTimelock();
  error ClaimRewardsFailed();
  error ECDSAInvalidSignature();
  error ECDSAInvalidSignatureLength(uint256 length);
  error ECDSAInvalidSignatureS(bytes32 s);
  error ERC20InsufficientAllowance(
    address spender,
    uint256 allowance,
    uint256 needed
  );
  error ERC20InsufficientBalance(
    address sender,
    uint256 balance,
    uint256 needed
  );
  error ERC20InvalidApprover(address approver);
  error ERC20InvalidReceiver(address receiver);
  error ERC20InvalidSender(address sender);
  error ERC20InvalidSpender(address spender);
  error ERC2612ExpiredSignature(uint256 deadline);
  error ERC2612InvalidSigner(address signer, address owner);
  error ERC4626ExceededMaxDeposit(
    address receiver,
    uint256 assets,
    uint256 max
  );
  error ERC4626ExceededMaxMint(address receiver, uint256 shares, uint256 max);
  error ERC4626ExceededMaxRedeem(address owner, uint256 shares, uint256 max);
  error ERC4626ExceededMaxWithdraw(
    address owner,
    uint256 assets,
    uint256 max
  );
  error FailedCall();
  error FailedToWithdraw();
  error InconsistentReallocation();
  error InputZeroShares();
  error InsufficientBalance(uint256 balance, uint256 needed);
  error InternalSupplyCapExceeded(address market);
  error InvalidAccountNonce(address account, uint256 currentNonce);
  error InvalidShortString();
  error MarketNotEnabled(address market);
  error NoPendingValue();
  error NotAllocatorRole();
  error NotCuratorNorGuardianRole();
  error NotCuratorRole();
  error NotEnoughLiquidity();
  error NotGuardianRole();
  error OwnableInvalidOwner(address owner);
  error OwnableUnauthorizedAccount(address account);
  error ReentrancyError();
  error SafeCastOverflowedUintDowncast(uint8 bits, uint256 value);
  error SafeERC20FailedOperation(address token);
  error StringTooLong(string str);
  error SupplyCapExceeded(address market);
  error TimelockNotElapsed();
  error UnauthorizedMarket(address market);
  error ZeroAddress();
  error ZeroAssets();
  error ZeroShares();
  event AccrueInterest(uint256 newTotalAssets, uint256 feeShares);
  event Approval(
    address indexed owner,
    address indexed spender,
    uint256 value
  );
  event Deposit(
    address indexed sender,
    address indexed owner,
    uint256 assets,
    uint256 shares
  );
  event EIP712DomainChanged();
  event OwnershipTransferStarted(
    address indexed previousOwner,
    address indexed newOwner
  );
  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );
  event ReallocateSupply(
    address indexed caller,
    address indexed market,
    uint256 suppliedAssets,
    uint256 suppliedShares
  );
  event ReallocateWithdraw(
    address indexed caller,
    address indexed market,
    uint256 withdrawnAssets,
    uint256 withdrawnShares
  );
  event RevokePendingCap(address indexed caller, address indexed market);
  event RevokePendingGuardian(address indexed caller);
  event RevokePendingMarketRemoval(
    address indexed caller,
    address indexed market
  );
  event RevokePendingTimelock(address indexed caller);
  event SetCurator(address indexed newCurator);
  event SetGuardian(address indexed caller, address indexed guardian);
  event SetTimelock(address indexed caller, uint256 newTimelock);
  event SubmitCap(
    address indexed caller,
    address indexed market,
    uint256 cap
  );
  event SubmitTimelock(uint256 newTimelock);
  event Transfer(address indexed from, address indexed to, uint256 value);
  event UpdateLastTotalAssets(uint256 updatedTotalAssets);
  event Withdraw(
    address indexed sender,
    address indexed receiver,
    address indexed owner,
    uint256 assets,
    uint256 shares
  );

  function DECIMALS_OFFSET() external view returns (uint8);

  function DEFAULT_LOST_THRESHOLD() external view returns (uint256);

  function DOMAIN_SEPARATOR() external view returns (bytes32);

  function INCENTIVES_MODULE() external view returns (address);

  function acceptCap(address _market) external;

  function acceptGuardian() external;

  function acceptOwnership() external;

  function acceptTimelock() external;

  function allowance(address owner, address spender)
  external
  view
  returns (uint256);

  function approve(address spender, uint256 value) external returns (bool);

  function arbitraryLossThreshold(address)
  external
  view
  returns (uint256 threshold);

  function asset() external view returns (address);

  function balanceOf(address account) external view returns (uint256);

  function balanceTracker(address) external view returns (uint256);

  function claimRewards() external;

  function config(address)
  external
  view
  returns (
    uint184 cap,
    bool enabled,
    uint64 removableAt
  );

  function convertToAssets(uint256 shares) external view returns (uint256);

  function convertToShares(uint256 assets) external view returns (uint256);

  function curator() external view returns (address);

  function decimals() external view returns (uint8);

  function deposit(uint256 _assets, address _receiver)
  external
  returns (uint256 shares);

  function eip712Domain()
  external
  view
  returns (
    bytes1 fields,
    string memory name,
    string memory version,
    uint256 chainId,
    address verifyingContract,
    bytes32 salt,
    uint256[] memory extensions
  );

  function fee() external view returns (uint96);

  function feeRecipient() external view returns (address);

  function guardian() external view returns (address);

  function isAllocator(address) external view returns (bool);

  function lastTotalAssets() external view returns (uint256);

  function maxDeposit(address) external view returns (uint256);

  function maxMint(address) external view returns (uint256);

  function maxRedeem(address _owner) external view returns (uint256 shares);

  function maxWithdraw(address _owner) external view returns (uint256 assets);

  function mint(uint256 _shares, address _receiver)
  external
  returns (uint256 assets);

  function multicall(bytes[] memory data)
  external
  returns (bytes[] memory results);

  function name() external view returns (string memory);

  function nonces(address owner) external view returns (uint256);

  function owner() external view returns (address);

  function pendingCap(address)
  external
  view
  returns (uint192 value, uint64 validAt);

  function pendingGuardian()
  external
  view
  returns (address value, uint64 validAt);

  function pendingOwner() external view returns (address);

  function pendingTimelock()
  external
  view
  returns (uint192 value, uint64 validAt);

  function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;

  function previewDeposit(uint256 assets) external view returns (uint256);

  function previewMint(uint256 shares) external view returns (uint256);

  function previewRedeem(uint256 shares) external view returns (uint256);

  function previewWithdraw(uint256 assets) external view returns (uint256);

  function reallocate(MarketAllocation[] memory _allocations) external;

  function redeem(
    uint256 _shares,
    address _receiver,
    address _owner
  ) external returns (uint256 assets);

  function reentrancyGuardEntered() external view returns (bool entered);

  function renounceOwnership() external;

  function revokePendingCap(address _market) external;

  function revokePendingGuardian() external;

  function revokePendingMarketRemoval(address _market) external;

  function revokePendingTimelock() external;

  function setArbitraryLossThreshold(address _market, uint256 _lossThreshold)
  external;

  function setCurator(address _newCurator) external;

  function setFee(uint256 _newFee) external;

  function setFeeRecipient(address _newFeeRecipient) external;

  function setIsAllocator(address _newAllocator, bool _newIsAllocator)
  external;

  function setSupplyQueue(address[] memory _newSupplyQueue) external;

  function submitCap(address _market, uint256 _newSupplyCap) external;

  function submitGuardian(address _newGuardian) external;

  function submitMarketRemoval(address _market) external;

  function submitTimelock(uint256 _newTimelock) external;

  function supplyQueue(uint256) external view returns (address);

  function supplyQueueLength() external view returns (uint256);

  function symbol() external view returns (string memory);

  function syncBalanceTracker(
    address _market,
    uint256 _expectedAssets,
    bool _override
  ) external;

  function timelock() external view returns (uint256);

  function totalAssets() external view returns (uint256 assets);

  function totalSupply() external view returns (uint256);

  function transfer(address _to, uint256 _value)
  external
  returns (bool success);

  function transferFrom(
    address _from,
    address _to,
    uint256 _value
  ) external returns (bool success);

  function transferOwnership(address newOwner) external;

  function updateWithdrawQueue(uint256[] memory _indexes) external;

  function withdraw(
    uint256 _assets,
    address _receiver,
    address _owner
  ) external returns (uint256 shares);

  function withdrawQueue(uint256) external view returns (address);

  function withdrawQueueLength() external view returns (uint256);

  struct MarketAllocation {
    address market;
    uint256 assets;
  }
}

