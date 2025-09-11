// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Restored from Sonic.0x9a8ff151bda518ece44cb1125f368f4c893d63b7
interface IPendleCommonPoolDeployHelperV2 {
    event Initialized(uint8 version);
    event MarketDeployment(
        PoolDeploymentAddrs addrs,
        PoolDeploymentParams params
    );
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    function ERC20_DEPLOY_ID() external view returns (bytes32);

    function ERC20_WITH_ADAPTER_ID() external view returns (bytes32);

    function ERC4626_DEPLOY_ID() external view returns (bytes32);

    function ERC4626_NOT_REDEEMABLE_DEPLOY_ID() external view returns (bytes32);

    function ERC4626_NO_REDEEM_WITH_ADAPTER_ID()
    external
    view
    returns (bytes32);

    function ERC4626_WITH_ADAPTER_ID() external view returns (bytes32);

    function claimOwnership() external;

    function deploy5115MarketAndSeedLiquidity(
        address SY,
        PoolConfig memory config,
        address tokenToSeedLiqudity,
        uint256 amountToSeed
    )
    external
    payable
    returns (PoolDeploymentAddrs memory);

    function deployERC20Market(
        bytes memory constructorParams,
        PoolConfig memory config,
        address tokenToSeedLiqudity,
        uint256 amountToSeed,
        address syOwner
    ) external returns (PoolDeploymentAddrs memory);

    function deployERC20WithAdapterMarket(
        bytes memory constructorParams,
        bytes memory initData,
        PoolConfig memory config,
        address tokenToSeedLiqudity,
        uint256 amountToSeed,
        address syOwner
    ) external returns (PoolDeploymentAddrs memory);

    function deployERC4626Market(
        bytes memory constructorParams,
        PoolConfig memory config,
        address tokenToSeedLiqudity,
        uint256 amountToSeed,
        address syOwner
    ) external returns (PoolDeploymentAddrs memory);

    function deployERC4626NoRedeemWithAdapterMarket(
        bytes memory constructorParams,
        bytes memory initData,
        PoolConfig memory config,
        address tokenToSeedLiqudity,
        uint256 amountToSeed,
        address syOwner
    ) external returns (PoolDeploymentAddrs memory);

    function deployERC4626NotRedeemableMarket(
        bytes memory constructorParams,
        PoolConfig memory config,
        address tokenToSeedLiqudity,
        uint256 amountToSeed,
        address syOwner
    ) external returns (PoolDeploymentAddrs memory);

    function deployERC4626WithAdapterMarket(
        bytes memory constructorParams,
        bytes memory initData,
        PoolConfig memory config,
        address tokenToSeedLiqudity,
        uint256 amountToSeed,
        address syOwner
    ) external returns (PoolDeploymentAddrs memory);

    function doCacheIndexSameBlock() external view returns (bool);

    function initialize(address _owner) external;

    function marketFactory() external view returns (address);

    function owner() external view returns (address);

    function pendingOwner() external view returns (address);

    function router() external view returns (address);

    function syFactory() external view returns (address);

    function transferOwnership(
        address newOwner,
        bool direct,
        bool renounce
    ) external;

    function yieldContractFactory() external view returns (address);

    struct PoolDeploymentAddrs {
        address SY;
        address PT;
        address YT;
        address market;
    }

    struct PoolDeploymentParams {
        uint32 expiry;
        uint80 lnFeeRateRoot;
        int256 scalarRoot;
        int256 initialRateAnchor;
        bool doCacheIndexSameBlock;
    }

    struct PoolConfig {
        uint32 expiry;
        uint256 rateMin;
        uint256 rateMax;
        uint256 desiredImpliedRate;
        uint256 fee;
    }
}
