# Core Developer's guide

## Learn

### Stack

* [Solidity](https://soliditylang.org/)
* [Foundry](https://book.getfoundry.sh/)
* [OpenZeppelin contracts](https://www.openzeppelin.com/contracts)

### Used EIP standards

* [ERC-20: Token Standard](https://eips.ethereum.org/EIPS/eip-20)
* [ERC-165: Standard Interface Detection](https://eips.ethereum.org/EIPS/eip-165)
* [ERC-721: Non-Fungible Token Standard](https://eips.ethereum.org/EIPS/eip-721)
* [ERC-1967: Proxy Storage Slots](https://eips.ethereum.org/EIPS/eip-1967)
* [ERC-4626: Tokenized Vaults](https://eips.ethereum.org/EIPS/eip-4626)
* [ERC-7201: Namespaced Storage Layout](https://eips.ethereum.org/EIPS/eip-7201)

### Used fresh Solidity language features

* [0.8.4](https://github.com/ethereum/solidity/releases/tag/v0.8.4): Support [custom errors](https://soliditylang.org/blog/2021/04/21/custom-errors/) via the error keyword and introduce the revert statement.
* [0.8.8](https://github.com/ethereum/solidity/blob/develop/Changelog.md#088-2021-09-27): Inheritance: A function that overrides only a single interface function does not require the override specifier
* [0.8.15](https://github.com/ethereum/solidity/blob/develop/Changelog.md#0815-2022-06-15): Add E.selector for a non-anonymous event E to access the 32-byte selector topic
* [0.8.18](https://github.com/ethereum/solidity/blob/develop/Changelog.md#0818-2023-02-01): Allow named parameters in mapping types
* [0.8.21](https://soliditylang.org/blog/2023/07/19/solidity-0.8.21-release-announcement/): Allow qualified access to events from other contracts
* [0.8.22](https://soliditylang.org/blog/2023/10/25/solidity-0.8.22-release-announcement/): Unchecked loop increments


## Prepare

* [install vscode](https://code.visualstudio.com/) and add extensions
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
