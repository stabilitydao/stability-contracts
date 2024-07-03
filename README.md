# Stability Platform contracts

> Asset management, liquidity mining and yield farming platform.
> Users invest funds to vaults that are created by other users.
> Vaults use tokenized developed asset management strategy logics.
>
> -- [Stability Book](https://stabilitydao.gitbook.io/)

## Contributing

Contributions can be made in the form of developing strategies, developing the core, creating issues with feature proposals and reporting bugs in contracts. You can also help solve issues with advice or words of encouragement.

### Reward

* Developed strategy logic: 30% of Stability Platform fee from all vaults using the strategy (by StrategyLogic NFT)
* Core development: $8+/hour salary paid by Stability DAO

### Guides

* **[Contributing](./CONTRIBUTING.md)**
* **[Strategy Developer's Guide V3](./src/strategies/README.md)**
* **[Core Developer's Guide](./src/core/README.md)**
* **[Platform Administration Guide V2](./ADM.md)**

## Coverage

[![codecov](https://codecov.io/gh/stabilitydao/stability-contracts/graph/badge.svg?token=HXU4SR81AV)](https://codecov.io/gh/stabilitydao/stability-contracts)

![Coverage Grid](https://codecov.io/gh/stabilitydao/stability-contracts/graphs/tree.svg?token=HXU4SR81AV)

## Versioning

* Stability Platform uses [CalVer](https://calver.org/) scheme **YY.MM.MINOR-TAG**
* Core contracts and strategies use [SemVer](https://semver.org/) scheme **MAJOR.MINOR.PATCH**

## Deployments

Platform address.

* **Polygon** [137] `0xb2a0737ef27b5Cc474D24c779af612159b1c3e60` [polygonscan](https://polygonscan.com/address/0xb2a0737ef27b5Cc474D24c779af612159b1c3e60)
* **Base** [8453] `0x7eAeE5CfF17F7765d89F4A46b484256929C62312` [basescan](https://basescan.org/address/0x7eaee5cff17f7765d89f4a46b484256929c62312)

## Audits

* [Initial vault audit v24.01.1-alpha](audits/initial-audit-stability-platform-v24.01.1-alpha.md) | [critical scope](audits/scopes.md)
