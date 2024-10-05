# Platform Administration Guide V3

## Dedicated sender actions

### Manual HardWork

#### Polygon

```shell
cast send -r polygon --gas-limit 15000000 --account DedicatedServerMsgSender 0x6DBFfd2846d4a556349a3bc53297700d89a94034 'call(address[])' [0x7337bf358b4B2e5d0a1AEbE7BbD65b46D6208ED2,0xa313547075DEd50854C1427b3C82878c010E7e35,]
```

#### Base

```shell
cast send -r polygon --gas-limit 15000000 --account DedicatedServerMsgSender 0x2FfeB278BB1Fb9f3B48619AbaBe955526942ac8c 'call(address[])' [0xf6164dE791FDD7028001977bf207e42c59076A48,0x62146825d787EaD9C5bB8ADc8e7EFd3Ec3d7189a,]```
```

## Operator actions

### Add new farms

Use `IFactory.addFarms` method via explorer.

<details>
  <summary>solidity</summary>

```solidity
struct Farm {
    uint status;
    address pool;
    string strategyLogicId;
    address[] rewardAssets;
    address[] addresses;
    uint[] nums;
    int24[] ticks;
}

/// @notice Add farm to factory
/// @param farms_ Settings and data required to work with the farm.
function addFarms(Farm[] memory farms_) external;
```
</details>

* [Factory polygonscan](https://polygonscan.com/address/0xa14EaAE76890595B3C7ea308dAEBB93863480EAD#writeProxyContract)
* Connect operator wallet
* `1. addFarms`
* `[[0, "0xAE81FAc689A1b4b1e06e7ef4a2ab4CD8aC0A087D", "DefiEdge QuickSwap Merkl Farm", ["0x958d208Cdf087843e9AD98d23823d32E17d723A1"], ["0x29f177EFF806b8A71Ff8C7259eC359312CaCE22D"], [0], []]]`

### Set strategy available init params

Use `IFactory.setStrategyAvailableInitParams` method via explorer.

<details>
  <summary>solidity</summary>

```solidity
/// @notice Initial addition or change of strategy available init params
/// @param id Strategy ID string
/// @param initParams Init params variations that will be parsed by strategy
function setStrategyAvailableInitParams(string memory id, StrategyAvailableInitParams memory initParams) external;
```
</details>

* [Factory polygonscan](https://polygonscan.com/address/0xa14EaAE76890595B3C7ea308dAEBB93863480EAD#writeProxyContract)
* Connect operator wallet
* `4. setStrategyAvailableInitParams (0x6c2713a3)`
* fill params

## Multisig actions

### Set vault config

Use `IFactory.setVaultConfig` method.

View current building prices and vault type string IDs on [Factory](https://polygonscan.com/address/0xa14EaAE76890595B3C7ea308dAEBB93863480EAD#readProxyContract) `24. vaultTypes`

<details>
    <summary>solidity</summary>

```solidity
struct VaultConfig {
    string vaultType;
    address implementation;
    bool deployAllowed;
    bool upgradeAllowed;
    uint buildingPrice;
}

/// @notice Initial addition or change of vault type settings.
/// Operator can add new vault type. Governance or multisig can change existing vault type config.
/// @param vaultConfig_ Vault type settings
function setVaultConfig(VaultConfig memory vaultConfig_) external;
```
</details>

Call it via Safe Transaction Builder:

* [New transasction](https://app.safe.global/apps/open?safe=matic:0x36780E69D38c8b175761c6C5F8eD42E61ee490E9&appUrl=https%3A%2F%2Fapps-portal.safe.global%2Ftx-builder)
* Connect signer wallet
* Address: 0xa14EaAE76890595B3C7ea308dAEBB93863480EAD

<details>
  <summary>ABI</summary>

`
[{"inputs": [{"components": [{"internalType": "string","name": "vaultType","type": "string"},{"internalType": "address","name": "implementation","type": "address"},{"internalType": "bool","name": "deployAllowed","type": "bool"},{"internalType": "bool","name": "upgradeAllowed","type": "bool"},{"internalType": "uint256","name":"buildingPrice","type": "uint256"}],"internalType": "struct IFactory.VaultConfig","name": "vaultConfig_","type": "tuple"}],"name": "setVaultConfig","outputs": [],"stateMutability": "nonpayable","type": "function"}]
`
</details>

* vaultConfig_: `["<Vault type string ID>","<implementation address>",true,true,"<price SDIV>"]`
* Add transaction, Create batch, Simulate, Send batch, Sign
* Ask other signers to confirm and execute

### Set strategy config

Use `IFactory.setStrategyLogicConfig` method.
This need to add new strategy, upgrade strategy implementation or disable vaults building.

<details>
  <summary>solidity</summary>

```solidity
struct StrategyLogicConfig {
    string id;
    address implementation;
    bool deployAllowed;
    bool upgradeAllowed;
    bool farming;
    uint tokenId;
}

/// @notice Initial addition or change of strategy logic settings.
/// Operator can add new strategy logic. Governance or multisig can change existing logic config.
/// @param config Strategy logic settings
/// @param developer Strategy developer is receiver of minted StrategyLogic NFT on initial addition
function setStrategyLogicConfig(StrategyLogicConfig memory config, address developer) external;
```
</details>

Call it via Safe Transaction Builder:

* [New transasction](https://app.safe.global/apps/open?safe=matic:0x36780E69D38c8b175761c6C5F8eD42E61ee490E9&appUrl=https%3A%2F%2Fapps-portal.safe.global%2Ftx-builder)
* Connect signer wallet
* Address: `0xa14EaAE76890595B3C7ea308dAEBB93863480EAD`

<details>
  <summary>ABI</summary>

`
[{"type": "function","name": "strategyLogicConfig","inputs": [{"name": "idHash","type": "bytes32","internalType": "bytes32"}],"outputs": [{"name": "config","type": "tuple","internalType": "struct IFactory.StrategyLogicConfig","components": [{"name": "id","type": "string","internalType": "string"},{"name": "implementation","type": "address","internalType": "address"},{"name": "deployAllowed","type": "bool","internalType": "bool"},{"name": "upgradeAllowed","type": "bool","internalType": "bool"},{"name": "farming","type": "bool","internalType": "bool"},{"name": "tokenId","type": "uint256","internalType": "uint256"}]}],"stateMutability": "view"},{"type": "function","name": "setStrategyLogicConfig","inputs": [{"name": "config","type": "tuple","internalType": "struct IFactory.StrategyLogicConfig","components": [{"name": "id","type": "string","internalType": "string"},{"name": "implementation","type": "address","internalType": "address"},{"name": "deployAllowed","type": "bool","internalType": "bool"},{"name": "upgradeAllowed","type": "bool","internalType": "bool"},{"name": "farming","type": "bool","internalType": "bool"},{"name": "tokenId","type": "uint256","internalType": "uint256"}]},{"name": "developer","type": "address","internalType": "address"}],"outputs": [],"stateMutability": "nonpayable"}]
`
</details>

* config: `["<Strategy string ID>","<implementation address>",true,true,<is farming?>,0]`
* developer: 0x0000000000000000000000000000000000000000 (zero address for upgrades and NFT receiver address for new logic)
* Add transaction, Create batch, Simulate, Send batch, Sign
* Ask other signers to confirm and execute
