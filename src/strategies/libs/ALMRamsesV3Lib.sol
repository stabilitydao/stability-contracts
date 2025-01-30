// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ALMLib} from "./ALMLib.sol";
import {IALM} from "../../interfaces/IALM.sol";
import {ILPStrategy} from "../../interfaces/ILPStrategy.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {INonfungiblePositionManager} from "../../integrations/ramsesv3/INonfungiblePositionManager.sol";
import {IFarmingStrategy} from "../../interfaces/IFarmingStrategy.sol";
import {IFactory} from "../../interfaces/IFactory.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IControllable} from "../../interfaces/IControllable.sol";
import {IGaugeV3} from "../../integrations/shadow/IGaugeV3.sol";

library ALMRamsesV3Lib {
    using SafeERC20 for IERC20;

    struct DepositAssetsVars {
        address nft;
        address pool;
        address[] assets;
    }

    function depositAssets(
        uint[] memory amounts,
        IALM.ALMStrategyBaseStorage storage $,
        ILPStrategy.LPStrategyBaseStorage storage _$_,
        IStrategy.StrategyBaseStorage storage __$__
    ) external returns (uint value) {
        if ($.algoId == ALMLib.ALGO_FILL_UP) {
            DepositAssetsVars memory v;
            v.nft = $.nft;
            v.pool = _$_.pool;
            v.assets = __$__._assets;
            uint price = ALMLib.getUniswapV3PoolPrice(v.pool);
            value = amounts[1] + (amounts[0] * price / ALMLib.PRECISION);
            uint total = __$__.total;
            int24 tickSpacing = ALMLib.getUniswapV3TickSpacing(v.pool);

            if (total == 0) {
                IALM.Position memory position;
                (position.tickLower, position.tickUpper) =
                    ALMLib.calcFillUpBaseTicks(ALMLib.getUniswapV3CurrentTick(v.pool), $.params[0], tickSpacing);
                (position.tokenId, position.liquidity,,) = INonfungiblePositionManager(v.nft).mint(
                    INonfungiblePositionManager.MintParams({
                        token0: v.assets[0],
                        token1: v.assets[1],
                        tickSpacing: tickSpacing,
                        tickLower: position.tickLower,
                        tickUpper: position.tickUpper,
                        amount0Desired: amounts[0],
                        amount1Desired: amounts[1],
                        amount0Min: 0,
                        amount1Min: 0,
                        recipient: address(this),
                        deadline: block.timestamp
                    })
                );
                $.positions.push(position);
                __$__.total = value;
            } else {
                (, uint[] memory totalAmounts) = IStrategy(address(this)).assetsAmounts();
                uint totalAmount = totalAmounts[1] + totalAmounts[0] * price / ALMLib.PRECISION - value;
                value = value * total / totalAmount;

                uint positionsLength = $.positions.length;
                IALM.Position memory position = $.positions[0];
                (uint128 addedLiquidity,,) = INonfungiblePositionManager(v.nft).increaseLiquidity(
                    INonfungiblePositionManager.IncreaseLiquidityParams({
                        tokenId: position.tokenId,
                        amount0Desired: ALMLib.balance(v.assets[0]),
                        amount1Desired: ALMLib.balance(v.assets[1]),
                        amount0Min: 0,
                        amount1Min: 0,
                        deadline: block.timestamp
                    })
                );
                $.positions[0].liquidity = position.liquidity + addedLiquidity;

                if (positionsLength == 2) {
                    position = $.positions[1];
                    uint amount0Desired = ALMLib.balance(v.assets[0]);
                    uint amount1Desired = ALMLib.balance(v.assets[1]);
                    if (amount0Desired > 100 || amount1Desired > 100) {
                        (addedLiquidity,,) = INonfungiblePositionManager(v.nft).increaseLiquidity(
                            INonfungiblePositionManager.IncreaseLiquidityParams({
                                tokenId: position.tokenId,
                                amount0Desired: amount0Desired,
                                amount1Desired: amount1Desired,
                                amount0Min: 0,
                                amount1Min: 0,
                                deadline: block.timestamp
                            })
                        );
                        $.positions[1].liquidity = position.liquidity + addedLiquidity;
                    }
                }

                __$__.total = total + value;
            }
        }
    }

    function withdrawAssets(
        uint value,
        address receiver,
        IALM.ALMStrategyBaseStorage storage $,
        IStrategy.StrategyBaseStorage storage __$__
    ) external returns (uint[] memory amountsOut) {
        if ($.algoId == ALMLib.ALGO_FILL_UP) {
            address nft = $.nft;

            // burn liquidity
            amountsOut = new uint[](2);
            uint positionsLength = $.positions.length;
            IALM.Position memory position = $.positions[0];
            uint total = __$__.total;
            uint128 liquidityToBurn = uint128(uint(position.liquidity) * value / total);
            (amountsOut[0], amountsOut[1]) = INonfungiblePositionManager(nft).decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: position.tokenId,
                    liquidity: liquidityToBurn,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                })
            );
            $.positions[0].liquidity = position.liquidity - liquidityToBurn;
            INonfungiblePositionManager(nft).collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: position.tokenId,
                    recipient: receiver,
                    amount0Max: uint128(amountsOut[0]),
                    amount1Max: uint128(amountsOut[1])
                })
            );
            if (positionsLength == 2) {
                position = $.positions[1];
                liquidityToBurn = uint128(uint(position.liquidity) * value / total);
                (uint fillupOut0, uint fillupOut1) = INonfungiblePositionManager(nft).decreaseLiquidity(
                    INonfungiblePositionManager.DecreaseLiquidityParams({
                        tokenId: position.tokenId,
                        liquidity: liquidityToBurn,
                        amount0Min: 0,
                        amount1Min: 0,
                        deadline: block.timestamp
                    })
                );
                $.positions[1].liquidity = position.liquidity - liquidityToBurn;
                amountsOut[0] += fillupOut0;
                amountsOut[1] += fillupOut1;
                INonfungiblePositionManager(nft).collect(
                    INonfungiblePositionManager.CollectParams({
                        tokenId: position.tokenId,
                        recipient: receiver,
                        amount0Max: uint128(fillupOut0),
                        amount1Max: uint128(fillupOut1)
                    })
                );
            }

            // send balance part
            address[] memory assets = __$__._assets;
            uint balance0ToSend = ALMLib.balance(assets[0]) * value / total;
            uint balance1ToSend = ALMLib.balance(assets[1]) * value / total;
            if (balance0ToSend != 0) {
                IERC20(assets[0]).safeTransfer(receiver, balance0ToSend);
                amountsOut[0] += balance0ToSend;
            }
            if (balance1ToSend != 0) {
                IERC20(assets[1]).safeTransfer(receiver, balance1ToSend);
                amountsOut[1] += balance1ToSend;
            }

            __$__.total = total - value;
        }
    }

    function rebalance(
        bool[] memory,
        IALM.NewPosition[] memory mintNewPositions,
        IALM.ALMStrategyBaseStorage storage $,
        ILPStrategy.LPStrategyBaseStorage storage _$_,
        IFarmingStrategy.FarmingStrategyBaseStorage storage _f$f_,
        IStrategy.StrategyBaseStorage storage __$__
    ) external {
        if ($.algoId == ALMLib.ALGO_FILL_UP) {
            if (mintNewPositions.length != 1 && mintNewPositions.length != 2) {
                revert IALM.IncorrectRebalanceArgs();
            }

            // collect farm rewards
            // collectFees($, _$_);
            collectFarmRewards($, _f$f_);

            // burn old tokenIds
            address nft = $.nft;
            uint positionsLength = $.positions.length;
            IALM.Position memory position;
            if (positionsLength == 2) {
                position = $.positions[1];
                INonfungiblePositionManager(nft).decreaseLiquidity(
                    INonfungiblePositionManager.DecreaseLiquidityParams({
                        tokenId: position.tokenId,
                        liquidity: position.liquidity,
                        amount0Min: 0,
                        amount1Min: 0,
                        deadline: block.timestamp
                    })
                );
                INonfungiblePositionManager(nft).collect(
                    INonfungiblePositionManager.CollectParams({
                        tokenId: position.tokenId,
                        recipient: address(this),
                        amount0Max: type(uint128).max,
                        amount1Max: type(uint128).max
                    })
                );
                INonfungiblePositionManager(nft).burn(position.tokenId);
                $.positions.pop();
            }

            position = $.positions[0];
            INonfungiblePositionManager(nft).decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: position.tokenId,
                    liquidity: position.liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                })
            );
            INonfungiblePositionManager(nft).collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: position.tokenId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
            INonfungiblePositionManager(nft).burn(position.tokenId);
            $.positions.pop();

            // mint new positions
            {
                address[] memory assets = __$__._assets;
                int24 tickSpacing = ALMLib.getUniswapV3TickSpacing(_$_.pool);
                position.tickLower = mintNewPositions[0].tickLower;
                position.tickUpper = mintNewPositions[0].tickUpper;
                (position.tokenId, position.liquidity,,) = INonfungiblePositionManager(nft).mint(
                    INonfungiblePositionManager.MintParams({
                        token0: assets[0],
                        token1: assets[1],
                        tickSpacing: tickSpacing,
                        tickLower: position.tickLower,
                        tickUpper: position.tickUpper,
                        amount0Desired: ALMLib.balance(assets[0]),
                        amount1Desired: ALMLib.balance(assets[1]),
                        amount0Min: mintNewPositions[0].minAmount0,
                        amount1Min: mintNewPositions[0].minAmount1,
                        recipient: address(this),
                        deadline: block.timestamp
                    })
                );
                $.positions.push(position);

                if (mintNewPositions.length == 2) {
                    position.tickLower = mintNewPositions[1].tickLower;
                    position.tickUpper = mintNewPositions[1].tickUpper;
                    (position.tokenId, position.liquidity,,) = INonfungiblePositionManager(nft).mint(
                        INonfungiblePositionManager.MintParams({
                            token0: assets[0],
                            token1: assets[1],
                            tickSpacing: tickSpacing,
                            tickLower: position.tickLower,
                            tickUpper: position.tickUpper,
                            amount0Desired: ALMLib.balance(assets[0]),
                            amount1Desired: ALMLib.balance(assets[1]),
                            amount0Min: mintNewPositions[1].minAmount0,
                            amount1Min: mintNewPositions[1].minAmount1,
                            recipient: address(this),
                            deadline: block.timestamp
                        })
                    );
                    $.positions.push(position);
                }
            }

            emit IALM.Rebalance($.positions);
        }
    }

    /*function collectFees(IALM.ALMStrategyBaseStorage storage $, ILPStrategy.LPStrategyBaseStorage storage _$_) public {
        if ($.algoId == ALMLib.ALGO_FILL_UP) {
            address nft = $.nft;
            // collect fees
            uint positionsLength = $.positions.length;
            IALM.Position memory position = $.positions[0];
            {
                uint[] memory fees = new uint[](2);
                (uint feeAmount0, uint feeAmount1) = INonfungiblePositionManager(nft).collect(
                    INonfungiblePositionManager.CollectParams({
                        tokenId: position.tokenId,
                        recipient: address(this),
                        amount0Max: type(uint128).max,
                        amount1Max: type(uint128).max
                    })
                );
                fees[0] = feeAmount0;
                fees[1] = feeAmount1;
                console.log('fees', fees[0], fees[1]);
                if (positionsLength == 2) {
                    position = $.positions[1];
                    (feeAmount0, feeAmount1) = INonfungiblePositionManager(nft).collect(
                        INonfungiblePositionManager.CollectParams({
                            tokenId: position.tokenId,
                            recipient: address(this),
                            amount0Max: type(uint128).max,
                            amount1Max: type(uint128).max
                        })
                    );
                    fees[0] += feeAmount0;
                    fees[1] += feeAmount1;
                }
                _$_._feesOnBalance[0] += fees[0];
                _$_._feesOnBalance[1] += fees[1];
                emit ILPStrategy.FeesClaimed(fees);
            }
            //////////
        }
    }*/

    function collectFarmRewards(
        IALM.ALMStrategyBaseStorage storage $,
        IFarmingStrategy.FarmingStrategyBaseStorage storage _f$f_
    ) public {
        IFactory.Farm memory farm =
            IFactory(IPlatform(IControllable(address(this)).platform()).factory()).farm(_f$f_.farmId);
        address gauge = farm.addresses[0];
        uint len = $.positions.length;
        uint[] memory tokenIds = new uint[](len);
        for (uint i; i < len; ++i) {
            tokenIds[i] = $.positions[i].tokenId;
        }
        address[] memory rewardAssets = _f$f_._rewardAssets;
        len = rewardAssets.length;
        uint[] memory rewardBalanceBefore = new uint[](len);
        for (uint i; i < len; ++i) {
            rewardBalanceBefore[i] = ALMLib.balance(rewardAssets[i]);
        }
        IGaugeV3(gauge).getReward(tokenIds, rewardAssets);
        uint[] memory rewardsClaimed = new uint[](len);
        for (uint i; i < len; ++i) {
            rewardsClaimed[i] = ALMLib.balance(rewardAssets[i]) - rewardBalanceBefore[i];
            _f$f_._rewardsOnBalance[i] += rewardsClaimed[i];
        }

        emit IFarmingStrategy.RewardsClaimed(rewardsClaimed);
    }
}
