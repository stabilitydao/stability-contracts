// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library AvalancheConstantsLib {
    // initial addresses
    address public constant MULTISIG = 0x06111E02BEb85B57caebEf15F5f90Bc82D54da3A;
    address public constant PLATFORM = 0x72b931a12aaCDa6729b4f8f76454855CB5195941;
    address public constant METAVAULT_FACTORY = 0x2FA6cc5E1dc2F6Dd8806a3969f2E7fcBf5f75e89;
    address public constant FACTORY = 0xE9D2FCaD6b691a1642587a2B61886a173632ed00;

    // ERC20
    address public constant TOKEN_USDC = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address public constant TOKEN_USDT = 0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7;
    address public constant TOKEN_DAI = 0xd586E7F844cEa2F87f50152665BCbc2C279D8d70;
    address public constant TOKEN_WETH = 0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB;
    address public constant TOKEN_WBTC = 0x50b7545627a5162F82A992c33b87aDc75187B218;
    address public constant TOKEN_BTCB = 0x152b9d0FdC40C096757F570A51E494bd4b943E50;
    address public constant TOKEN_WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address public constant TOKEN_REUL = 0x2e3b32730B4F6b6502BdAa9122df3B026eDE5391;
    address public constant TOKEN_EUL = 0x9ceeD3A7f753608372eeAb300486cc7c2F38AC68;
    address public constant TOKEN_AUSD = 0x00000000eFE302BEAA2b3e6e1b18d08D69a9012a;
    address public constant TOKEN_xBTC = 0x6eAf19b2FC24552925dB245F9Ff613157a7dbb4C;
    address public constant TOKEN_savBTS = 0x649342c6bff544d82DF1B2bA3C93e0C22cDeBa84;
    address public constant TOKEN_savUSDC = 0x06d47F3fb376649c3A9Dafe069B3D6E35572219E;

    // Oracles
    address public constant ORACLE_CHAINLINK_USDC_USD = 0xF096872672F44d6EBA71458D74fe67F9a77a23B9;
    address public constant ORACLE_CHAINLINK_USDT_USD = 0xEBE676ee90Fe1112671f19b6B7459bC678B67e8a;
    address public constant ORACLE_CHAINLINK_BTC_USD = 0x2779D32d5166BAaa2B2b658333bA7e6Ec0C65743;
    address public constant ORACLE_CHAINLINK_WBTC_USD = 0x86442E3a98558357d46E6182F4b262f76c4fa26F;
    address public constant ORACLE_CHAINLINK_ETH_USD = 0x976B3D034E162d8bD72D6b9C989d545b839003b0;
    address public constant ORACLE_CHAINLINK_AVAX_USD = 0x0A77230d17318075983913bC2145DB16C7366156;

    // AMMs
    address public constant POOL_BLACKHOLE_CL_WAVAX_USDC = 0x41100C6D2c6920B10d12Cd8D59c8A9AA2eF56fC7;
    address public constant POOL_BLACKHOLE_CL_USDT_USDC = 0x859592A4A469610E573f96Ef87A0e5565F9a94c8;
    address public constant POOL_BLACKHOLE_CL_WBTC_BTCB = 0xfc231423E1a863d94Abb21D9f68e8C2589B3Edb9;
    address public constant POOL_BLACKHOLE_CL_BTCB_WAVAX = 0x8FEF4fE4970a5D6bFa7C65871a2EbFD0F42aa822;
    address public constant POOL_BLACKHOLE_CL_WETH_WAVAX = 0x5E128EbC09C918DDAE3Ca1668d4EE9527dc00D78;
    address public constant POOL_BLACKHOLE_CL_AUSD_USDC = 0x10Ed86c3D147dCd4bdecACfF5aDA625328B9678D;

    // Merkl
    address public constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

    // Euler
    address public constant EULER_VAULT_USDT_K3 = 0xa446938b0204Aa4055cdFEd68Ddf0E0d1BAB3E9E;
    address public constant EULER_VAULT_USDC_RE7 = 0x39dE0f00189306062D79eDEC6DcA5bb6bFd108f9;
    address public constant EULER_VAULT_BTCB_RESERVOIR = 0x04293b180bf9C57eD0923C99c784Cb571f0A9Ae9;
    address public constant EULER_VAULT_WBTC_RESERVOIR = 0xA321a38b03a7218157668a724E186f3a81CF56c8;

    // AAVE v3
    address public constant AAVE_V3_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address public constant AAVE_aAvaUSDC = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;

    // Silo
    address public constant SILO_VAULT_USDC_125 = 0xE0345f66318F482aCCcd67244A921C7FDC410957;
    address public constant SILO_VAULT_BTCb_130 = 0x7437ac81457Fa98fFB2d0C8f9943ecfE4813e2f1;
    address public constant SILO_VAULT_BTCb_121 = 0xD8a26DFEba3E9B558Bd79d10722636Dfb4dc2bF4;
    address public constant SILO_VAULT_USDC_142 = 0x606fe9a70338e798a292CA22C1F28C829F24048E;
    address public constant SILO_VAULT_USDC_129 = 0x672b77f0538b53Dc117C9dDfEb7377A678d321a6;

    address public constant SILO_MANAGED_VAULT_USDC_MEV = 0x4dc1ce9b9f9EF00c144BfAD305f16c62293dC0E8;
    address public constant SILO_MANAGED_VAULT_BTCb_MEV = 0x1f8E769B5B6010B2C2BBCd68629EA1a0a0Eda7E3;
    address public constant SILO_MANAGED_VAULT_AUSD_VARLAMOURE = 0x3d7B0c3997E48fA3FC96cd057d1fb4E5F891835B;
    address public constant SILO_MANAGED_VAULT_USDt_VARLAMOURE = 0x6c09bfdc1df45D6c4Ff78Dc9F1C13aF29eB335d4;

    // ---------------------------------- LayerZero-v2 https://docs.layerzero.network/v2/deployments/chains/avalanche
    uint32 public constant LAYER_ZERO_V2_ENDPOINT_ID = 30106;
    address public constant LAYER_ZERO_V2_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address public constant LAYER_ZERO_V2_SEND_ULN_302 = 0x197D1333DEA5Fe0D6600E9b396c7f1B1cFCc558a;
    address public constant LAYER_ZERO_V2_RECEIVE_ULN_302 = 0xbf3521d309642FA9B1c91A08609505BA09752c61;
    address public constant LAYER_ZERO_V2_READ_LIB_1002 = 0x8839D3f169f473193423b402BDC4B5c51daAABDc;
    address public constant LAYER_ZERO_V2_EXECUTOR = 0x90E595783E43eb89fF07f63d27B8430e6B44bD9c;
    address public constant LAYER_ZERO_V2_BLOCKED_MESSAGE_LIBRARY = 0x1ccBf0db9C192d969de57E25B3fF09A25bb1D862;
    address public constant LAYER_ZERO_V2_DEAD_DVN = 0x90cCA24D1338Bd284C25776D9c12f96764Bde5e1;

    // DeX aggregators
    /// @notice Aggregator router V6
    /// @dev https://portal.1inch.dev/documentation/contracts/aggregation-protocol/aggregation-introduction
    address public constant ONE_INCH = 0x111111125421cA6dc452d289314280a0f8842A65;
//    /// @notice Aggregator router V5
//    address public constant ONE_INCH = 0x1111111254EEB25477B68fb85Ed929f73A960582;

}
