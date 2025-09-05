// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IRewardManager} from "./IRewardManager.sol";
import {IPInterestManagerYT} from "./IPInterestManagerYT.sol";

interface IPYieldToken is IERC20Metadata, IRewardManager, IPInterestManagerYT {
    event NewInterestIndex(uint indexed newIndex);

    event Mint(
        address indexed caller,
        address indexed receiverPT,
        address indexed receiverYT,
        uint amountSyToMint,
        uint amountPYOut
    );

    event Burn(address indexed caller, address indexed receiver, uint amountPYToRedeem, uint amountSyOut);

    event RedeemRewards(address indexed user, uint[] amountRewardsOut);

    event RedeemInterest(address indexed user, uint interestOut);

    event CollectRewardFee(address indexed rewardToken, uint amountRewardFee);

    function mintPY(address receiverPT, address receiverYT) external returns (uint amountPYOut);

    function redeemPY(address receiver) external returns (uint amountSyOut);

    function redeemPYMulti(
        address[] calldata receivers,
        uint[] calldata amountPYToRedeems
    ) external returns (uint[] memory amountSyOuts);

    function redeemDueInterestAndRewards(
        address user,
        bool redeemInterest,
        bool redeemRewards
    ) external returns (uint interestOut, uint[] memory rewardsOut);

    function rewardIndexesCurrent() external returns (uint[] memory);

    function pyIndexCurrent() external returns (uint);

    function pyIndexStored() external view returns (uint);

    function getRewardTokens() external view returns (address[] memory);

    function SY() external view returns (address);

    function PT() external view returns (address);

    function factory() external view returns (address);

    function expiry() external view returns (uint);

    function isExpired() external view returns (bool);

    function doCacheIndexSameBlock() external view returns (bool);

    function pyIndexLastUpdatedBlock() external view returns (uint128);
}
