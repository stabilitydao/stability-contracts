// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IKyberSwapElasticLM {
    struct RewardData {
        address rewardToken;
        uint rewardUnclaimed;
    }

    struct LMPoolInfo {
        address poolAddress;
        uint32 startTime;
        uint32 endTime;
        uint totalSecondsClaimed; // scaled by (1 << 96)
        RewardData[] rewards;
        uint feeTarget;
        uint numStakes;
    }

    struct PositionInfo {
        address owner;
        uint liquidity;
    }

    struct StakeInfo {
        uint128 secondsPerLiquidityLast;
        uint[] rewardLast;
        uint[] rewardPending;
        uint[] rewardHarvested;
        int feeFirst;
        uint liquidity;
    }

    // input data in harvestMultiplePools function
    struct HarvestData {
        uint[] pIds;
    }

    // avoid stack too deep error
    struct RewardCalculationData {
        uint128 secondsPerLiquidityNow;
        int feeNow;
        uint vestingVolume;
        uint totalSecondsUnclaimed;
        uint secondsPerLiquidity;
        uint secondsClaim; // scaled by (1 << 96)
    }

    // nftId => Position info
    function positions(uint nftId) external view returns (PositionInfo memory);

    function admin() external view returns (address);

    function updateOperator(address user, bool grantOrRevoke) external;

    /**
     * @dev Add new pool to LM
     * @param poolAddr pool address
     * @param startTime start time of liquidity mining
     * @param endTime end time of liquidity mining
     * @param rewardTokens reward token list for pool
     * @param rewardAmounts reward amount of list token
     * @param feeTarget fee target for pool
     *
     */
    function addPool(
        address poolAddr,
        uint32 startTime,
        uint32 endTime,
        address[] calldata rewardTokens,
        uint[] calldata rewardAmounts,
        uint feeTarget
    ) external;

    /**
     * @dev Renew a pool to start another LM program
     * @param pId pool id to update
     * @param startTime start time of liquidity mining
     * @param endTime end time of liquidity mining
     * @param rewardAmounts reward amount of list token
     * @param feeTarget fee target for pool
     *
     */
    function renewPool(
        uint pId,
        uint32 startTime,
        uint32 endTime,
        uint[] calldata rewardAmounts,
        uint feeTarget
    ) external;

    /**
     * @dev Deposit NFT
     * @param nftIds list nft id
     *
     */
    function deposit(uint[] calldata nftIds) external;

    /**
     * @dev Deposit NFTs into the pool and join farms if applicable
     * @param pId pool id to join farm
     * @param nftIds List of NFT ids from BasePositionManager, should match with the pId
     *
     */
    function depositAndJoin(uint pId, uint[] calldata nftIds) external;

    /**
     * @dev Withdraw NFT, must exit all pool before call.
     * @param nftIds list nft id
     *
     */
    function withdraw(uint[] calldata nftIds) external;

    /**
     * @dev Join pools
     * @param pId pool id to join
     * @param nftIds nfts to join
     * @param liqs list liquidity value to join each nft
     *
     */
    function join(uint pId, uint[] calldata nftIds, uint[] calldata liqs) external;

    /**
     * @dev Exit from pools
     * @param pId pool ids to exit
     * @param nftIds list nfts id
     * @param liqs list liquidity value to exit from each nft
     *
     */
    function exit(uint pId, uint[] calldata nftIds, uint[] calldata liqs) external;

    /**
     * @dev Claim rewards for a list of pools for a list of nft positions
     * @param nftIds List of NFT ids to harvest
     * @param datas List of pool ids to harvest for each nftId, encoded into bytes
     */
    function harvestMultiplePools(uint[] calldata nftIds, bytes[] calldata datas) external;

    /**
     * @dev remove liquidity from elastic for a list of nft position, also update on farm
     * @param nftId to remove
     * @param liquidity liquidity amount to remove from nft
     * @param amount0Min expected min amount of token0 should receive
     * @param amount1Min expected min amount of token1 should receive
     * @param deadline deadline of this tx
     * @param isReceiveNative should unwrap native or not
     * @param claimFeeAndRewards also claim LP Fee and farm rewards
     */
    function removeLiquidity(
        uint nftId,
        uint128 liquidity,
        uint amount0Min,
        uint amount1Min,
        uint deadline,
        bool isReceiveNative,
        bool[2] calldata claimFeeAndRewards
    ) external;

    /**
     * @dev Claim fee from elastic for a list of nft positions
     * @param nftIds List of NFT ids to claim
     * @param amount0Min expected min amount of token0 should receive
     * @param amount1Min expected min amount of token1 should receive
     * @param poolAddress address of Elastic pool of those nfts
     * @param isReceiveNative should unwrap native or not
     * @param deadline deadline of this tx
     */
    function claimFee(
        uint[] calldata nftIds,
        uint amount0Min,
        uint amount1Min,
        address poolAddress,
        bool isReceiveNative,
        uint deadline
    ) external;

    /**
     * @dev Operator only. Call to withdraw all reward from list pools.
     * @param rewards list reward address erc20 token
     * @param amounts amount to withdraw
     *
     */
    function emergencyWithdrawForOwner(address[] calldata rewards, uint[] calldata amounts) external;

    /**
     * @dev Withdraw NFT, can call any time, reward will be reset. Must enable this func by operator
     * @param pIds list pool to withdraw
     *
     */
    function emergencyWithdraw(uint[] calldata pIds) external;

    /**
     * @dev get list of pool that this nft joined
     * @param nftId to get
     */
    function getJoinedPools(uint nftId) external view returns (uint[] memory poolIds);

    /**
     * @dev get list of pool that this nft joined, only in a specific range
     * @param nftId to get
     * @param fromIndex index from
     * @param toIndex index to
     */
    function getJoinedPoolsInRange(
        uint nftId,
        uint fromIndex,
        uint toIndex
    ) external view returns (uint[] memory poolIds);

    /**
     * @dev get user's info (staked info) of a nft in a pool
     * @param nftId to get
     * @param pId to get
     */
    function getUserInfo(
        uint nftId,
        uint pId
    ) external view returns (uint liquidity, uint[] memory rewardPending, uint[] memory rewardLast);

    /**
     * @dev get pool info
     * @param pId to get
     */
    function getPoolInfo(uint pId)
        external
        view
        returns (
            address poolAddress,
            uint32 startTime,
            uint32 endTime,
            uint totalSecondsClaimed,
            uint feeTarget,
            uint numStakes,
            //index reward => reward data
            address[] memory rewardTokens,
            uint[] memory rewardUnclaimeds
        );

    /**
     * @dev get list of deposited nfts of an address
     * @param user address of user to get
     */
    function getDepositedNFTs(address user) external view returns (uint[] memory listNFTs);

    function nft() external view returns (address);

    function poolLength() external view returns (uint);

    function getRewardCalculationData(uint nftId, uint pId) external view returns (RewardCalculationData memory data);
}
