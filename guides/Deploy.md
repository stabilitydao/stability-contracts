# Deploy Guide

## Deploy and verify

It is important to verify during deployment. Otherwise, you will have to manually verify each lib.

### Sonic

```shell
forge script --rpc-url sonic --slow --broadcast --verify --etherscan-api-key sonic script/deploy-core/Deploy.Sonic.s.sol
```

### Avalanche

```shell
forge script --rpc-url avalanche --slow --broadcast --verify --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/43114/etherscan' --etherscan-api-key avalanche script/deploy-core/Deploy.Avalanche.s.sol
```

### Polygon

```shell
forge script --rpc-url polygon --slow --broadcast -vvvv --verify --etherscan-api-key polygon script/deploy-periphery/Frontend.Polygon.s.sol
```

### Base

```shell
forge script --rpc-url base --slow --broadcast -vvvv --verify --etherscan-api-key base script/deploy-periphery/Frontend.Base.s.sol
```

### Real

```shell
forge script --rpc-url real --slow --broadcast --verify --verifier blockscout --verifier-url https://explorer.re.al/api? --with-gas-price 30000000 -g 200 script/deploy-periphery/Frontend.Real.s.sol
```
