# Deploy Guide

## Deploy and verify

It is important to verify during deployment. Otherwise, you will have to manually verify each lib.

### Plasma

`forge script` now show error: `Error: Chain 9745 not supported`.

When deploying Platform via `forge create` we see `Error: Dynamic linking not supported in `create` command - deploy the following library contracts first, then provide the address to link at compile time`.

```shell
#forge script --rpc-url plasma --slow --broadcast --verify --etherscan-api-key plasma script/deploy-core/Deploy.Plasma.s.sol

forge create .\src\core\proxy\Proxy.sol:Proxy --rpc-url plasma -i --broadcast
# Proxy Platform 0x06e709798dCE60B24a442F3AF5db418B5D388e7C
# Proxy MetaVaultFactory 0x3C888C84511f4C0a4F3Ea5eD1a16ad7F6514077e
# CommonLib 0xb58De97355fb3cFF58db07b3dd5b7dd3e8898425
forge create .\src\core\Platform.sol:Platform --rpc-url plasma -i --broadcast --libraries
# Platform 0xE3f1d1B8ea9721FF0399cF6c2990A4bE5e4fc023
# MetaVaultFactory 0xEB529553Bc75377d8A47F2367881D4e854a560e7
cast send -i --rpc-url plasma 0x06e709798dCE60B24a442F3AF5db418B5D388e7C "initProxy(address)" 0xE3f1d1B8ea9721FF0399cF6c2990A4bE5e4fc023
cast send -i --rpc-url plasma 0x3C888C84511f4C0a4F3Ea5eD1a16ad7F6514077e "initProxy(address)" 0xEB529553Bc75377d8A47F2367881D4e854a560e7
cast send -i --rpc-url plasma 0x06e709798dCE60B24a442F3AF5db418B5D388e7C "initialize(address,string)" 0xE929438B5B53984FdBABf8562046e141e90E8099 2025.10.1-alpha
cast send -i --rpc-url plasma 0x3C888C84511f4C0a4F3Ea5eD1a16ad7F6514077e "initialize(address)" 0x06e709798dCE60B24a442F3AF5db418B5D388e7C

forge verify-contract --chain-id 9745 --num-of-optimizations 200 --watch --compiler-version v0.8.28+commit.7893614a --rpc-url plasma --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/9745/etherscan' --etherscan-api-key avalanche 0xb58De97355fb3cFF58db07b3dd5b7dd3e8898425 .\src\core\libs\CommonLib.sol:CommonLib



```

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
