// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./base/LPStrategyBase.sol";
import "./base/FarmingStrategyBase.sol";
import "./libs/UniswapV3MathLib.sol";
import "./libs/StrategyIdLib.sol";
import "./libs/QuickswapLib.sol";
import "../integrations/algebra/IAlgebraPool.sol";
import "../integrations/algebra/INonfungiblePositionManager.sol";
import "../integrations/algebra/IFarmingCenter.sol";
import "../integrations/algebra/IncentiveKey.sol";
import "../core/libs/CommonLib.sol";
import "../adapters/libs/AmmAdapterIdLib.sol";

/// @title Earning QuickSwapV3 farm rewards and swap fees by static liquidity position
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
contract QuickSwapV3StaticFarmStrategy is LPStrategyBase, FarmingStrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = '1.0.0';

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    int24 public lowerTick;
    int24 public upperTick;
    uint internal _tokenId;
    uint internal _startTime;
    uint internal _endTime;
    INonfungiblePositionManager internal _nft;
    IFarmingCenter internal _farmingCenter;

    /// @dev This empty reserved space is put in place to allow future versions to add new.
    /// variables without shifting down storage in the inheritance chain.
    /// Total gap == 50 - storage slots used.
    uint[50 - 7] private __gap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(
        address[] memory addresses,
        uint[] memory nums,
        int24[] memory ticks
    ) public initializer {
        if (addresses.length != 2 || nums.length != 1 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }

        IFactory.Farm memory farm = _getFarm(addresses[0], nums[0]);
        if (farm.addresses.length != 2 || farm.nums.length != 2 || farm.ticks.length != 2) {
            revert IFarmingStrategy.BadFarm();
        }
        _startTime = farm.nums[0];
        _endTime = farm.nums[1];
        lowerTick = farm.ticks[0];
        upperTick = farm.ticks[1];
        _nft = INonfungiblePositionManager(farm.addresses[0]);
        _farmingCenter = IFarmingCenter(farm.addresses[1]);

        __LPStrategyBase_init(LPStrategyBaseInitParams({
            id: StrategyIdLib.QUICKSWAPV3_STATIC_FARM,
            platform: addresses[0],
            vault: addresses[1],
            pool: farm.pool,
            underlying : address(0)
        }));

        __FarmingStrategyBase_init(addresses[0], nums[0]);

        IERC20(_assets[0]).forceApprove(farm.addresses[0], type(uint).max);
        IERC20(_assets[1]).forceApprove(farm.addresses[0], type(uint).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CALLBACKS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override (LPStrategyBase, FarmingStrategyBase) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IFarmingStrategy
    function canFarm() external view override returns (bool) {
        return block.timestamp < _endTime;
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_) public view returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks) {
        //slither-disable-next-line unused-return
        return QuickswapLib.initVariants(platform_, ammAdapterId(), STRATEGY_LOGIC_ID());
    }

    /// @inheritdoc IStrategy
    function getRevenue() external view returns (address[] memory __assets, uint[] memory amounts) {
        __assets = new address[](4);
        __assets[0] = _assets[0];
        __assets[1] = _assets[1];
        __assets[2] = _rewardAssets[0];
        __assets[3] = _rewardAssets[1];
        amounts = new uint[](4);
        IAlgebraPool _pool = IAlgebraPool(pool);
        uint __tokenId = _tokenId;

        // get fees
        UniswapV3MathLib.ComputeFeesEarnedCommonParams memory params = UniswapV3MathLib.ComputeFeesEarnedCommonParams({
            tick: 0,
            lowerTick: 0,
            upperTick: 0,
            liquidity: 0,
            feeGrowthGlobal: 0
        });

        //slither-disable-next-line unused-return
        (,params.tick,,,,,) = _pool.globalState();
        params.feeGrowthGlobal = _pool.totalFeeGrowth0Token();
        uint feeGrowthInside0Last;
        uint feeGrowthInside1Last;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
        //slither-disable-next-line unused-return
        (,,,, params.lowerTick, params.upperTick, params.liquidity, feeGrowthInside0Last, feeGrowthInside1Last, tokensOwed0, tokensOwed1) = _nft.positions(__tokenId);
        //slither-disable-next-line unused-return
        (,, uint feeGrowthOutsideLower0to1, uint feeGrowthOutsideLower1to0,,,,) = _pool.ticks(params.lowerTick);
        //slither-disable-next-line unused-return
        (,, uint feeGrowthOutsideUpper0to1, uint feeGrowthOutsideUpper1to0,,,,) = _pool.ticks(params.upperTick);
        amounts[0] = UniswapV3MathLib.computeFeesEarned(params, feeGrowthOutsideLower0to1, feeGrowthOutsideUpper0to1, feeGrowthInside0Last) + uint(tokensOwed0);
        amounts[1] = UniswapV3MathLib.computeFeesEarned(params, feeGrowthOutsideLower1to0, feeGrowthOutsideUpper1to0, feeGrowthInside1Last) + uint(tokensOwed1);

        // get rewards
        uint[] memory rewards = _getRewards();
        (amounts[2], amounts[3]) = (rewards[0], rewards[1]);
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() external view returns (uint[] memory proportions) {
        proportions = new uint[](2);
        proportions[0] = _getProportion0(pool);
        proportions[1] = 1e18 - proportions[0];
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x558ac5), bytes3(0x121319)));
    }

    /// @inheritdoc ILPStrategy
    function ammAdapterId() public pure override returns(string memory) {
        return AmmAdapterIdLib.ALGEBRA;
    }

    /// @inheritdoc IStrategy
    function STRATEGY_LOGIC_ID() public pure override returns(string memory) {
        return StrategyIdLib.QUICKSWAPV3_STATIC_FARM;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   FARMING STRATEGY BASE                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc FarmingStrategyBase
    function _getRewards() internal view override returns (uint[] memory amounts) {
        amounts = new uint[](2);
        uint __tokenId = _tokenId;
        IncentiveKey memory key = _getIncentiveKey();
        (amounts[0], amounts[1]) = _farmingCenter.eternalFarming().getRewardInfo(key, __tokenId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    //slither-disable-next-line reentrancy-no-eth
    function _depositAssets(uint[] memory amounts, bool claimRevenue) internal override returns (uint value) {
        IFarmingCenter __farmingCenter = _farmingCenter;
        uint128 liquidity;
        uint tokenId = _tokenId;
        IncentiveKey memory key = _getIncentiveKey();
        INonfungiblePositionManager __nft = _nft;
        
        // tokenId == 0 mean that there is no NFT managed by the strategy now
        //slither-disable-next-line incorrect-equality
        if (tokenId == 0) {
            //slither-disable-next-line unused-return
            (tokenId, liquidity, , ) = __nft.mint(INonfungiblePositionManager.MintParams(
                _assets[0],
                _assets[1],
                lowerTick,
                upperTick,
                amounts[0],
                amounts[1],
                0,
                0,
                address(this),
                block.timestamp
            ));
            _tokenId = tokenId;
            __nft.safeTransferFrom(address(this), address(__farmingCenter), tokenId);
        } else {
            //slither-disable-next-line unused-return
            (liquidity,,) = __nft.increaseLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams(
                tokenId,
                amounts[0],
                amounts[1],
                0,
                0,
                block.timestamp
            ));
            if (total > 0) {
                if (claimRevenue) {
                    // get reward amounts
                    _collectRewardsToState(tokenId, key);
                }
                // exit farming (undeposit)
                __farmingCenter.exitFarming(key, tokenId, false);
            } else {
                __nft.safeTransferFrom(address(this), address(_farmingCenter), tokenId);
            }
        }
        _farmingCenter.enterFarming(key, tokenId, 0, false);
        value = uint(liquidity);
        total += value;
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        IFarmingCenter __farmingCenter = _farmingCenter;
        amountsOut = new uint[](2);
        IncentiveKey memory key = _getIncentiveKey();
        uint tokenId = _tokenId;
        _collectRewardsToState(tokenId, key);
        __farmingCenter.exitFarming(key, tokenId, false);
        __farmingCenter.withdrawToken(tokenId, address(this), '');
        // burn liquidity
        (amountsOut[0], amountsOut[1]) = _nft.decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams(tokenId, uint128(value), 0, 0, block.timestamp));
        {
            // collect tokens and fee
            (uint collected0, uint collected1) = _nft.collect(INonfungiblePositionManager.CollectParams(tokenId, address(this), type(uint128).max, type(uint128).max));
            IERC20(_assets[0]).safeTransfer(receiver, amountsOut[0]);
            IERC20(_assets[1]).safeTransfer(receiver, amountsOut[1]);
            uint[] memory fees = new uint[](2);
            fees[0] = collected0 > amountsOut[0] ? (collected0 - amountsOut[0]) : 0;
            fees[1] = collected1 > amountsOut[1] ? (collected1 - amountsOut[1]) : 0;
            emit FeesClaimed(fees);
            if (fees[0] > 0) {
                _feesOnBalance[0] += fees[0];
            }
            if (fees[1] > 0) {
                _feesOnBalance[1] += fees[1];
            }
        }
        total -= value;
        // think total is always gt zero because we have initial shares
        _nft.safeTransferFrom(address(this), address(__farmingCenter), tokenId);
        __farmingCenter.enterFarming(key, tokenId, 0, false);
    }

    /// @inheritdoc StrategyBase
    function _claimRevenue() internal override returns(
        address[] memory __assets,
        uint[] memory __amounts,
        address[] memory __rewardAssets,
        uint[] memory __rewardAmounts
    ) {
        IFarmingCenter __farmingCenter = _farmingCenter;
        __assets = new address[](2);
        __assets[0] = _assets[0];
        __assets[1] = _assets[1];
        __rewardAssets = _rewardAssets;
        __amounts = new uint[](2);
        __rewardAmounts = new uint[](2);
        uint tokenId = _tokenId;
        if (tokenId > 0 && total > 0) {
            (__amounts[0], __amounts[1]) = __farmingCenter.collect(INonfungiblePositionManager.CollectParams(tokenId, address(this), type(uint128).max, type(uint128).max));
            emit FeesClaimed(__amounts);
            (__rewardAmounts[0], __rewardAmounts[1]) = __farmingCenter.collectRewards(_getIncentiveKey(), tokenId);
            if (__rewardAmounts[0] > 0) {
                __rewardAmounts[0] = __farmingCenter.claimReward(__rewardAssets[0], address(this), 0, __rewardAmounts[0]);
            }
            if (__rewardAmounts[1] > 0) {
                __rewardAmounts[1] = __farmingCenter.claimReward(__rewardAssets[1], address(this), 0, __rewardAmounts[1]);
            }
            emit RewardsClaimed(__rewardAmounts);
        }
        uint fee = _feesOnBalance[0];
        if (fee > 0) {
            __amounts[0] += fee;
            _feesOnBalance[0] = 0;
        }
        fee = _feesOnBalance[1];
        if (fee > 0) {
            __amounts[1] += fee;
            _feesOnBalance[1] = 0;
        }
        fee = _rewardsOnBalance[0];
        if (fee > 0) {
            __rewardAmounts[0] += fee;
            _rewardsOnBalance[0] = 0;
        }
        fee = _rewardsOnBalance[1];
        if (fee > 0) {
            __rewardAmounts[1] += fee;
            _rewardsOnBalance[1] = 0;
        }
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {
        (uint[] memory amountsToDeposit) = _swapForDepositProportion(_getProportion0(pool));
        if (amountsToDeposit[0] > 1 || amountsToDeposit[1] > 1) {
            _depositAssets(amountsToDeposit, false);
        }
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax) internal view override (StrategyBase, LPStrategyBase) returns (uint[] memory amountsConsumed, uint value) {
        int24[] memory ticks = new int24[](2);
        ticks[0] = lowerTick;
        ticks[1] = upperTick;
        (value, amountsConsumed) = ammAdapter.getLiquidityForAmounts(pool, amountsMax, ticks);
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        int24[] memory ticks = new int24[](2);
        ticks[0] = lowerTick;
        ticks[1] = upperTick;
        amounts_ = ammAdapter.getAmountsForLiquidity(pool, ticks, uint128(total));
        assets_ = _assets;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getProportion0(address pool_) internal view returns (uint) {
        return ammAdapter.getProportion0(pool_);
    }

    function _getIncentiveKey() private view returns (IncentiveKey memory) {
        return IncentiveKey(_rewardAssets[0], _rewardAssets[1], pool, _startTime, _endTime);
    }

    //slither-disable-next-line reentrancy-no-eth
    function _collectRewardsToState(uint tokenId, IncentiveKey memory key) internal {
        (uint reward, uint bonusReward) = _farmingCenter.collectRewards(key, tokenId);
        if (reward > 0) {
            address token = _rewardAssets[0];
            reward = _farmingCenter.claimReward(token, address(this), 0, reward);
            _rewardsOnBalance[0] += reward;
        }
        if (bonusReward > 0) {
            address token = _rewardAssets[1];
            bonusReward = _farmingCenter.claimReward(token, address(this), 0, bonusReward);
            _rewardsOnBalance[1] += bonusReward;
        }

        if (reward > 0 || bonusReward > 0) {
            uint[] memory __rewardAmounts = new uint[](2);
            __rewardAmounts[0] = reward;
            __rewardAmounts[1] = bonusReward;
            emit RewardsClaimed(__rewardAmounts);
        }
    }
}
