// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRecovery} from "../interfaces/IRecovery.sol";

contract MockRecovery is IRecovery {
    address[] public registeredTokens;

    // add this to be excluded from coverage report
    function test() public {}

    function registeredTokensLength() external view returns (uint) {
        return registeredTokens.length;
    }

    function initialize(address platform_) external pure override {
        platform_;
    }

    function recoveryPools() external pure override returns (address[] memory) {
        address[] memory pools;
        return pools;
    }

    function threshold(address token) external pure override returns (uint) {
        token;
        return 0;
    }

    function whitelisted(address operator_) external pure override returns (bool) {
        operator_;
        return false;
    }

    function addRecoveryPools(address[] memory recoveryPools_) external pure override {
        recoveryPools_;
    }

    function removeRecoveryPool(address pool_) external pure override {
        pool_;
    }

    function setThresholds(address[] memory tokens, uint[] memory thresholds) external pure override {
        tokens;
        thresholds;
    }

    function changeWhitelist(address operator_, bool add_) external pure override {
        operator_;
        add_;
    }

    function registerAssets(address[] memory tokens) external override {
        registeredTokens = tokens;
    }

    function swapAssetsToRecoveryTokens(uint indexFirstRecoveryPool1) external pure override {
        indexFirstRecoveryPool1;
    }

    function isTokenRegistered(address token) external view override returns (bool) {
        for (uint i; i < registeredTokens.length; ++i) {
            if (registeredTokens[i] == token) {
                return true;
            }
        }
        return false;
    }
}
