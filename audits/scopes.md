# Audit scopes

Lines of code for [release 24.05.0-alpha](https://github.com/stabilitydao/stability-contracts/releases/tag/v24.05.0-alpha) have been calculated.

## Critical

LoC: 521

| File Path                        | nSLOC |
|----------------------------------|-------|
| src/core/base/VaultBase.sol      | 416   |
| src/core/libs/VaultBaseLib.sol   | 76    |
| src/core/vaults/CVault.sol       | 29    |

## Important

LoC: 4706

| File Path                                           | nSLOC |
|-----------------------------------------------------|-------|
| src/core/base/VaultBase.sol                         | 416   |
| src/core/base/Controllable.sol                      | 78    |
| src/core/base/UpgradeableProxy.sol                  | 49    |
| src/core/libs/VaultBaseLib.sol                      | 76    |
| src/core/proxy/Proxy.sol                            | 21    |
| src/core/proxy/StrategyProxy.sol                    | 43    |
| src/core/proxy/VaultProxy.sol                       | 41    |
| src/core/vaults/CVault.sol                          | 29    |
| src/core/Factory.sol                                | 462   |
| src/core/HardWorker.sol                             | 236   |
| src/core/Platform.sol                               | 663   |
| src/core/PriceReader.sol                            | 105   |
| src/core/StrategyLogic.sol                          | 75    |
| src/core/VaultManager.sol                           | 172   |
| src/core/Zap.sol                                    | 133   |
| src/core/Swapper.sol                                | 364   |
| src/adapters/ChainlinkAdapter.sol                   | 64    |
| src/adapters/UniswapV3Adapter.sol                   | 177   |
| src/strategies/base/StrategyBase.sol                | 216   |
| src/strategies/base/LPStrategyBase.sol              | 81    |
| src/strategies/base/FarmingStrategyBase.sol         | 41    |
| src/strategies/base/ERC4626StrategyBase.sol         | 161   |
| src/strategies/libs/StrategyLib.sol                 | 190   |
| src/strategies/libs/LPStrategyLib.sol               | 199   |
| src/strategies/IchiQuickSwapMerklFarmStrategy.sol   | 235   |
| src/strategies/QuickSwapStaticMerklFarmStrategy.sol | 313   |
| src/strategies/YearnStrategy.sol                    | 66    |

## All

LoC: 9051

| File Path                                             | nSLOC |
|-------------------------------------------------------|-------|
| src/core/base/VaultBase.sol                           | 416   |
| src/core/base/RVaultBase.sol                          | 119   |
| src/core/base/Controllable.sol                        | 78    |
| src/core/base/UpgradeableProxy.sol                    | 49    |
| src/core/libs/VaultBaseLib.sol                        | 76    |
| src/core/libs/CommonLib.sol                           | 140   |
| src/core/libs/DeployerLib.sol                         | 11    |
| src/core/libs/FactoryLib.sol                          | 566   |
| src/core/libs/RVaultLib.sol                           | 149   |
| src/core/libs/SlotsLib.sol                            | 23    |
| src/core/libs/StrategyLogicLib.sol                    | 178   |
| src/core/libs/VaultManagerLib.sol                     | 357   |
| src/core/proxy/Proxy.sol                              | 21    |
| src/core/proxy/StrategyProxy.sol                      | 43    |
| src/core/proxy/VaultProxy.sol                         | 41    |
| src/core/vaults/CVault.sol                            | 29    |
| src/core/vaults/RVault.sol                            | 66    |
| src/core/vaults/RMVault.sol                           | 82    |
| src/core/Factory.sol                                  | 462   |
| src/core/HardWorker.sol                               | 236   |
| src/core/Platform.sol                                 | 663   |
| src/core/PriceReader.sol                              | 105   |
| src/core/StrategyLogic.sol                            | 75    |
| src/core/VaultManager.sol                             | 172   |
| src/core/Zap.sol                                      | 133   |
| src/core/Swapper.sol                                  | 364   |
| src/adapters/ChainlinkAdapter.sol                     | 64    |
| src/adapters/UniswapV3Adapter.sol                     | 177   |
| src/adapters/AlgebraAdapter.sol                       | 159   |
| src/adapters/CurveAdapter.sol                         | 113   |
| src/strategies/base/StrategyBase.sol                  | 216   |
| src/strategies/base/LPStrategyBase.sol                | 81    |
| src/strategies/base/FarmingStrategyBase.sol           | 41    |
| src/strategies/base/ERC4626StrategyBase.sol           | 161   |
| src/strategies/libs/StrategyLib.sol                   | 190   |
| src/strategies/libs/LPStrategyLib.sol                 | 199   |
| src/strategies/libs/DQMFLib.sol                       | 40    |
| src/strategies/libs/GRMFLib.sol                       | 98    |
| src/strategies/libs/IQMFLib.sol                       | 67    |
| src/strategies/libs/IRMFLib.sol                       | 140   |
| src/strategies/libs/QSMFLib.sol                       | 60    |
| src/strategies/libs/UniswapV3MathLib.sol              | 301   |
| src/strategies/IchiQuickSwapMerklFarmStrategy.sol     | 235   |
| src/strategies/QuickSwapStaticMerklFarmStrategy.sol   | 313   |
| src/strategies/YearnStrategy.sol                      | 66    |
| src/strategies/CompoundFarmStrategy.sol               | 198   |
| src/strategies/CurveConvexFarmStrategy.sol            | 262   |
| src/strategies/GammaQuickSwapMerklFarmStrategy.sol    | 273   |
| src/strategies/GammaRetroMerklFarmStrategy.sol        | 311   |
| src/strategies/DefiEdgeQuickSwapMerklFarmStrategy.sol | 334   |
| src/strategies/IchiRetroMerklFarmStrategy.sol         | 298   |
