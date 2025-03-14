# Platform Administration Guide V4

## Dedicated sender actions

### Manual HardWork

#### Sonic

```shell
cast send -r sonic --gas-limit 15000000 --account DedicatedServerMsgSender 0x635b1f7dd7d0172533ba9fe5cfe2d83d9848f701 'call(address[])' [0x2fBeBA931563feAAB73e8C66d7499c49c8AdA224]
```

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

* [Factory sonicscan](https://sonicscan.org/address/0xc184a3ecca684f2621c903a7943d85fa42f56671#writeProxyContract)
* Connect operator wallet
* `1. addFarms`
* `[[0, "0x822B6E8D0A3EAf306A6A604f6AF370F6d893292d", "Equalizer Farm", ["0xddF26B42C1d903De8962d3F79a74a501420d5F19"], ["0xad2131601f22D15cBbc6267ACc16e4035FfC8bF6","0xcC6169aA1E879d3a4227536671F85afdb2d23fAD"], [], []]]`

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

* [Factory sonicscan](https://sonicscan.org/address/0xc184a3ecca684f2621c903a7943d85fa42f56671#writeProxyContract)
* Connect operator wallet
* `4. setStrategyAvailableInitParams (0x6c2713a3)`
* fill params

### Add swapper routes

#### Use `ISwapper.addPools` method via cast.

```shell
cast send -i --rpc-url sonic 0xe52fcf607a8328106723804de1ef65da512771be 'addPools((address,address,address,address)[],bool)' '[("0xE72b6DD415cDACeAC76616Df2C9278B33079E0D3","0xaf95468b1a624605bbfb862b0fb6e9c73ad847b8","0x29219dd400f2Bf60E5a23d13Be72B486D4038894","0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38")]' true
```

#### Use `ISwapper.addPools` method via explorer.

<details>
  <summary>solidity</summary>

```solidity
struct AddPoolData {
    address pool;
    address ammAdapter;
    address tokenIn;
    address tokenOut;
}

function addPools(AddPoolData[] memory pools, bool rewrite) external;
```
</details>

<details>
  <summary>AMM adapters on sonic</summary>

* Solidly (Equalizer, SwapX classic): 0xe3374041f173ffcb0026a82c6eef94409f713cf9
* AlgebraV4 (SwapX CL): 0xcb2dfcaec4F1a4c61c5D09100482109574E6b8C7
* UniswapV3 (Shadow): 0xAf95468B1a624605bbFb862B0FB6e9C73Ad847b8
* ERC4626: 0xB7192f4b8f741E21b9022D2F8Fd19Ca8c94E7774
</details>

* [Swapper sonicscan](https://sonicscan.org/address/0xe52Fcf607A8328106723804De1ef65Da512771Be#writeProxyContract)
* Connect operator wallet
* `3. addPools`
* pools_ (tuple[]): `[["0x822B6E8D0A3EAf306A6A604f6AF370F6d893292d","0xe3374041f173ffcb0026a82c6eef94409f713cf9","0x05e31a691405d06708A355C029599c12d5da8b28","0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38"]]`
* rewrite (bool): false
* Check price on [PriceReader sonicscan](https://sonicscan.org/address/0x422025182dd83a610bfa8b20550dcccdf94dc549#readProxyContract)

### Add new strategy

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

* [Factory sonicscan](https://sonicscan.org/address/0xc184a3ecca684f2621c903a7943d85fa42f56671#writeProxyContract)
* Connect operator wallet
* `8. setStrategyLogicConfig`
* fill

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

### Upgrade strategy

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

* [New transasction](https://app.safe.global/apps/open?safe=sonic:0xF564EBaC1182578398E94868bea1AbA6ba339652&appUrl=https%3A%2F%2Fapps-portal.safe.global%2Ftx-builder)
* Connect signer wallet
* Address: `0xc184a3ecca684f2621c903a7943d85fa42f56671`

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
* Upgrade vault's strategy [Factory sonicscan](https://sonicscan.org/address/0xc184a3ecca684f2621c903a7943d85fa42f56671#writeProxyContract)

### Init contest gems rewards

Use `IMerkleDistributor.setupCampaign`.

1. [New Transaction](https://app.safe.global/apps/open?safe=sonic:0xF564EBaC1182578398E94868bea1AbA6ba339652&appUrl=https%3A%2F%2Fapps-portal.safe.global%2Ftx-builder)
2. `0x0391aBDCFaB86947d93f9dd032955733B639416b` (MerkleDistributor)
3. Enter ABI: `[{"type": "function", "name": "setupCampaign", "inputs": [{"name": "campaignId", "type": "string", "internalType": "string"}, {"name": "token", "type": "address", "internalType": "address"}, {"name": "totalAmount", "type": "uint256", "internalType": "uint256"}, {"name": "merkleRoot", "type": "bytes32", "internalType": "bytes32"}, {"name": "mint", "type": "bool", "internalType": "bool"}], "outputs": [], "stateMutability": "nonpayable"}]`
4. campignId: `y<num>`
5. token: `0x9A08cD5691E009cC72E2A4d8e7F2e6EE14E96d6d`
6. totalAmount: `900000000000000000000000`
7. merkleRoot: `<copy>`
8. mint: `true`

### Upgrade platform

Use `IPlatform.announcePlatformUpgrade`

1. [New Transaction](https://app.safe.global/apps/open?safe=sonic:0xF564EBaC1182578398E94868bea1AbA6ba339652&appUrl=https%3A%2F%2Fapps-portal.safe.global%2Ftx-builder)
2. `0x4Aca671A420eEB58ecafE83700686a2AD06b20D8` (Platform)
3. Enter ABI: `[{"type": "function","name": "announcePlatformUpgrade","inputs": [{"name": "newVersion","type": "string","internalType": "string"}, {"name": "proxies","type": "address[]","internalType": "address[]"}, {"name": "newImplementations","type": "address[]","internalType": "address[]"}],"outputs": [],"stateMutability": "nonpayable"}]`
4. Fill
