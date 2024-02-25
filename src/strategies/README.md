# Strategy Developer's Guide

Development of DeFi strategy logic is not simple, its hard work, and not everyone can do it. You need to understand how it all works.

## Choose strategy

See [open STRATEGY issues](https://github.com/stabilitydao/stability-platform-contracts/issues?q=is%3Aopen+is%3Aissue+label%3ASTRATEGY). If the issue has not been created, then create it.

Study the protocols used in the strategy. Conduct all interactions with protocols manually, or find links to such transactions in an explorer.

## Prepare

### Setup software

* git
* foundry
* vscode

### Setup repo

* fork this repo
* clone it

### Fill `.env` file

```text
POLYGON_RPC_URL=<your Polygon RPC url>
```

### Try to run forge

```shell
forge install
forge build --sizes
forge test
forge coverage
```

## 1. Create constants

* Put your new strategy ID to `src/strategies/libs/StrategyIdLib.sol`
* Put the addresses necessary for the strategy to `chains/<ChainName>Lib.sol` constants
* Put your developer address to `src/strategies/libs/StrategyDeveloperLib.sol`

## 2. (Optional) Implement AMM adapter

If the strategy uses AMM for which the platform does not have an adapter, then this adapter will have to be developed.
Functions inheriting from IAmmAdapter should be implemented.

## 3. (Optional) Add swapper routes

For each token in strategy assets and farming reward assets the swapper must have a route.
Add routes to `chains/<ChainName>Lib.sol` inside `routes*()` method.

## 4. (Optional) Add farms

For farming strategy you need to add farming data to `chains/<ChainName>Lib.sol`

## 4. Implement strategy logic

Depending on the purpose of the logic, the strategy is inherited from a set of base classes:

* LPStrategyBase if strategy uses AMM
* FarmingStrategyBase if it is farming strategy

Put your strategy to `src/strategies/<YourStrategyContractName>.sol` and implement all functions that need for compiling.

Add your strategy logic deployment to `script/libs/DeployStrategyLib.sol` and to `runDeploy` method in `chains/<ChainName>Lib.sol`

## 5. Add universal test

Put your test to `test/strategies/<YourStrategyContractName>.<ChainName>.t.sol`
You must inherit from contracts `<ChainName>Setup`, `UniversalTest` and write `test***` method with adding strategy variations for testing by `strategies.push(...)`.

Run tests:

```shell
forge test -vv -match-test test***
```

## 6. Check your strategy code size

If your strategy size exceeds the permissible limit, then move part of the code to the library `src/strategies/libs/<YourStrategyContractName>Lib.sol`.

```shell
forge build --sizes
```

## 7. Write deploy script

Put deploy script for operator to `script/DeployStrategy****.<ChainName>.s.sol` with deploying strategy implementation, adding swap routes and farms.

## 8. Create PR

Create Pull Request for merging from your fork repo branch to main branch of this repo.
