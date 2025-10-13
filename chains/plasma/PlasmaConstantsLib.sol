// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library PlasmaConstantsLib {
    address public constant MULTISIG = 0xE929438B5B53984FdBABf8562046e141e90E8099;
    address public constant PLATFORM = 0x06e709798dCE60B24a442F3AF5db418B5D388e7C;

    // ERC20
    address public constant TOKEN_USDT0 = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;
    address public constant TOKEN_USDE = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;
    address public constant TOKEN_SUSDE = 0x211Cc4DD073734dA055fbF44a2b4667d5E5fE5d2;
    address public constant TOKEN_WETH = 0x9895D81bB462A195b4922ED7De0e3ACD007c32CB;
    address public constant TOKEN_WEETH = 0xA3D68b74bF0528fdD07263c60d6488749044914b;
    address public constant TOKEN_WXPL = 0x6100E367285b01F48D07953803A2d8dCA5D19873;

    // @notice https://docs.euler.finance/EUL/addresses
    address public constant TOKEN_EUL = 0xca632FA58397391C750c13F935DAA61AbBe0BaA6;
    address public constant TOKEN_REUL = 0xe2011F2bF6556863c3bacE991Efc8DaC26CD84c2;

    // Oracles
    // address public constant ORACLE_CHAINLINK_USDT0_USD = 0xdBbB0b5DD13E7AC9C56624834ef193df87b022c3;
    address public constant ORACLE_CHAINLINK_USDT0_USD = 0x70b77FcdbE2293423e41AdD2FB599808396807BC;
    address public constant ORACLE_CHAINLINK_ETH_USD = 0x43A7dd2125266c5c4c26EB86cd61241132426Fe7;

    // AMMs
    address public constant POOL_BALANCER_V3_RECLAMM_WXPL_USDT0 = 0xe14Ba497A7C51f34896D327ec075F3F18210a270;

    // Merkl
    address public constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

    // Balancer
    address public constant BALANCER_V3_ROUTER = 0x9dA18982a33FD0c7051B19F0d7C76F2d5E7e017c;

    // Euler: todo we need new strategy
    /// @notice https://app.euler.finance/earn/0xe818ad0D20D504C55601b9d5e0E137314414dec4?network=plasma
    address public constant EULER_MERKL_USDT0_K3_CAPITAL = 0xe818ad0D20D504C55601b9d5e0E137314414dec4;
    address public constant EULER_MERKL_USDT0_RE7 = 0xa5EeD1615cd883dD6883ca3a385F525e3bEB4E79;

    // AAVE
    address public constant AAVE_V3_POOL = 0x925a2A7214Ed92428B5b1B090F80b25700095e12;
    address public constant AAVE_V3_POOL_USDT0 = 0x5D72a9d9A9510Cd8cBdBA12aC62593A58930a948;
}
