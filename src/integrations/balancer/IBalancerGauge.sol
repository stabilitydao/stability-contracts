// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

/// @notice gauge-v2, see 0xc9b36096f5201ea332Db35d6D195774ea0D5988f
/// @dev see 20230316-child-chain-gauge-factory-v2 in balancer-deployments repository
interface IBalancerGauge {
    event Approval(address indexed _owner, address indexed _spender, uint _value);
    event Transfer(address indexed _from, address indexed _to, uint _value);
    event Deposit(address indexed _user, uint _value);
    event Withdraw(address indexed _user, uint _value);
    event UpdateLiquidityLimit(
        address indexed _user,
        uint _original_balance,
        uint _original_supply,
        uint _working_balance,
        uint _working_supply
    );

    function deposit(uint _value) external;

    function deposit(uint _value, address _user) external;

    function withdraw(uint _value) external;

    function withdraw(uint _value, address _user) external;

    function transferFrom(address _from, address _to, uint _value) external returns (bool);

    function approve(address _spender, uint _value) external returns (bool);

    function permit(
        address _owner,
        address _spender,
        uint _value,
        uint _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (bool);

    function transfer(address _to, uint _value) external returns (bool);

    function increaseAllowance(address _spender, uint _added_value) external returns (bool);

    function decreaseAllowance(address _spender, uint _subtracted_value) external returns (bool);

    function user_checkpoint(address addr) external returns (bool);

    function claimable_tokens(address addr) external returns (uint);

    function claimed_reward(address _addr, address _token) external view returns (uint);

    function claimable_reward(address _user, address _reward_token) external view returns (uint);

    function set_rewards_receiver(address _receiver) external;

    function claim_rewards() external;

    function claim_rewards(address _addr) external;

    function claim_rewards(address _addr, address _receiver) external;

    function claim_rewards(address _addr, address _receiver, uint[] memory _reward_indexes) external;

    function add_reward(address _reward_token, address _distributor) external;

    function set_reward_distributor(address _reward_token, address _distributor) external;

    function deposit_reward_token(address _reward_token, uint _amount) external;

    function killGauge() external;

    function unkillGauge() external;

    function decimals() external view returns (uint);

    function allowance(address owner, address spender) external view returns (uint);

    function integrate_checkpoint() external view returns (uint);

    function bal_token() external view returns (address);

    function bal_pseudo_minter() external view returns (address);

    function voting_escrow_delegation_proxy() external view returns (address);

    function authorizer_adaptor() external view returns (address);

    function initialize(address _lp_token, string memory _version) external;

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function nonces(address arg0) external view returns (uint);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function balanceOf(address arg0) external view returns (uint);

    function totalSupply() external view returns (uint);

    function lp_token() external view returns (address);

    function version() external view returns (string memory);

    function factory() external view returns (address);

    function working_balances(address arg0) external view returns (uint);

    function working_supply() external view returns (uint);

    function period() external view returns (uint);

    function period_timestamp(uint arg0) external view returns (uint);

    function integrate_checkpoint_of(address arg0) external view returns (uint);

    function integrate_fraction(address arg0) external view returns (uint);

    function integrate_inv_supply(uint arg0) external view returns (uint);

    function integrate_inv_supply_of(address arg0) external view returns (uint);

    function reward_count() external view returns (uint);

    function reward_tokens(uint arg0) external view returns (address);

    function reward_data(address arg0) external view returns (S_0 memory);

    function rewards_receiver(address arg0) external view returns (address);

    function reward_integral_for(address arg0, address arg1) external view returns (uint);

    function is_killed() external view returns (bool);

    function inflation_rate(uint arg0) external view returns (uint);
}

struct S_0 {
    address distributor;
    uint period_finish;
    uint rate;
    uint last_update;
    uint integral;
}
