# Stability Platform contracts

Stability is asset management, liquidity mining and yield farming platform. Users can deposit funds to vaults that built by other users.
Vaults use tokenized developed asset management strategy logic.

**Contracts are currently being developed. Alpha version is not deployed yet.**

## Strategy development

See the unified list of implemented strategies and those proposed for implementation on the [Strategies](https://book.stabilitydao.org/strategies.html) page in the [Stability Book](https://book.stabilitydao.org).

You can learn how to develop strategies for the platform by reading the [guide](./src/strategies/README.md).

## Core development

### Guide

[Core Developer's guide](./src/core/README.md)

### Tasks

#### Alpha

* coverage
* add events for all actions
* optimize deploy script
  * implement `platform.addBoostTokens(address[] memory allowedBoostRewardToken, address[] memory defaultBoostRewardToken);`
  * refactor `swapper.setThreshold` to `swapper.setThresholds(address[] memory tokenIn, uint[] memory thresholdAmount);`
  * refactor `factory.addFarm` to `factory.addFarms(Farm[] memory farms_);`
* natspecs
* code todo tasks
* zap

#### Beta

* AI audit
* RMVault
  * buy-back ratio
  * manage capacity
* dynamic strategy
* managed strategy
* optimise reads (dexAdapters etc)

#### Bridge

* describe arch of bridging TOKEN lock -> ChildATOKEN mint -> burn -> ChildBTOKEN mint -> burn -> TOKEN unlock
* TokenFactory, ChildERC20, ChildERC721
* IDataTransferProtocol
  * LayerZeroAdapter
* bridge ecosystem tokens
* assets bridge adapters

#### Future developments

Further plans for the development of the platform core can be read in the [Roadmap](https://book.stabilitydao.org/roadmap.html).

## Coverage

[![codecov](https://codecov.io/gh/stabilitydao/stability-platform-contracts/graph/badge.svg?token=HXU4SR81AV)](https://codecov.io/gh/stabilitydao/stability-platform-contracts)

![cov](https://codecov.io/gh/stabilitydao/stability-platform-contracts/graphs/tree.svg?token=HXU4SR81AV)

## Versioning

* Stability Platform uses [CalVer](https://calver.org/) scheme **YY.MM.MINOR-TAG**
* Core contracts and strategies use [SemVer](https://semver.org/) scheme **MAJOR.MINOR.PATCH**
