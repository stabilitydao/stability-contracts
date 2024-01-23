// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IICHIVaultFactory {
    function algebraFactory() external view returns(address);
    function feeRecipient() external view returns(address);
    function ammFeeRecipient() external view returns(address);
    function ammFee() external view returns(uint256);
    function baseFee() external view returns(uint256);
    function baseFeeSplit() external view returns(uint256);
    
    function setFeeRecipient(address _feeRecipient) external;
    function setAmmFeeRecipient(address _ammFeeRecipient) external;
    function setAmmFee(uint256 _ammFee) external;
    function setBaseFee(uint256 _baseFee) external;
    function setBaseFeeSplit(uint256 _baseFeeSplit) external;

    function createICHIVault(
        address tokenA,
        bool allowTokenA,
        address tokenB,
        bool allowTokenB
    ) external returns (address ichiVault);

    function genKey(
        address deployer, 
        address token0, 
        address token1, 
        bool allowToken0, 
        bool allowToken1) external pure returns(bytes32 key);
}