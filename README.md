<img src="https://avatars.githubusercontent.com/u/92305387?s" width="100" align="right" alt="Stability">

# Stability Platform contracts

<img src="https://img.shields.io/github/v/tag/stabilitydao/stability-contracts" alt="Tag">
<img src="https://img.shields.io/github/commit-activity/m/stabilitydao/stability-contracts" alt="Commit activity">

> Asset management, liquidity mining and yield farming platform.
> Users invest funds to vaults that are created by other users.
> Vaults use tokenized developed asset management strategy logics.
>
> -- [Stability Book](https://stabilitydao.gitbook.io/)

## Contributing

[<img alt="GitHub top language" src="https://img.shields.io/github/languages/top/stabilitydao/stability-contracts?logo=solidity">](https://docs.soliditylang.org/en/)
[<img src="https://raw.githubusercontent.com/foundry-rs/foundry/master/.github/logo.png" alt="Foundry" width="20" />](https://book.getfoundry.sh/)

Contributions can be made in the form of developing strategies, developing the core, creating issues with feature proposals and reporting bugs in contracts. You can also help solve issues with advice or words of encouragement.

### 🏷️ Issues

[<img src="https://img.shields.io/github/labels/stabilitydao/stability-contracts/META%20ISSUE">](https://github.com/stabilitydao/stability-contracts/labels/META%20ISSUE)
[<img src="https://img.shields.io/github/labels/stabilitydao/stability-contracts/STRATEGY">](https://github.com/stabilitydao/stability-contracts/labels/STRATEGY)
[<img src="https://img.shields.io/github/labels/stabilitydao/stability-contracts/PLATFORM%20UPGRADE">](https://github.com/stabilitydao/stability-contracts/labels/PLATFORM%20UPGRADE)
[<img src="https://img.shields.io/github/labels/stabilitydao/stability-contracts/NETWORK">](https://github.com/stabilitydao/stability-contracts/labels/NETWORK)
[<img src="https://img.shields.io/github/labels/stabilitydao/stability-contracts/ADAPTER">](https://github.com/stabilitydao/stability-contracts/labels/ADAPTER)
[<img src="https://img.shields.io/github/labels/stabilitydao/stability-contracts/BASE%20STRATEGY">](https://github.com/stabilitydao/stability-contracts/labels/BASE%20STRATEGY)
[<img src="https://img.shields.io/github/labels/stabilitydao/stability-contracts/STRATEGY%20UPGRADE">](https://github.com/stabilitydao/stability-contracts/labels/STRATEGY%20UPGRADE)

[<img src="https://img.shields.io/github/issues-search/stabilitydao/stability-contracts?query=is%3Aissue%20is%3Aopen%20awaiting%20in%3Atitle%20label%3ASTRATEGY&style=for-the-badge&label=%F0%9F%93%9C%20Strategies%20awaiting%20the%20developer&labelColor=%23008800">](https://github.com/stabilitydao/stability-contracts/issues?q=is%3Aissue+is%3Aopen+awaiting+in%3Atitle+label%3ASTRATEGY)

### 💰 Reward

* Developed strategy logic: 30% of Stability Platform fee from all vaults using the strategy (by StrategyLogic NFT)
* Core development: $10+/hour salary paid by Stability DAO
* [coming soon] Bounty for creating and solving issues [#155](https://github.com/stabilitydao/stability-contracts/issues/155)

### 📚 Guides

* **[Strategy Developer's Guide V3](./src/strategies/README.md)**
* **[Core Developer's Guide](./src/core/README.md)**
* **[Platform Administration Guide V3](./ADM.md)**

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
* **Re.al** [111188] `0xB7838d447deece2a9A5794De0f342B47d0c1B9DC` [explorer.re.al](https://explorer.re.al/address/0xB7838d447deece2a9A5794De0f342B47d0c1B9DC)
* **Sonic** [146] `0x4Aca671A420eEB58ecafE83700686a2AD06b20D8` [sonicscan](https://sonicscan.org/address/0x4aca671a420eeb58ecafe83700686a2ad06b20d8)

## Audits

* [Initial vault audit v24.01.1-alpha](audits/initial-audit-stability-platform-v24.01.1-alpha.md) | [critical scope](audits/scopes.md)
