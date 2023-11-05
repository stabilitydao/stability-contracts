<div align="center">  
<h1>Stability Platform Audit</h1>
</div>

### Table of contents

- [Summary](#summary)
- [Scope](#scope)
- [Severity Criteria](#severity-criteria)
- [High Risk Findings](#high-risk-findings)
  - [H-01 Sends eth to arbitrary user](#h-01-sends-eth-to-arbitrary-user)
  - [H-02 Uninitialized State Variables](#h-02-uninitialized-state-variables)
- [Medium Risk Findings](#medium-risk-findings)
  - [M-01 Performs a multiplication on the result of a division](#m-01-performs-a-multiplication-on-the-result-of-a-division)
  - [M-02 Uses a dangerous strict equality](#m-02-uses-a-dangerous-strict-equality)
  - [M-03 Contract locking ether found](#m-03-contract-locking-ether-found)
  - [M-04 Can be used in cross function reentrancies](#m-04-can-be-used-in-cross-function-reentrancies)
  - [M-05 Is a local variable never initialized](#m-05-is-a-local-variable-never-initialized)
  - [M-06 Ignores return value](#m-06-ignores-return-value)
- [Low Risk Findings](#low-risk-findings)
  - [L-01 Local variable shadowing](#l-01-local-variable-shadowing)
  - [L-02 Missing zero address validation](#l-02-missing-zero-address-validation)
  - [L-03 Has external calls inside a loop](#l-03-has-external-calls-inside-a-loop)
  - [L-04 Reentrancy External calls State variables written after the call](#l-04-reentrancy-external-calls-state-variables-written-after-the-call)
  - [L-05 Reentrancy External calls Event emitted after the call](#l-05-reentrancy-external-calls-event-emitted-after-the-call)
  - [L-06 Uses timestamp for comparisons](#l-06-uses-timestamp-for-comparisons)
- [Informational](#informational)
  - [I-01 Uses Assembly](#i-01-uses-assembly)
  - [I-02 Has costly operations inside a loop](#i-02-has-costly-operations-inside-a-loop)
  - [I-03 Is never used and should be removed](#i-03-is-never-used-and-should-be-removed)
  - [I-04 Necessitates a version too recent to be trusted](#i-04-necessitates-a-version-too-recent-to-be-trusted)
  - [I-05 Allows old versions](#i-05-allows-old-versions)
  - [I-06 Low level call](#i-06-low-level-call)
  - [I-07 Is not in mixedCase](#i-07-is-not-in-mixedCase)
  - [I-08 Variable names too similar](#i-08-variable-names-too-similar)
  - [I-09 Unused state variable](#i-09-unused-state-variable)
  - [I-10 State variables that could be declared constant](#i-10-state-variables-that-could-be-declared-constant)
- [Notes & Additional Information](#notes-&-additional-information)
- [Conclusions](#conclusions)
- [Disclaimers](#disclaimers)

# Summary

Stability is an asset management, liquidity mining and yield farming platform.
Users can deposit funds to vaults that built by other users.
Vaults use tokenized developed asset management strategy logic.

- Asset management
- Liquidity mining
- Vaults
- Strategies
- Assembly
- Fee structure

This is an Independent Audit of Stability Platform contracts.
This document may contain confidential information about IT systems
and the intellectual property of the Customer as well as
information about potential vulnerabilities and methods of their
exploitation.
The report containing confidential information can be used
internally by the Customer, or it can be disclosed publicly after
all vulnerabilities fixed - upon a decision of the Customer.

# Scope

This is an audit of commit [e0cbc0a54452c208707914ece2d51c9def1026ce](https://github.com/stabilitydao/stability-platform-contracts/commit/e0cbc0a54452c208707914ece2d51c9def1026ce) of the [stabilitydao/stability-platform-contracts](https://github.com/stabilitydao/stability-platform-contracts) repository.

The audit involved a thorough examination of the code to identify vulnerabilities, security weaknesses, and compliance with best practices.
The primary goal is to uncover and mitigate potential risks, preventing security breaches, and ensuring that the smart contracts are resilient to various attack vectors. The audit focused on a wide range of security aspects, including but not limited to, reentrancy issues, access control, input validation, and proper use of cryptographic functions.

The scope included the files inside the `/src` directory, excluding those inside the `/src/integrations` and `/src/test` directories.

In summary, the files in scope are:

- /src/adapters/AlgebraAdapter.sol
- /src/adapters/ChainlinkAdapter.sol
- /src/adapters/KyberAdapter.sol
- /src/adapters/libs/DexAdapterIdLib.sol
- /src/adapters/UniswapV3Adapter.sol
- /src/core/AprOracle.sol
- /src/core/base/Controllable.sol
- /src/core/base/RVaultBase.sol
- /src/core/base/UpgradeableProxy.sol
- /src/core/base/VaultBase.sol
- /src/core/CVault.sol
- /src/core/Factory.sol
- /src/core/HardWorker.sol
- /src/core/libs/CommonLib.sol
- /src/core/libs/ConstantsLib.sol
- /src/core/libs/DeployerLib.sol
- /src/core/libs/FactoryLib.sol
- /src/core/libs/RVaultLib.sol
- /src/core/libs/SlotsLib.sol
- /src/core/libs/StrategyLogicLib.sol
- /src/core/libs/VaultManagerLib.sol
- /src/core/libs/VaultStatusLib.sol
- /src/core/libs/VaultTypeLib.sol
- /src/core/Platform.sol
- /src/core/PriceReader.sol
- /src/core/proxy/Proxy.sol
- /src/core/proxy/StrategyProxy.sol
- /src/core/proxy/VaultProxy.sol
- /src/core/RMVault.sol
- /src/core/RVault.sol
- /src/core/StrategyLogic.sol
- /src/core/Swapper.sol
- /src/core/VaultManager.sol
- /src/interfaces/IAprOracle.sol       
- /src/interfaces/IControllable.sol    
- /src/interfaces/IDexAdapter.sol      
- /src/interfaces/IFactory.sol
- /src/interfaces/IFarmingStrategy.sol 
- /src/interfaces/IHardWorker.sol      
- /src/interfaces/IManagedVault.sol    
- /src/interfaces/IOracleAdapter.sol   
- /src/interfaces/IPairStrategyBase.sol
- /src/interfaces/IPlatform.sol        
- /src/interfaces/IPriceReader.sol     
- /src/interfaces/IProxy.sol
- /src/interfaces/IRVault.sol
- /src/interfaces/IStrategy.sol        
- /src/interfaces/IStrategyLogic.sol   
- /src/interfaces/IStrategyProxy.sol
- /src/interfaces/ISwapper.sol
- /src/interfaces/IVault.sol
- /src/interfaces/IVaultManager.sol
- /src/interfaces/IVaultProxy.sol
- /src/strategies/base/FarmingStrategyBase.sol
- /src/strategies/base/PairStrategyBase.sol   
- /src/strategies/base/StrategyBase.sol       
- /src/strategies/GammaQuickSwapFarmStrategy.sol
- /src/strategies/libs/GammaLib.sol
- /src/strategies/libs/QuickswapLib.sol        
- /src/strategies/libs/StrategyDeveloperLib.sol
- /src/strategies/libs/StrategyIdLib.sol       
- /src/strategies/libs/StrategyLib.sol
- /src/strategies/libs/UniswapV3MathLib.sol    
- /src/strategies/QuickswapV3StaticFarmStrategy.sol

# Severity Criteria

1. High: High-severity vulnerabilities indicate significant security issues that, if exploited, can have a noticeable impact on the security or functionality of a system, potentially leading to financial losses or other detrimental outcomes. Addressing high-severity vulnerabilities is crucial and should be done promptly.

2. Medium: Medium-severity vulnerabilities are less critical than high-severity issues but should still be taken seriously. They may have the potential to cause harm to the security or functionality of a system if exploited, although the impact may be less severe. It is recommended to address medium-severity vulnerabilities to maintain a higher level of security.

3. Low: Low-severity vulnerabilities are the least critical among the classifications. They generally represent minor issues that may have a limited impact on the security or functionality of a system. While not highly dangerous, addressing low-severity vulnerabilities is advisable to ensure comprehensive security.

4. Informational: Informational items provide insights, recommendations, or suggestions for improving code quality, readability, or adherence to best practices. They do not represent direct security vulnerabilities but are valuable for enhancing the maintainability and understandability of the code or system.

# High Risk Findings

### High Risk Findings List

| Number |              Details                                       | Instances |
| :----: | :--------------------------------------------------------- | :-------: |
| [H-01] | Sends eth to arbitrary user                                |     1     |
| [H-02] | Uninitialized State Variables                              |     3     |

## [H-01] Sends eth to arbitrary user

HardWorker._checkGelatoBalance() sends eth to arbitrary user
Dangerous calls:
- `_treasury.depositFunds{value: _gelatoDepositAmount}(address(this),ETH,0);`

#### Recommended Mitigation Steps:

Ensure that an arbitrary user cannot withdraw unauthorized funds.

## [H-02] Uninitialized State Variables

In `src/core/HardWorker.sol:34` the state variable `HardWorker.maxHwPerCall` is never initialized. It is used in: `HardWorker.call(address[])`

In `src/core/HardWorker.sol:35` the state variable `HardWorker.excludedVaults` is never initialized. It is used in: `HardWorker._checker(uint256)`

In `src/core/Platform.sol:80` the state variable `address public ecosystemRevenueReceiver;` is never initialized. It is used in: `Platform._setFees(uint256,uint256,uint256,uint256)`

#### Recommended Mitigation Steps:

Initialize all the variables. If a variable is meant to be initialized to zero, explicitly set it to zero to improve code readability.

# Medium Risk Findings

### Medium Risk Findings List

| Number |              Details                                       | Instances |
| :----: | :--------------------------------------------------------- | :-------: |
| [M-01] | Performs a multiplication on the result of a division      |     15    |
| [M-02] | Uses a dangerous strict equality                           |     1     |
| [M-03] | Contract locking ether found                               |     3     |
| [M-04] | Can be used in cross function reentrancies                 |     8     |
| [M-05] | Is a local variable never initialized                      |     18    |
| [M-06] | Ignores return value                                       |     76    |

## [M-01] Performs a multiplication on the result of a division

In `src/adapters/KyberAdapter.sol:114` in the function `getPrice()` at line 134 `uint part = uint(sqrtPriceX96) * precision / UniswapV3MathLib.TWO_96;`

In `src/adapters/KyberAdapter.sol:114` in the function `getPrice()` at line 138 `uint part = UniswapV3MathLib.TWO_96 * precision / uint(sqrtPriceX96);`

In `src/adapters/KyberAdapter.sol:114` in the function `getPrice()` at line 144 `price * amount / (10 ** tokenInDecimals)`

In `src/adapters/KyberAdapter.sol:56` in the function `getProportion0()` at line 67 `uint consumed1Priced = amount1Consumed * token1Price / token1Desired;`

#### Recommended Mitigation Steps:

Consider ordering multiplication before division.

## [M-02] Uses a dangerous strict equality 

In `src/strategies/QuickswapV3StaticFarmStrategy.sol:143`
QuickSwapV3StaticFarmStrategy._depositAssets(uint256[],bool) uses a dangerous strict equality:
- tokenId == 0

#### Recommended Mitigation Steps:

Don't use strict equality to determine if an account has enough Ether or tokens.

## [M-03] Contract locking ether found

In `src/core/proxy/Proxy.sol:9` Contract `Proxy` has payable functions:
- `UpgradeableProxy.constructor()`
- `UpgradeableProxy.fallback()`
- `UpgradeableProxy.receive()`
But does not have a function to withdraw the ether

In `src/core/proxy/StrategyProxy.sol:11` Contract `StrategyProxy` has payable functions:
- `UpgradeableProxy.constructor()`
- `UpgradeableProxy.fallback()`
- `UpgradeableProxy.receive()`
But does not have a function to withdraw the ether

In `src/core/proxy/VaultProxy.sol:11` Contract `VaultProxy` has payable functions:
- `UpgradeableProxy.constructor()`
- `UpgradeableProxy.fallback()`
- `UpgradeableProxy.receive()`
But does not have a function to withdraw the ether

#### Recommended Mitigation Steps:

Remove the payable attribute or add a withdraw function.

## [M-04] Can be used in cross function reentrancies

In `src/core/base/VaultBase.sol:185` Reentrancy in VaultBase.withdrawAssets(address[],uint256,uint256[]):
External calls:
- strategy.withdrawUnderlying(amountsOut[0],msg.sender)
- amountsOut = strategy.withdrawAssets(assets_,value,msg.sender)
- strategy.withdrawUnderlying(amountsOut[0],msg.sender)
- amountsOut = strategy.transferAssets(amountShares,_totalSupply,msg.sender)
State variables written after the call(s):
- _burn(msg.sender,amountShares)
- _withdrawRequests[from] = block.number
- _withdrawRequests[to] = block.number
VaultBase._withdrawRequests can be used in cross function reentrancies:
- VaultBase._update(address,address,uint256)

#### Recommended Mitigation Steps:

Apply the check-effects-interactions pattern.

# Low Risk Findings

### Low Risk Findings List

| Number |              Details                                                | Instances |
| :----: | :-------------------------------------------------------------------| :-------: |
| [L-01] | Local variable shadowing                                            |     7     |
| [L-02] | Missing zero address validation                                     |     1     |
| [L-03] | Has external calls inside a loop                                    |     32    |
| [L-04] | Reentrancy External calls State variables written after the call    |     15    |
| [L-05] | Reentrancy External calls Event emitted after the call              |     17    |
| [L-06] | Uses timestamp for comparisons                                      |     12    |

# Informational

### Informational List

| Number |              Details                                 | Instances |
| :----: | :----------------------------------------------------| :-------: |
| [I-01] | Uses Assembly                                        |     9     |
| [I-02] | Has costly operations inside a loop                  |     1     |
| [I-03] | Is never used and should be removed                  |     4     |
| [I-04] | Necessitates a version too recent to be trusted      |     64    |
| [I-05] | Allows old versions                                  |     30    |
| [I-06] | Low level call                                       |     2     |
| [I-07] | Is not in mixedCase                                  |     52    |
| [I-08] | Variable names too similar                           |     69    |
| [I-09] | Unused state variable                                |     10    |
| [I-10] | State variables that could be declared constant      |     5     |

