// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IImpermaxFactory {
    event LendingPoolInitialized(
        address indexed uniswapV2Pair,
        address indexed token0,
        address indexed token1,
        address collateral,
        address borrowable0,
        address borrowable1,
        uint256 lendingPoolId
    );
    event NewAdmin(address oldAdmin, address newAdmin);
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);
    event NewReservesAdmin(address oldReservesAdmin, address newReservesAdmin);
    event NewReservesManager(
        address oldReservesManager,
        address newReservesManager
    );
    event NewReservesPendingAdmin(
        address oldReservesPendingAdmin,
        address newReservesPendingAdmin
    );

    function _acceptAdmin() external;

    function _acceptReservesAdmin() external;

    function _setPendingAdmin(address newPendingAdmin) external;

    function _setReservesManager(address newReservesManager) external;

    function _setReservesPendingAdmin(address newReservesPendingAdmin) external;

    function admin() external view returns (address);

    function allLendingPools(uint256) external view returns (address);

    function allLendingPoolsLength() external view returns (uint256);

    function bDeployer() external view returns (address);

    function cDeployer() external view returns (address);

    function createBorrowable0(address uniswapV2Pair)
    external
    returns (address borrowable0);

    function createBorrowable1(address uniswapV2Pair)
    external
    returns (address borrowable1);

    function createCollateral(address uniswapV2Pair)
    external
    returns (address collateral);

    function getLendingPool(address)
    external
    view
    returns (
        bool initialized,
        uint24 lendingPoolId,
        address collateral,
        address borrowable0,
        address borrowable1
    );

    function initializeLendingPool(address uniswapV2Pair) external;

    function pendingAdmin() external view returns (address);

    function reservesAdmin() external view returns (address);

    function reservesManager() external view returns (address);

    function reservesPendingAdmin() external view returns (address);
}
