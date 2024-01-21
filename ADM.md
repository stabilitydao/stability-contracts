# Platform Administration Guide

## Add new farm

### Use Factory method addFarms

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
