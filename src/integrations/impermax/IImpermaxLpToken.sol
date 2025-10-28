// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IImpermaxLpToken {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Mint(
        address indexed sender,
        address indexed minter,
        uint256 mintAmount,
        uint256 mintTokens
    );
    event Redeem(
        address indexed sender,
        address indexed redeemer,
        uint256 redeemAmount,
        uint256 redeemTokens
    );
    event Reinvest(address indexed caller, uint256 reward, uint256 bounty);
    event Sync(uint256 totalBalance);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function MINIMUM_LIQUIDITY() external view returns (uint256);

    function PERMIT_TYPEHASH() external view returns (bytes32);

    function REINVEST_BOUNTY() external view returns (uint256);

    function _initialize(
        address _underlying,
        address _token0,
        address _token1,
        address _router,
        address _voter,
        address _rewardsToken,
        address _rewardsToken1,
        address[] memory _bridgeTokens
    ) external;

    function _setFactory() external;

    function allowance(address, address) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function balanceOf(address) external view returns (uint256);

    function bridgeTokens(uint256) external view returns (address);

    function currentCumulativePrices()
    external
    view
    returns (
        uint256 reserve0Cumulative,
        uint256 reserve1Cumulative,
        uint256 timestamp
    );

    function decimals() external view returns (uint8);

    function exchangeRate() external returns (uint256);

    function factory() external view returns (address);

    function gauge() external view returns (address);

    function getReserves()
    external
    view
    returns (
        uint112 reserve0,
        uint112 reserve1,
        uint32 blockTimestampLast
    );

    function getReward() external returns (uint256);

    function isStakedLPToken() external view returns (bool);

    function mint(address minter) external returns (uint256 mintTokens);

    function name() external view returns (string memory);

    function nonces(address) external view returns (uint256);

    function observationLength() external view returns (uint256);

    function observations(uint256 index)
    external
    view
    returns (
        uint256 timestamp,
        uint256 reserve0Cumulative,
        uint256 reserve1Cumulative
    );

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function redeem(address redeemer) external returns (uint256 redeemAmount);

    function reinvest() external;

    function rewardsToken() external view returns (address);

    function rewardsToken1() external view returns (address);

    function router() external view returns (address);

    function skim(address to) external;

    function stable() external view returns (bool);

    function stakedLPTokenType() external view returns (string memory);

    function symbol() external view returns (string memory);

    function sync() external;

    function token0() external view returns (address);

    function token1() external view returns (address);

    function totalBalance() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function underlying() external view returns (address);
}

