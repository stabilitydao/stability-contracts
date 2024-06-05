---
name: Network
about: Add network for platform deployment
title: "NetworkName"
labels: NETWORK
assignees: ''

---

# NetworkName

<!-- Change NetworkName to real network name everywhere. -->

## Initial data

<!-- Paste initial data here. -->

* MULTISIG: `0x...`
* buildingPayPerVaultToken: `TOKENSYMBOL`
* buildingPayPerVaultPrice[0]: `AMOUNT`
* network color: `#......`
* bg color: `#......`
* RPC github secret: `..._RPC_URL`

## Need to add

### Chain library

`chains/NetworkNameLib.sol`

* [ ] Tokens
* [ ] Pools
* [ ] Deploy Platform
* [ ] Deploy and setup oracle adapters
* [ ] Deploy AMM adapters
* [ ] SetupSwapper, add routes
* [ ] Farms
* [ ] Deploy strategy logics
* [ ] Add DeX aggregators

### Deploy script

* [ ] `script/Deploy.NetworkName.s.sol`

### Forking and RPC setup

* [ ] `test/base/chains/NetworkNameSetup.sol`
* [ ] `.env.example`
* [ ] `foundry.toml`

### Strategies

* [ ] StrategyShortName1
* [ ] StrategyShortName2
