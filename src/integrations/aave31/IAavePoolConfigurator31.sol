// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAavePoolConfigurator31 {
    struct InitReserveInput {
        address aTokenImpl;
        address variableDebtTokenImpl;
        address underlyingAsset;
        string aTokenName;
        string aTokenSymbol;
        string variableDebtTokenName;
        string variableDebtTokenSymbol;
        bytes params;
        bytes interestRateData;
    }

    struct UpdateATokenInput {
        address asset;
        string name;
        string symbol;
        address implementation;
        bytes params;
    }

    struct UpdateDebtTokenInput {
        address asset;
        string name;
        string symbol;
        address implementation;
        bytes params;
    }

    
    function CONFIGURATOR_REVISION() external view returns (uint256);

    function MAX_GRACE_PERIOD() external view returns (uint40);

    function configureReserveAsCollateral(
        address asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external;

    function disableLiquidationGracePeriod(address asset) external;

    function dropReserve(address asset) external;

    function getConfiguratorLogic() external pure returns (address);

    function getPendingLtv(address asset) external view returns (uint256);

    function initReserves(
        InitReserveInput[] memory input
    ) external;

    function initialize(address provider) external;

    function setAssetBorrowableInEMode(
        address asset,
        uint8 categoryId,
        bool borrowable
    ) external;

    function setAssetCollateralInEMode(
        address asset,
        uint8 categoryId,
        bool allowed
    ) external;

    function setBorrowCap(address asset, uint256 newBorrowCap) external;

    function setBorrowableInIsolation(address asset, bool borrowable) external;

    function setDebtCeiling(address asset, uint256 newDebtCeiling) external;

    function setEModeCategory(
        uint8 categoryId,
        uint16 ltv,
        uint16 liquidationThreshold,
        uint16 liquidationBonus,
        string memory label
    ) external;

    function setLiquidationProtocolFee(address asset, uint256 newFee) external;

    function setPoolPause(bool paused, uint40 gracePeriod) external;

    function setPoolPause(bool paused) external;

    function setReserveActive(address asset, bool active) external;

    function setReserveBorrowing(address asset, bool enabled) external;

    function setReserveFactor(address asset, uint256 newReserveFactor) external;

    function setReserveFlashLoaning(address asset, bool enabled) external;

    function setReserveFreeze(address asset, bool freeze) external;

    function setReserveInterestRateData(address asset, bytes memory rateData) external;

    function setReservePause(address asset, bool paused) external;

    function setReservePause(
        address asset,
        bool paused,
        uint40 gracePeriod
    ) external;

    function setSiloedBorrowing(address asset, bool newSiloed) external;

    function setSupplyCap(address asset, uint256 newSupplyCap) external;

    function updateAToken(UpdateATokenInput memory input)
    external;

    function updateFlashloanPremium(uint128 newFlashloanPremium) external;

    function updateVariableDebtToken(
        UpdateDebtTokenInput memory input
    ) external;
}