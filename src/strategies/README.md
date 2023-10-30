# Development of strategy logic

## 0. Prepare

### Install forge, git

### Fork repo

```shell
git clone https://github.com/stabilitydao/v2.git
```

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
* Add your strategy logic deployment to runDeploy method in `chains/<ChainName>Lib.sol`
* Put your developer address to `src/strategies/libs/StrategyDeveloperLib.sol`

## 2. (Optional) Implement DeX adapter

If the strategy uses DeX for which the platform does not have an adapter, then this adapter will have to be developed.
Functions inheriting from IDexAdapter should be implemented.

## 3. (Optional) Add swapper routes

For each token in strategy assets and farming reward assets the swapper must have a route.
Add routes to `chains/<ChainName>DataLib.sol`.

## 4. (Optional) Add farms

For farming strategy you need to add farming data to `chains/<ChainName>Lib.sol`

## 4. Implement strategy logic

Depending on the purpose of the logic, the strategy is inherited from a set of base classes:

* PairStrategyBase if strategy uses AMM based on two ERC20 tokens
* FarmingStrategyBase if it is farming strategy

Put your strategy to `src/strategies/<YourStrategyContractName>.sol` and implement all functions that need for compiling.

## 5. Add universal test wrapper and run test

Put your test to `test/strategies/<YourStrategyContractName>.<ChainName>.t.sol`
You must inherit from contracts `<ChainName>Setup`, `UniversalTest` and write `testStrategyUniversal` method with adding strategy variations for testing by `strategies.push(...)`.

Run tests:

```shell
forge test -vvv
```

## 6. Check your strategy code size

If your strategy size exceeds the permissible limit, then move part of the code to the library `src/strategies/libs/<YourStrategyContractName>Lib.sol`.

```shell
forge build --sizes
```
