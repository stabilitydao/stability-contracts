// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IStabilityDAO} from "../interfaces/IStabilityDAO.sol";

contract MockStabilityDAO is IStabilityDAO {
    /// @notice add this to be excluded from coverage report
    function test() public {}

    function totalSupply() external pure override returns (uint) {
        return 0;
    }

    function balanceOf(address) external pure override returns (uint) {
        return 0;
    }

    function transfer(address, uint) external pure override returns (bool) {
        return true;
    }

    function allowance(address, address) external pure override returns (uint) {
        return 0;
    }

    function approve(address, uint) external pure override returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint) external pure override returns (bool) {
        return true;
    }

    function name() external pure override returns (string memory) {
        return "Mock";
    }

    function symbol() external pure override returns (string memory) {
        return "MOCK";
    }

    function decimals() external pure override returns (uint8) {
        return 18;
    }

    //region --------------------------------------- Read functions
    /// @notice Current DAO config
    function config() external pure returns (DaoParams memory dest) {
        return dest;
    }

    /// @notice Address of xSTBL token
    function xStbl() external pure returns (address dest) {
        return dest;
    }

    /// @notice Address of xStaking contract
    function xStaking() external pure returns (address dest) {
        return dest;
    }

    /// @notice TODO
    function minimalPower() external pure returns (uint dest) {
        return dest;
    }

    /// @notice TODO
    function exitPenalty() external pure returns (uint dest) {
        return dest;
    }

    /// @notice TODO
    function proposalThreshold() external pure returns (uint dest) {
        return dest;
    }

    /// @notice TODO
    function powerAllocationDelay() external pure returns (uint dest) {
        return dest;
    }

    //endregion --------------------------------------- Read functions

    //region --------------------------------------- Write functions
    /// @dev Init
    function initialize(
        address, /*platform_*/
        address, /*xStbl_*/
        address, /*xStaking_*/
        DaoParams memory /*config_*/
    ) external {}

    /// @notice Update DAO config
    /// @custom:restricted To multisig
    function updateConfig(DaoParams memory) external {}

    /// @custom:restricted To xStaking
    function mint(address, /*account*/ uint /*amount*/ ) external {}

    /// @custom:restricted To xStaking
    function burn(address, /*account*/ uint /*amount*/ ) external {}
    //endregion --------------------------------------- Write functions
}
