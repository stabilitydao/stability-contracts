// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../../interfaces/IPlatform.sol";
import "../../interfaces/IRVault.sol";
import "../../interfaces/IVault.sol";
import "../../interfaces/IControllable.sol";

library RVaultLib {
    using SafeERC20 for IERC20;

    uint public constant MAX_COMPOUND_RATIO = 90_000;

    // Custom Errors

    function __RVaultBase_init(
        IRVault.RVaultBaseStorage storage $,
        address platform_,
        address[] memory vaultInitAddresses,
        uint[] memory vaultInitNums
    ) external {
        uint addressesLength = vaultInitAddresses.length;
        if (addressesLength == 0) {
            revert IRVault.NoBBToken();
        }
        if (IPlatform(platform_).allowedBBTokenVaults(vaultInitAddresses[0]) == 0) {
            revert IRVault.NotAllowedBBToken();
        }
        if (vaultInitNums.length != addressesLength * 2) {
            revert IRVault.IncorrectNums();
        }
        // nosemgrep
        for (uint i; i < addressesLength; ++i) {
            if (vaultInitAddresses[i] == address(0)) {
                revert IRVault.ZeroToken();
            }
            if (vaultInitNums[i] == 0) {
                revert IRVault.ZeroVestingDuration();
            }
        }
        if (vaultInitNums[addressesLength * 2 - 1] > MAX_COMPOUND_RATIO) {
            revert IRVault.TooHighCompoundRation();
        }

        $.rewardTokensTotal = addressesLength;
        // nosemgrep
        for (uint i; i < addressesLength; ++i) {
            $.rewardToken[i] = vaultInitAddresses[i];
            $.duration[i] = vaultInitNums[i];
        }
        $.compoundRatio = vaultInitNums[vaultInitNums.length - 1];
        emit IRVault.CompoundRatio(vaultInitNums[vaultInitNums.length - 1]);
    }

    function rewardTokens(IRVault.RVaultBaseStorage storage $) external view returns (address[] memory) {
        uint len = $.rewardTokensTotal;
        address[] memory rts = new address[](len);
        // nosemgrep
        for (uint i; i < len; ++i) {
            rts[i] = $.rewardToken[i];
        }
        return rts;
    }

    function rewardPerToken(IRVault.RVaultBaseStorage storage $, uint rewardTokenIndex) public view returns (uint) {
        uint totalSupplyWithoutItself =
            IERC20(address(this)).totalSupply() - IERC20(address(this)).balanceOf(address(this));
        if (totalSupplyWithoutItself == 0) {
            return $.rewardPerTokenStoredForToken[rewardTokenIndex];
        }
        return $.rewardPerTokenStoredForToken[rewardTokenIndex]
            + (
                (
                    _lastTimeRewardApplicable($.periodFinishForToken[rewardTokenIndex])
                        - $.lastUpdateTimeForToken[rewardTokenIndex]
                ) * $.rewardRateForToken[rewardTokenIndex] * 1e18 / totalSupplyWithoutItself
            );
    }

    function earned(IRVault.RVaultBaseStorage storage $, uint rt, address account) public view returns (uint) {
        return IERC20(address(this)).balanceOf(account)
            * (rewardPerToken($, rt) - $.userRewardPerTokenPaidForToken[rt][account]) / 1e18
            + $.rewardsForToken[rt][account];
    }

    /// @dev Refresh reward numbers
    function updateReward(IRVault.RVaultBaseStorage storage $, address account, uint tokenIndex) public {
        uint _rewardPerTokenStoredForToken = rewardPerToken($, tokenIndex);
        $.rewardPerTokenStoredForToken[tokenIndex] = _rewardPerTokenStoredForToken;
        $.lastUpdateTimeForToken[tokenIndex] = _lastTimeRewardApplicable($.periodFinishForToken[tokenIndex]);
        // nosemgrep
        if (account != address(0) && account != address(this)) {
            $.rewardsForToken[tokenIndex][account] = earned($, tokenIndex, account);
            $.userRewardPerTokenPaidForToken[tokenIndex][account] = _rewardPerTokenStoredForToken;
        }
    }

    /// @dev Transfer earned rewards to rewardsReceiver
    //slither-disable-next-line reentrancy-events
    function payRewardTo(
        IRVault.RVaultBaseStorage storage $,
        uint rewardTokenIndex,
        address owner,
        address receiver
    ) public {
        address localRewardToken = $.rewardToken[rewardTokenIndex];
        uint reward = earned($, rewardTokenIndex, owner);
        //slither-disable-start timestamp
        // nosemgrep
        if (reward > 0 && IERC20(localRewardToken).balanceOf(address(this)) >= reward) {
            $.rewardsForToken[rewardTokenIndex][owner] = 0;
            IERC20(localRewardToken).safeTransfer(receiver, reward);
            emit IRVault.RewardPaid(owner, localRewardToken, reward);
        }
        //slither-disable-end timestamp
    }

    /// @dev Use it for any underlying movements
    function updateRewards(IRVault.RVaultBaseStorage storage $, address account) public {
        uint len = $.rewardTokensTotal;
        // nosemgrep
        for (uint i; i < len; ++i) {
            updateReward($, account, i);
        }
    }

    function getAllRewards(IRVault.RVaultBaseStorage storage $, address owner, address receiver) external {
        updateRewards($, owner);
        uint len = $.rewardTokensTotal;
        // nosemgrep
        for (uint i; i < len; ++i) {
            payRewardTo($, i, owner, receiver);
        }
    }

    function _lastTimeRewardApplicable(uint periodFinishForToken) internal view returns (uint) {
        return Math.min(block.timestamp, periodFinishForToken);
    }

    function notifyTargetRewardAmount(
        IRVault.RVaultBaseStorage storage $,
        IVault.VaultBaseStorage storage _$_,
        uint i,
        uint amount
    ) external {
        updateRewards($, address(0));

        // overflow fix according to https://sips.synthetix.io/sips/sip-77
        if (amount >= type(uint).max / 1e18) {
            revert IRVault.Overflow(type(uint).max / 1e18 - 1);
        }

        address localRewardToken = $.rewardToken[i];
        if (localRewardToken == address(0)) {
            revert IRVault.RTNotFound();
        }

        uint _duration = $.duration[i];

        uint _oldRewardRateForToken = $.rewardRateForToken[i];

        if (i == 0) {
            if (address(_$_.strategy) != msg.sender) {
                revert IControllable.IncorrectMsgSender();
            }
        } else {
            if (amount <= _oldRewardRateForToken * _duration / 100) {
                revert IRVault.RewardIsTooSmall();
            }
        }

        IERC20(localRewardToken).safeTransferFrom(msg.sender, address(this), amount);
        //slither-disable-next-line timestamp
        if (block.timestamp >= $.periodFinishForToken[i]) {
            $.rewardRateForToken[i] = amount / _duration;
        } else {
            uint remaining = $.periodFinishForToken[i] - block.timestamp;
            uint leftover = remaining * _oldRewardRateForToken;
            $.rewardRateForToken[i] = (amount + leftover) / _duration;
        }
        $.lastUpdateTimeForToken[i] = block.timestamp;
        $.periodFinishForToken[i] = block.timestamp + _duration;

        // cant get this error by tests, so commented
        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        // uint balance = IERC20(localRewardToken).balanceOf(address(this));
        // if ($.rewardRateForToken[i] > balance / _duration) {
        //     revert IRVault.RewardIsTooBig();
        // }
        emit IRVault.RewardAdded(localRewardToken, amount);
    }
}
