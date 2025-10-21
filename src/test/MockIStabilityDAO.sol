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
    function config() external pure returns (DaoParams memory dest) {
        return dest;
    }

    function xStbl() external pure returns (address dest) {
        return dest;
    }

    function xStaking() external pure returns (address dest) {
        return dest;
    }

    function minimalPower() external pure returns (uint dest) {
        return dest;
    }

    function exitPenalty() external pure returns (uint dest) {
        return dest;
    }

    function proposalThreshold() external pure returns (uint dest) {
        return dest;
    }

    function quorum() external view returns (uint dest) {
        return dest;
    }

    function powerAllocationDelay() external view returns (uint dest) {
        return dest;
    }

    function userPower(address user_) external view returns (uint dest) {
        return dest;
    }

    function delegates(address user_) external view returns (address delegatedTo, address[] memory delegatedFrom) {
        return (delegatedTo, delegatedFrom);
    }

    //endregion --------------------------------------- Read functions

    //region --------------------------------------- Write functions
    function initialize(
        address, /*platform_*/
        address, /*xStbl_*/
        address, /*xStaking_*/
        DaoParams memory /*config_*/
    ) external {}

    function updateConfig(DaoParams memory) external {}

    function mint(address, /*account*/ uint /*amount*/ ) external {}

    function burn(address, /*account*/ uint /*amount*/ ) external {}

    function setPowerDelegation(address /*to*/) external {}
    //endregion --------------------------------------- Write functions
}
