# Platform Administration Guide

## Add new farm

### Use IFactory.addFarms method

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

### Call it via explorer

* [Factory polygonscan](https://polygonscan.com/address/0xa14EaAE76890595B3C7ea308dAEBB93863480EAD#writeProxyContract)
* Connect operator wallet
* `1. addFarms`
* `[[0, "0xAE81FAc689A1b4b1e06e7ef4a2ab4CD8aC0A087D", "DefiEdge QuickSwap Merkl Farm", ["0x958d208Cdf087843e9AD98d23823d32E17d723A1"], ["0x29f177EFF806b8A71Ff8C7259eC359312CaCE22D"], [0], []]]`

## Set strategy config

This need to add new strategy, upgrade strategy implementation or disable vaults building.

### Use IFactory.setStrategyLogicConfig method

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

### Call it via Safe Transaction Builder

* [New transasction](https://app.safe.global/apps/open?safe=matic:0x36780E69D38c8b175761c6C5F8eD42E61ee490E9&appUrl=https%3A%2F%2Fapps-portal.safe.global%2Ftx-builder)
* Connect signer wallet
* Address: `0xa14EaAE76890595B3C7ea308dAEBB93863480EAD`
* ABI: `[{"type": "function","name": "strategyLogicConfig","inputs": [{"name": "idHash","type": "bytes32","internalType": "bytes32"}],"outputs": [{"name": "config","type": "tuple","internalType": "struct IFactory.StrategyLogicConfig","components": [{"name": "id","type": "string","internalType": "string"},{"name": "implementation","type": "address","internalType": "address"},{"name": "deployAllowed","type": "bool","internalType": "bool"},{"name": "upgradeAllowed","type": "bool","internalType": "bool"},{"name": "farming","type": "bool","internalType": "bool"},{"name": "tokenId","type": "uint256","internalType": "uint256"}]}],"stateMutability": "view"},{"type": "function","name": "setStrategyLogicConfig","inputs": [{"name": "config","type": "tuple","internalType": "struct IFactory.StrategyLogicConfig","components": [{"name": "id","type": "string","internalType": "string"},{"name": "implementation","type": "address","internalType": "address"},{"name": "deployAllowed","type": "bool","internalType": "bool"},{"name": "upgradeAllowed","type": "bool","internalType": "bool"},{"name": "farming","type": "bool","internalType": "bool"},{"name": "tokenId","type": "uint256","internalType": "uint256"}]},{"name": "developer","type": "address","internalType": "address"}],"outputs": [],"stateMutability": "nonpayable"}]`
* config: `["DefiEdge QuickSwap Merkl Farm","0x6878F20E9d9d794ca12B9c2a786b90DB82F6aC72",true,true,true,0]`
* developer: 0x0000000000000000000000000000000000000000
* Add transaction, Create batch, Simulate, Send batch, Sign
* Ask other signers to confirm and execute
