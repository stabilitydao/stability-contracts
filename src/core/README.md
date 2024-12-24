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

* [0.8.4](https://github.com/ethereum/solidity/releases/tag/v0.8.4):
  Support [custom errors](https://soliditylang.org/blog/2021/04/21/custom-errors/) via the error keyword and introduce
  the revert statement.
* [0.8.8](https://github.com/ethereum/solidity/blob/develop/Changelog.md#088-2021-09-27): Inheritance: A function that
  overrides only a single interface function does not require the override specifier
* [0.8.15](https://github.com/ethereum/solidity/blob/develop/Changelog.md#0815-2022-06-15): Add E.selector for a
  non-anonymous event E to access the 32-byte selector topic
* [0.8.18](https://github.com/ethereum/solidity/blob/develop/Changelog.md#0818-2023-02-01): Allow named parameters in
  mapping types
* [0.8.21](https://soliditylang.org/blog/2023/07/19/solidity-0.8.21-release-announcement/): Allow qualified access to
  events from other contracts
* [0.8.22](https://soliditylang.org/blog/2023/10/25/solidity-0.8.22-release-announcement/): Unchecked loop increments

## Prepare

* Setup IDE
    * [vscode](https://code.visualstudio.com/)
        * add extensions
            * nomicfoundation.hardhat-solidity
            * ryanluker.vscode-coverage-gutters
            * davidanson.vscode-markdownlint
    * [WebStorm](https://www.jetbrains.com/webstorm/)
        * add plugins
            * [Solidity](https://plugins.jetbrains.com/plugin/9475-solidity)
        * Windows users: Editor -> Code Style -> Line separator: Unix and macos
* [install foundry](https://book.getfoundry.sh/getting-started/installation)
* clone this repo
* put your urls and keys to `.env` from `.env.exmaple`
* install deps, compile and test

```shell
forge install
forge test -vv
forge coverage
forge coverage --report lcov
forge build --sizes
```

## Documentation

To generate and serve documentation for smart contracts based
on [NatSpec](https://docs.soliditylang.org/en/latest/natspec-format.html) comments, run:

```shell
forge doc --serve
```

## Deploy and verify

It is important to verify during deployment. Otherwise, you will have to manually verify each lib.

### Polygon

```shell
forge script --rpc-url polygon script/deploy-strategy/IQMF.Polygon.s.sol -vvvv --broadcast --verify --slow --etherscan-api-key polygon
```

### Real

```shell
forge script --rpc-url real script/deploy-core/Deploy.Real.s.sol --verify --verifier blockscout --verifier-url https://explorer.re.al/api? --slow --with-gas-price 30000000 -g 200 --broadcast
```

### Sonic

```shell
forge script --rpc-url sonic --slow --broadcast --verify --etherscan-api-key sonic script/deploy-core/Deploy.Sonic.s.sol
```
