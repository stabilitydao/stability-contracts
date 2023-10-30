# Core Developer's guide

## Learn stack

* solidity

## Prepare

* install vscode and add extensions
  * nomicfoundation.hardhat-solidity
  * ryanluker.vscode-coverage-gutters
  * davidanson.vscode-markdownlint
* [install foundry](https://book.getfoundry.sh/getting-started/installation)
* clone this repo
* put your Polygon archive RPC node to .env:

```text
POLYGON_RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/....
```

* install deps, compile and test

```shell
forge install
forge test -vv
forge coverage
forge coverage --report lcov
forge build --sizes
```

## Documentation

To generate and serve documentation for smart contracts based on [NatSpec](https://docs.soliditylang.org/en/latest/natspec-format.html) comments, run:

```shell
forge doc --serve
```

## Deploy platform locally for UI

Read UI README.
