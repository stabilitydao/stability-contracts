// SPDX-License-Identifier: ISC
pragma solidity ^0.8.23;

interface IBalancerHelper {
    function queryExit(
        bytes32 poolId,
        address sender,
        address recipient,
        IVault.JoinPoolRequest memory request
    ) external returns (uint bptIn, uint[] memory amountsOut);

    function queryJoin(
        bytes32 poolId,
        address sender,
        address recipient,
        IVault.JoinPoolRequest memory request
    ) external returns (uint bptOut, uint[] memory amountsIn);

    function vault() external view returns (address);
}

interface IVault {
    struct JoinPoolRequest {
        address[] assets;
        uint[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }
}
