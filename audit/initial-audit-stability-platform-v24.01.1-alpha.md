# Stability initial Vault audit (11.03.24)
Most sensitive scope on Stability Platform v24.01.1-alpha stage
## Audited Commit
https://github.com/stabilitydao/stability-contracts/commit/71ac9d219d8dde8b88b45f31d4edf5ea91abd27d

## Executive Summary

The smart contract code review of the solidity blockchain code was performed in such way in order to identify any low to high severity discrepancies within the smart contracts themselves, which may be used as indication to measure the extend of the damages that a black hat hacker could achieve just exploiting the solidity bugs within the assets in scope.

## Document Properties

| File Path                                | nSLOC |
|------------------------------------------|-------|
| src/core/base/VaultBase.sol              | 572   |
| src/core/vaults/CVault.sol               | 58    |

## High Level Outcomes

After having performed and gone through several key stages in the smart contract code review, we were able to identify 3 (three) total solidity bugs/vulnerability, however none were highly compelling and do not require emergency patches.

Overall, Stability was found to have robust smart contracts (from the ones in scope), with some minor solidity artifacts and best practice changes.

## Vulnerability Detail
This section covers the primary vulnerabilities that have been confirmed, through testing, to be
present in the target(s) in scope, and would thereby likely allow unwanted, unintended or unauthorised actions on through the smart contract. Each key vulnerability is given an overall
risk rating based off its individual impact on the target. As part of the sample limitations, remediation is not always included and the description is less detailed.

| Severity | Count |
|----------|-------|
| High     | 0     |
| Medium   | 2     |
| Low      | 1     |

## M-01
| Aspect          | Details                                                                                                 |
|-----------------|---------------------------------------------------------------------------------------------------------|
| Rating          | Medium                                                                                                     |
| Impact          | Withdrawals blocking by griefing attack |
## M-02
| Aspect          | Details                                                                                                 |
|-----------------|---------------------------------------------------------------------------------------------------------|
| Rating          | Medium                                                                                                     |
| Impact          | The user may receive less commission when exiting the strategy |
## L-01
| Aspect          | Details                                                                                                 |
|-----------------|---------------------------------------------------------------------------------------------------------|
| Rating          | Low |                                                                                      
| Impact          | Separate ISwapper getPrice interfaces |


# Medium Risk

## M-01 Withdrawals blocking by griefing attack

## Links to affected code

https://github.com/stabilitydao/stability-contracts/blob/5a22ba12dbd2ddae0b1d68706f2697b64e3012a9/src/core/base/VaultBase.sol#L35

https://github.com/stabilitydao/stability-contracts/blob/5a22ba12dbd2ddae0b1d68706f2697b64e3012a9/src/core/base/VaultBase.sol#L568-L573

https://github.com/stabilitydao/stability-contracts/blob/5a22ba12dbd2ddae0b1d68706f2697b64e3012a9/src/core/base/VaultBase.sol#L512

## Vulnerability details

## Impact

Anyone can block the withdrawal possibility of any user. The attacker can block users with big deposits for a long time just transferring them `0` amount of shares before the withdrawal delay expires. The victim will not be able to withdraw assets instantly. This can cause different financial losses depending on the withdrawal purpose. The time of blocking will be controlled by the attacker, because the delay parameter in the contract is a constant and can't be set to `0` to interrupt an attack. There is a similar issue https://solodit.xyz/issues/m-10-griefing-attack-to-block-withdraws-code4rena-mochi-mochi-contest-git.

  

## Proof of Concept

The contract establish a delay between deposits/transfers and withdrawals:

```solidity
uint internal constant _WITHDRAW_REQUEST_BLOCKS = 5;
```

Users can't withdraw assets before the delay:

```solidity
function _beforeWithdraw(VaultBaseStorage storage $, address owner) internal {
  if ($.withdrawRequests[owner] + _WITHDRAW_REQUEST_BLOCKS >= block.number) {
    revert WaitAFewBlocks();
  }
  $.withdrawRequests[owner] = block.number;
}
```

Every time when user receives shares the user's `withdrawRequests` is set to `block.number`:

```solidity
function _update(address from, address to, uint value) internal
    virtual override {
  super._update(from, to, value);
  VaultBaseStorage storage $ = _getVaultBaseStorage();
  $.withdrawRequests[from] = block.number;
  $.withdrawRequests[to] = block.number;
}
```

It will happen even for a zero value transfer.

The only way for the victim to try to withdraw is to split the balance between many addresses. This can somehow make the attack more difficult.


## Recommended Mitigation Steps

Still on it


## M-02 The user may receive less commission when exiting the strategy

## Vulnerability details

## Impact
`Strategy.doHardWork` collects revenue from the DAO.

`Strategy.doHardWork` can be called either from `VaultBase.doHardWork` or from `VaultBase.depositAssets`.

`VaultBase` can be created with the `QuickSwapV3StaticFarmStrategy` — this strategy collects fees from uni-v3.

The following scenario is possible:

1.  The user adds liquidity to the vault through depositAssets;
2.  In `QuickSwapV3StaticFarmStrategy`, trading occurs and fees are accrued;
3.  The user calls `withdrawAssets`;
4.  As a result, if there was no call to `doHardWork` between steps 1 and 3, then the pool fee rewards will not be credited to the user.



## Recommended Mitigation Steps

Add a doHardWork call to beginning of withdrawAssets.

## L-01 Separate ISwapper getPrice interfaces
## Vulnerability details

## Impact
All contracts that implement ISwapper (UniswapV3Adapter, AlgebraAdapter) use

```solidity 
(uint160 sqrtPriceX96,,,,,,) = IAlgebraPool(pool).globalState();
```
to obtain the price that is used to calculate tvl.

The `sqrtPriceX96` variable can be manipulated to increase or decrease the tvl of the protocol using flash-loan.


## Recommended Mitigation Steps

To avoid such situations, you should separate the use of `ISwapper.getPrice`. Use one function for exchange and leave it as is, the second for displaying tvl, etc. and use `Oracle.Observation` from Uniswap V3.
  

## Tools Used

Manual review

  


