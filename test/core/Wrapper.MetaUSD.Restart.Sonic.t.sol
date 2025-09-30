// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {RecoveryToken} from "../../src/core/vaults/RecoveryToken.sol";
import {AaveMerklFarmStrategy} from "../../src/strategies/AaveMerklFarmStrategy.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {IAToken} from "../../src/integrations/aave/IAToken.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IRecoveryToken} from "../../src/interfaces/IRecoveryToken.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";
import {MetaVaultFactory} from "../../src/core/MetaVaultFactory.sol";
import {console, Test} from "forge-std/Test.sol";
import {Factory} from "../../src/core/Factory.sol";
import {IProxy} from "../../src/interfaces/IProxy.sol";

contract WrapperMetaUsdRestartSonicTest is Test {
    // uint public constant FORK_BLOCK = 42601861; // Aug-12-2025 03:58:17 AM +UTC
    // uint public constant FORK_BLOCK = 42622282; // Aug-12-2025 07:58:50 AM +UTC
    uint public constant FORK_BLOCK = 42789000; // Aug-13-2025 10:30:56 AM +UTC

    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVaultFactory public metaVaultFactory;
    IPriceReader public priceReader;
    address public multisig;
    IWrappedMetaVault public wrappedMetaVault;

    uint internal constant COUNT_WRAPPED_META_USD_USERS = 26;
    uint internal constant COUNT_META_USD_USERS = 36;
    uint internal constant COUNT_WRAPPED_META_USDC_USERS = 33;
    uint internal constant COUNT_WRAPPED_META_SCUSD_USERS = 55;
    uint internal constant COUNT_META_SCUSD_USERS = 2;

    address[COUNT_WRAPPED_META_USD_USERS] internal WRAPPED_META_USD_LARGEST_HOLDERS;
    address[COUNT_META_USD_USERS] internal META_USD_LARGEST_HOLDERS;
    address[COUNT_WRAPPED_META_USDC_USERS] internal WRAPPED_META_USDC_LARGEST_HOLDERS;
    // address[] internal constant META_USDC_LARGEST_HOLDERS;  // no holders
    address[COUNT_WRAPPED_META_SCUSD_USERS] internal WRAPPED_META_SCUSD_LARGEST_HOLDERS;
    address[COUNT_META_SCUSD_USERS] internal META_SCUSD_LARGEST_HOLDERS;

    // broken vaults in metaUSDC
    address public constant VAULT_1_USDC = SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0;
    address public constant VAULT_2_USDC = SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA5;

    // broken vaults in metascUSD
    address public constant VAULT_3_SCUSD = SonicConstantsLib.VAULT_C_CREDIX_SCUSD_AMFA0;
    address public constant VAULT_4_SCUSD = SonicConstantsLib.VAULT_C_CREDIX_SCUSD_AMFA5;

    address[4] internal CREDIX_VAULTS;

    /// @notice [WMetaUSD, WMetaUsdc, WMetaScUSD, MetaUSD, MetaUsdc, MetaScUSD]
    address[] internal recoveryTokens;

    /// @notice [WMetaUSD, WMetaUsdc, WMetaScUSD, MetaUSD, MetaUsdc, MetaScUSD]
    address[6] internal SMALL_USERS;

    struct UserAddresses {
        address[] wmetaUSDOwner;
        address[] metaUSDOwner;
        address[] wmetaUsdcOwner;
        //address[] metaUsdcOwner;
        address[] wmetaScUsdOwner;
        address[] metaScUsdOwner;
    }

    struct UserBalances {
        uint[] wmetaUSDBalance;
        uint[] metaUSDBalance;
        uint[] wmetaUsdcBalance;
        //uint[] metaUsdcBalance;
        uint[] wmetaScUsdBalance;
        uint[] metaScUsdBalance;
    }

    struct State {
        uint wmetaUSDPrice;
        uint wmetaUSDPriceDirectCalculations;
        uint wmetaUsdcPrice;
        uint wmetaScUsdPrice;
        uint usdcPrice;
        uint metaUSDMultisigBalance;
        uint metaUSDTotalSupply;
        uint metaUsdcMultisigBalance;
        uint metaUsdcTotalSupply;
        uint metaScUsdMultisigBalance;
        uint metaScUsdTotalSupply;
        uint[] vaultUnderlyingBalance;
        UserBalances metaVault;
        UserBalances[4] underlying;
        UserBalances[] recoveryToken;
        uint[4] credixVaultTotalSupply;
        uint[4] credixVaultMetavaultBalance;
    }

    struct WithdrawUnderlyingLocal {
        IMetaVault metaVault;
        address[] owners;
        uint[] minAmountsOut;
        bool[] paused;
        uint count;
        uint decimals;
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        multisig = IPlatform(PLATFORM).multisig();
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        metaVaultFactory = IMetaVaultFactory(SonicConstantsLib.METAVAULT_FACTORY);
        wrappedMetaVault = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);

        CREDIX_VAULTS = [VAULT_1_USDC, VAULT_2_USDC, VAULT_3_SCUSD, VAULT_4_SCUSD];

        WRAPPED_META_USD_LARGEST_HOLDERS = [
            0x6e8C150224D6e9B646889b96EFF6f7FD742e2C22,
            0xCCdDbBbd1E36a6EDA3a84CdCee2040A86225Ba71,
            0x287939376DCc571b5ee699DD8E72199989424A2E,
            0x859C08DDB344FaCf01027FE7e75C5DFA6230c7dE,
            0x6F11663766bB213003cD74EB09ff4c67145023c5,
            0x76Da6c90d2b16b2e420377623e347d5AD8263837,
            0x06C319099BaC1a2b2797c55eF06667B4Ce62D226,
            0xc109C45330576048B35686275372e8a84DAeD552,
            0x27d475C8279FE603647A976CF55b657b0cef8070,
            0x60e2A70a4Ba833Fe94AF82f01742e7bfd8e18FA0,
            0xD5541c0De06aE99D9D66E5c0bb24b0206d653CB8,
            0x1D801dC616C79c499C5d38c998Ef2D0D6Cf868e8,
            0x97006dB48f27A1312BbeD5E96dE146A97A78E396,
            0x8f80791DcdAeb64794F53d4ab1c27BF4c21A4F41,
            0x5e149861BdA09B595e71F7031Ead42fCf6882a4a,
            0x000066320a467dE62B1548f46465abBB82662331,
            0x249a947f9Bf78F0e1E3F4304d744c5AD7aBcAb12,
            0xf0a85BA66b3F0858Dc466Cd2BD75c5aAD0cB3A19,
            0x789D42f23cf436eD62421c68beFfE570157F2B2d,
            0xda17792426279c05738811726C76BB025715DD5f,
            0x6967C1BBACce1eB79F92db11b28169C6BB635Ed6,
            0xb33B51e0575530493e8118e922A1d2b7e8DEB351,
            0xe8B8f2467d096740f9F71a3a98B3E424FBc98531,
            0x1AB8aa28Ae574654d494956e5d5cc8CE7C0BDcAD,
            0xBCAA4c21c674DFD89e8C4e550d1e02eA099c8afb,
            0xF1dCce3a6c321176C62b71c091E3165CC9C3816E
        ];

        META_USD_LARGEST_HOLDERS = [
            0x8901D9cf0272A2876525ee25Fcbb9E423c4B95f6,
            0x97006dB48f27A1312BbeD5E96dE146A97A78E396,
            0x59603A3AB3e33F07A2B9a4419399d502a1Fb6a95,
            0xc2d5904602e2d76D3D04EC28A5A1c52E136C4475,
            0xCE785cccAa0c163E6f83b381eBD608F98f694C44,
            0x698eDaCD0cc284aB731e1c57662f3d3989E8adB7,
            0x34F6eA796d06870db4dD5775D9e665539Bc6bBA0,
            0xa9714f7291251Bc1b0D0dBA6481959Ef814E171a,
            0x8C9C2f167792254C651FcA36CA40Ed9a229e5921,
            0xaC207c599e4A07F9A8cc5E9cf49B02E20AB7ba69,
            0x5027457c50A3b45772baFE70e2E6f05D98514ad4,
            0xec8e3A07d6c5c172e821588EF1749b739A06b20E,
            0xB19f6698d63D51Cfa0D6eb4490ca83Fcd640F462,
            0x30A26c2837e9Ad41Ea5955949F00402DbF86f124,
            0x029953c81d3e27F60844A8E16c6F4535997310B2,
            0x587ed0683581fE5bD127A3CE4450cFCe7E00629c,
            0xb4cE0c954bB129D8039230F701bb6503dca1Ee8c,
            0x02fFb9B4bBC29f9A59b20C541d369C5add62a5a3,
            0x685dcbC1AFF2C2fB41d0747Aa125b28e93150D54,
            0x17B72bf643a1c8356D2bB264A42bFCD4dfa3661C,
            0xa4410ad338CfC95416c99Aa4B7Bfdf3571Be7c12,
            0x5D00Ef140D2438B544Bb3809675a9F27264f8217,
            0x2C00637a8CF228B8e882aB0BDfCDA22c159E1E6C,
            0x2a1842baC18058078F682e1996f763480081174A,
            0xCCCCCCf25584cAFbD4d80E9464361Af1e7280b44,
            0xDe39832d15466129Fc5E85b8d1E612b24Cdea012,
            0xA51A6F181D7BdE6F4fc445Ff844fa9329616C01a,
            0xebdB6fc1DBde7139348B379408f447400EF07065,
            0x1563C4751Ad2be48Fd17464B73585B6ba8b6A5f0,
            0x874f1BcFf7BECb45C95f5582a7c5EC936f81684B,
            0x5E340b4907365814B789eDD30E150601879C1104,
            0x9726d0e8Bd180A2136110EeD2Eb56fFDE8C98C7D,
            0x593851CA21Bfd716a9FC71c744e8b1CdF101535b,
            0x4282341588F94c158bFAA40AE2C9F3ABfdAc647f,
            0x1C1732e19D016F20f59aDe301375B1572a0981c2,
            0xC02D68B1287534d8D12a9bE01A5B4ef5A1771bA3
        ];

        WRAPPED_META_USDC_LARGEST_HOLDERS = [
            0xCE785cccAa0c163E6f83b381eBD608F98f694C44,
            0x25cc6D2eAa941c8bA7B67Ee588565b5aC5D392Db,
            0xbA1333333333a1BA1108E8412f11850A5C319bA9,
            0xbf21Ba013A41b443b7b21eaAbBB647ceC360fa68,
            0x5e8AfE101Ce69963233629000519636812a0B778,
            0x34c8e61d2AE926d8088317726a89AA05861Bbc41,
            0x99F1cE9D0b95D5D9B3929D0079bdB27628e7eFd7,
            0xd36036e589803016CF6d510950ecbe75a0b28c29,
            0xB3baaf17E80010a3aF533b776b08077c9065DbE1,
            0xaBf0f7bD0Dc8Ce44b084B4B66b8Db97F1b9Ce419,
            0x441921132b11Fdc628F25Fe80D7369143FA6c18E,
            0x8b51E11B673b8A47b3558af8380AdD9AcFC19356,
            0x32Bcd41D2093212b647A789DC7Ff6B1021D9Ea98,
            0x5754Dc0453dD0f19C3AF670E49f133F6c27553E7,
            0x69EBBA5e2b429592483b5687a392436BA3Ac15b5,
            0x6d6b0d6EFED507ec2304F0eab83d2E814DDe99Ab,
            0x2C636dfBc7FEC91B88B6F5d05e0CFc87645acEd7,
            0xdf6D62cCfe81D47DD648be9bA33eaf330A2F0195,
            0xAF1bff74708098dB603e48aaEbEC1BBAe03Dcf11,
            0x82784592893afcDec068050c6a10A7d0233293f9,
            0xf1196bF726ed9227507f5a8b7C87Ae177124dB2B,
            0xdD82D88183290BEa46c286A4C43395820dd46a6C,
            0xAFA0E9B4693acBCd679Be4B4a53b5589B25139c5,
            0x24bfaE3526E246cF75D0BdB494cA7860948d37aC,
            0xe0D01EFEe7A9740F8e702F086dd4FcaE87926Abf,
            0xA78d705E517863749fB1C48783134B168d75c2dC,
            0xeC97f1c07b29e21CECe5581fc3354c3fEaC7DB7B,
            0x7044C9382E76b6a32a817A5156A36b9fbCEFb61e,
            0x6D1E0084a6910a8803ab7c22483A1a2Db3F1001a,
            0x04261F3A4f4E244B80ED7e3d8b7fF28Abd6c4Dc9,
            0x02443d1fCb2a76C99Bf9BDf89de7F048d26eaDbA,
            0xc5E0250037195850E4D987CA25d6ABa68ef5fEe8,
            0x27e7EF864A1143d95D4f0d3391232475B545F9AE
        ];

        WRAPPED_META_SCUSD_LARGEST_HOLDERS = [
            0xCE785cccAa0c163E6f83b381eBD608F98f694C44,
            0xbA1333333333a1BA1108E8412f11850A5C319bA9,
            0x029953c81d3e27F60844A8E16c6F4535997310B2,
            0xbf21Ba013A41b443b7b21eaAbBB647ceC360fa68,
            0xa765A629f11f538F6d67e3fDF799BaEd1506017d,
            0x34c8e61d2AE926d8088317726a89AA05861Bbc41,
            0x5e8AfE101Ce69963233629000519636812a0B778,
            0xd36036e589803016CF6d510950ecbe75a0b28c29,
            0xC5042F9d9a18e95547864438455c8F05b4987399,
            0xB3baaf17E80010a3aF533b776b08077c9065DbE1,
            0xaBf0f7bD0Dc8Ce44b084B4B66b8Db97F1b9Ce419,
            0x698eDaCD0cc284aB731e1c57662f3d3989E8adB7,
            0x441921132b11Fdc628F25Fe80D7369143FA6c18E,
            0x27d475C8279FE603647A976CF55b657b0cef8070,
            0x8b51E11B673b8A47b3558af8380AdD9AcFC19356,
            0x99F1cE9D0b95D5D9B3929D0079bdB27628e7eFd7,
            0x1f95B1FF006311bAa9865BA48382A144f8135FE7,
            0x5754Dc0453dD0f19C3AF670E49f133F6c27553E7,
            0x32Bcd41D2093212b647A789DC7Ff6B1021D9Ea98,
            0x224b920120AD0c30aedb5AFD01056405ec8E00F8,
            0x69EBBA5e2b429592483b5687a392436BA3Ac15b5,
            0xEE25A745ceA4e061c7A163396e79ae90BA804040,
            0x6d6b0d6EFED507ec2304F0eab83d2E814DDe99Ab,
            0x2C636dfBc7FEC91B88B6F5d05e0CFc87645acEd7,
            0xdf6D62cCfe81D47DD648be9bA33eaf330A2F0195,
            0x92Fa9b5d84587170E56a780793Ba5d3F3591623d,
            0x25cc6D2eAa941c8bA7B67Ee588565b5aC5D392Db,
            0xAF1bff74708098dB603e48aaEbEC1BBAe03Dcf11,
            0x81819e54706F4205DDB70d8c57B4DDAD46e3484a,
            0x82784592893afcDec068050c6a10A7d0233293f9,
            0xf1196bF726ed9227507f5a8b7C87Ae177124dB2B,
            0xAad23a77205429720b50972C2D74F9CC8b757e25,
            0x288a2395f027F65684D836754bA43Afa20CA09e6,
            0xdD82D88183290BEa46c286A4C43395820dd46a6C,
            0x0E8a00AE00a153A087BCcD1b89efCc78209B3ab8,
            0x2f50fFD44daCA5f4B420d89B9F609d5bB30E4B53,
            0x0D7720DF68cfC04534D02C2669e51652b0E77791,
            0xAFA0E9B4693acBCd679Be4B4a53b5589B25139c5,
            0x24bfaE3526E246cF75D0BdB494cA7860948d37aC,
            0x730a1EAA28f844e7f02aE910b32644D7584f675C,
            0xe0D01EFEe7A9740F8e702F086dd4FcaE87926Abf,
            0xA09BC385421f18D5d5072924f9d3709bB2B76281,
            0xA78d705E517863749fB1C48783134B168d75c2dC,
            0xeC97f1c07b29e21CECe5581fc3354c3fEaC7DB7B,
            0xc4137Cd4FE5B811C77CB3f0f0EbA28755E96099e,
            0x7044C9382E76b6a32a817A5156A36b9fbCEFb61e,
            0x6D1E0084a6910a8803ab7c22483A1a2Db3F1001a,
            0x04261F3A4f4E244B80ED7e3d8b7fF28Abd6c4Dc9,
            0x02443d1fCb2a76C99Bf9BDf89de7F048d26eaDbA,
            0x27e7EF864A1143d95D4f0d3391232475B545F9AE,
            0x4f639310A05b36f525711fd52AFCe2770851f988,
            0xE765c1f860D1d949aF634E0CAc67bbe161b8Eb58,
            0xF681a2f3A9a773B4fab46d6725F43B1762674698,
            0x0FC587968C33acda9a16C5fa6E66258fF8aA2F61,
            0xe5707753E0Db37D338817EB81Ee431264E755458
            // todo remove 999/1000 below
            //            0xb616d066fb1aB1384D47A5a70Ce00af515445A6d,
            //            0xb153560DDDE28d3b86F018d030D573E7e34a3388,
            //            0x88888887C3ebD4a33E34a15Db4254C74C75E5D4A
        ];

        META_SCUSD_LARGEST_HOLDERS =
            [0x88888887C3ebD4a33E34a15Db4254C74C75E5D4A, 0x1f95B1FF006311bAa9865BA48382A144f8135FE7];

        SMALL_USERS = [
            0x4f82e73EDb06d29Ff62C91EC8f5Ff06571bdeb29,
            0x4f639310A05b36f525711fd52AFCe2770851f988,
            0x2BC6ae2f72b75fF055c5847a75203F056547319b,
            0x1AB8aa28Ae574654d494956e5d5cc8CE7C0BDcAD,
            0xf63361925255c17C53E2303Ce167145D4cBD0c9C,
            0x43da58c65F0fadd0A94EdD85A9b018542BAd4223
        ];

        _upgradeFactory(); // upgrade to Factory v2.0.0
    }

    /// @notice Restart MetaUSD: withdraw all broken underlying, replace it by real assets and recovery tokens
    function testRestartMetaUSD() public {
        UserAddresses memory users = _getUsers();
        // ---------------------------------- upgrade strategies and vaults
        console.log("Upgrade");
        {
            _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
            _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
            _upgradeMetaVault(SonicConstantsLib.METAVAULT_METASCUSD);
            _upgradeWrappedMetaVaults();

            for (uint i; i < 4; ++i) {
                _upgradeAmfStrategy(address(IVault(CREDIX_VAULTS[i]).strategy()));
                _upgradeCVault(CREDIX_VAULTS[i]);

                {
                    IStrategy _strategy = IVault(CREDIX_VAULTS[i]).strategy();

                    vm.prank(multisig);
                    AaveMerklFarmStrategy(address(_strategy)).setUnderlying();
                }
            }
        }

        // ---------------------------------- set up recovery tokens
        console.log("Set up recovery tokens");
        {
            // _upgradePlatform();
            _setupMetaVaultFactory();

            //            _createMockedRecoveryToken(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);
            //            _createMockedRecoveryToken(SonicConstantsLib.WRAPPED_METAVAULT_METAUSDC);
            //            _createMockedRecoveryToken(SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD);
            //
            //            _createMockedRecoveryToken(SonicConstantsLib.METAVAULT_METAUSD);
            //            _createMockedRecoveryToken(SonicConstantsLib.METAVAULT_METAUSDC);
            //            _createMockedRecoveryToken(SonicConstantsLib.METAVAULT_METASCUSD);

            _createRealRecoveryToken(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, 0x00);
            _createRealRecoveryToken(SonicConstantsLib.WRAPPED_METAVAULT_METAUSDC, bytes32(uint(0x01)));
            _createRealRecoveryToken(SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD, bytes32(uint(0x02)));

            _createRealRecoveryToken(SonicConstantsLib.METAVAULT_METAUSD, bytes32(uint(0x03)));
            _createRealRecoveryToken(SonicConstantsLib.METAVAULT_METAUSDC, bytes32(uint(0x04)));
            _createRealRecoveryToken(SonicConstantsLib.METAVAULT_METASCUSD, bytes32(uint(0x05)));
        }

        // ---------------------------------- whitelist vaults
        console.log("Whitelist");
        {
            _whitelistVault(SonicConstantsLib.METAVAULT_METAUSD, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);

            _whitelistVault(SonicConstantsLib.METAVAULT_METAUSDC, SonicConstantsLib.METAVAULT_METAUSD);
            _whitelistVault(SonicConstantsLib.METAVAULT_METAUSDC, SonicConstantsLib.WRAPPED_METAVAULT_METAUSDC);

            _whitelistVault(SonicConstantsLib.METAVAULT_METASCUSD, SonicConstantsLib.METAVAULT_METAUSD);
            _whitelistVault(SonicConstantsLib.METAVAULT_METASCUSD, SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD);
        }

        // ---------------------------------- set target proportions of scUsd-broken c-vaults to 0
        {
            uint vaultIndex1 = _getVaultIndex(SonicConstantsLib.METAVAULT_METASCUSD, VAULT_3_SCUSD);
            uint vaultIndex2 = _getVaultIndex(SonicConstantsLib.METAVAULT_METASCUSD, VAULT_4_SCUSD);
            uint targetIndex = IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD).vaults().length - 1;
            while (targetIndex == vaultIndex1 || targetIndex == vaultIndex2) {
                targetIndex--;
            }
            _setProportion(SonicConstantsLib.METAVAULT_METASCUSD, vaultIndex1, targetIndex, 1e16);

            _setProportion(SonicConstantsLib.METAVAULT_METASCUSD, vaultIndex2, targetIndex, 1e16);
        }

        // ---------------------------------- save initial state
        console.log("Get state");
        State memory state0 = _getState(users);

        // ---------------------------------- withdraw underlying in emergency, provide recovery tokens for large users
        console.log("Withdraw underlying to users");
        {
            // metaScUsd vault
            for (uint i = 2; i < 4; i++) {
                console.log("!!!!!!!!!! Withdraw from MetaScUsd.CVault", i, CREDIX_VAULTS[i]);
                _redeemUnderlyingEmergency(
                    SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD, CREDIX_VAULTS[i], users.wmetaScUsdOwner
                );
                _withdrawUnderlyingEmergency(
                    SonicConstantsLib.METAVAULT_METASCUSD, CREDIX_VAULTS[i], users.metaScUsdOwner
                );
            }

            // metaUSD vault
            for (uint i; i < 4; i++) {
                console.log("!!!!!!!!!! Withdraw from MetaUSD.CVault", i, CREDIX_VAULTS[i]);
                _redeemUnderlyingEmergency(
                    SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, CREDIX_VAULTS[i], users.wmetaUSDOwner
                );
                _withdrawUnderlyingEmergency(SonicConstantsLib.METAVAULT_METAUSD, CREDIX_VAULTS[i], users.metaUSDOwner);
            }

            // metaUsdc vault
            for (uint i; i < 2; i++) {
                console.log("!!!!!!!!!! Withdraw from MetaUsdc.CVault", i, CREDIX_VAULTS[i]);
                _redeemUnderlyingEmergency(
                    SonicConstantsLib.WRAPPED_METAVAULT_METAUSDC, CREDIX_VAULTS[i], users.wmetaUsdcOwner
                );
                // _withdrawUnderlyingEmergency(SonicConstantsLib.METAVAULT_METAUSDC, CREDIX_VAULTS[i], users);
            }
        }

        // ---------------------------------- check current state
        console.log("Get state");
        _getState(users);

        // ---------------------------------- deposit into metaUSD by multisig to be able to withdraw all left broken underlying
        {
            console.log("!!!!!!!!!!!!!!!!!!!!!!!! Deposit to metaUSD");
            (uint amount, address asset) = _depositToMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
            console.log("MetaUSD: amount, asset", amount, IERC20Metadata(asset).symbol());

            console.log("!!!!!!!!!!!!!!!!!!!!!!!! Deposit to metaUsdc");
            (amount, asset) = _depositToMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
            console.log("MetaUSDC: amount, asset", amount, IERC20Metadata(asset).symbol());

            console.log("!!!!!!!!!!!!!!!!!!!!!!!! Deposit to metaScUsd");
            (amount, asset) = _depositToMetaVault(SonicConstantsLib.METAVAULT_METASCUSD);
            console.log("MetaScUSD: amount, asset", amount, IERC20Metadata(asset).symbol());
        }

        // ---------------------------------- check current state
        console.log("Get state");
        _getState(users);

        // ---------------------------------- withdraw underlying in emergency for multisig
        console.log("Withdraw underlying to multisig");
        {
            address[] memory govUsers = new address[](1);
            govUsers[0] = multisig;
            for (uint i; i < 4; i++) {
                console.log("------- Withdraw leftovers from MetaUSD.CVault", i, CREDIX_VAULTS[i]);
                _withdrawUnderlyingEmergency(SonicConstantsLib.METAVAULT_METAUSD, CREDIX_VAULTS[i], govUsers);
            }

            for (uint i; i < 2; i++) {
                console.log("------- Withdraw leftovers from MetaUsdc.CVault", i, CREDIX_VAULTS[i]);
                _withdrawUnderlyingEmergency(SonicConstantsLib.METAVAULT_METAUSDC, CREDIX_VAULTS[i], govUsers);
            }

            for (uint i = 2; i < 4; i++) {
                console.log("------- Withdraw leftovers from MetaScUsd.CVault", i, CREDIX_VAULTS[i]);
                _withdrawUnderlyingEmergency(SonicConstantsLib.METAVAULT_METASCUSD, CREDIX_VAULTS[i], govUsers);
            }
        }

        // ---------------------------------- check current state: ensure that there is 0 broken underlying in metaUSD
        State memory stateFinal = _getState(users);

        {
            for (uint i; i < 4; i++) {
                assertApproxEqAbs(
                    stateFinal.credixVaultMetavaultBalance[i], 0, 10, "Underlying balance in Credix vault should be 0"
                );
            }
            assertApproxEqAbs(
                stateFinal.credixVaultTotalSupply[0],
                1516866797820516256053,
                10,
                "Vault 1 - only direct deposits should be left"
            );
            assertApproxEqAbs(
                stateFinal.credixVaultTotalSupply[1],
                7629744040403949565711,
                10,
                "Vault 2 - only direct deposits should be left"
            );
            assertApproxEqAbs(
                stateFinal.credixVaultTotalSupply[2],
                15006462608827822933,
                10,
                "Vault 3 - only direct deposits should be left"
            );
            assertApproxEqAbs(
                stateFinal.credixVaultTotalSupply[3],
                100853433576210056223,
                10,
                "Vault 4 - only direct deposits should be left"
            );

            assertApproxEqAbs(
                stateFinal.wmetaUSDPrice, state0.wmetaUSDPrice, 1, "USD-Wrapped price should be the same 1"
            );
            assertApproxEqAbs(
                stateFinal.wmetaUSDPriceDirectCalculations,
                state0.wmetaUSDPriceDirectCalculations,
                state0.wmetaUSDPriceDirectCalculations / 100_000,
                "USD-Wrapped price should be the same 2"
            );
            assertApproxEqAbs(
                stateFinal.wmetaUSDPrice,
                state0.wmetaUSDPriceDirectCalculations,
                state0.wmetaUSDPriceDirectCalculations / 100_000,
                "USD-Wrapped price should be the same 3"
            );
            assertApproxEqAbs(
                stateFinal.wmetaUsdcPrice,
                state0.wmetaUsdcPrice,
                state0.wmetaUsdcPrice / 100_000,
                "Usdc-Wrapped price should be the same"
            );
            assertApproxEqAbs(
                stateFinal.wmetaScUsdPrice,
                state0.wmetaScUsdPrice,
                state0.wmetaScUsdPrice / 100_000,
                "ScUsd-Wrapped price should be the same"
            );
        }

        // ---------------------------------- check meta vault balances
        {
            for (uint i; i < users.wmetaUSDOwner.length; ++i) {
                assertApproxEqAbs(stateFinal.metaVault.wmetaUSDBalance[i], 0, 1, "Large user has no wmetaUSD");
            }

            for (uint i; i < users.wmetaUsdcOwner.length; ++i) {
                assertApproxEqAbs(stateFinal.metaVault.wmetaUsdcBalance[i], 0, 1, "Large user has no wmetaUSDC");
            }

            for (uint i; i < users.wmetaScUsdOwner.length; ++i) {
                // console.log("user", users.wmetaScUsdOwner[i]);
                assertApproxEqAbs(stateFinal.metaVault.wmetaScUsdBalance[i], 0, 1, "Large user has no wmetaScUSD");
            }

            for (uint i; i < users.metaUSDOwner.length; ++i) {
                assertApproxEqAbs(stateFinal.metaVault.metaUSDBalance[i], 0, 1, "Large user has no metaUSD");
            }

            for (uint i; i < users.metaScUsdOwner.length; ++i) {
                assertApproxEqAbs(stateFinal.metaVault.metaScUsdBalance[i], 0, 1, "Large user has no metaScUSD");
            }
        }

        // ---------------------------------- check amounts of recovery tokens
        {
            for (uint i; i < users.wmetaUSDOwner.length; ++i) {
                assertApproxEqAbs(
                    state0.metaVault.wmetaUSDBalance[i] * state0.wmetaUSDPrice / 1e18, // amount of meta vault tokens
                    stateFinal.recoveryToken[0].wmetaUSDBalance[i],
                    stateFinal.recoveryToken[0].wmetaUSDBalance[i] / 100_000,
                    "Recovery token for wmetaUSD should be equal to initial balance of wmetaUSD"
                );
            }

            for (uint i; i < users.wmetaUsdcOwner.length; ++i) {
                //                console.log("eq", i, state0.metaVault.wmetaUsdcBalance[i] * state0.wmetaUsdcPrice / 1e18, stateFinal.recoveryToken[1].wmetaUsdcBalance[i]);
                assertApproxEqAbs(
                    state0.metaVault.wmetaUsdcBalance[i] * state0.wmetaUsdcPrice / 1e18, // amount of meta vault tokens
                    stateFinal.recoveryToken[1].wmetaUsdcBalance[i],
                    stateFinal.recoveryToken[1].wmetaUsdcBalance[i] / 100_000,
                    "Recovery token for wmetaUSDC should be equal to initial balance of wmetaUSDC"
                );
            }

            for (uint i; i < users.wmetaScUsdOwner.length; ++i) {
                //                console.log("eq", i, state0.metaVault.wmetaScUsdBalance[i] * state0.wmetaScUsdPrice / 1e18, stateFinal.recoveryToken[2].wmetaScUsdBalance[i]);
                assertApproxEqAbs(
                    state0.metaVault.wmetaScUsdBalance[i] * state0.wmetaScUsdPrice / 1e18, // amount of meta vault tokens
                    stateFinal.recoveryToken[2].wmetaScUsdBalance[i],
                    stateFinal.recoveryToken[2].wmetaScUsdBalance[i] / 100_000,
                    "Recovery token for wmetaScUSD should be equal to initial balance of wmetaScUSD"
                );
            }

            for (uint i; i < users.metaUSDOwner.length; ++i) {
                //                console.log("eq", i, state0.metaVault.metaUSDBalance[i], stateFinal.recoveryToken[3].metaUSDBalance[i]);
                assertApproxEqAbs(
                    state0.metaVault.metaUSDBalance[i],
                    stateFinal.recoveryToken[3].metaUSDBalance[i],
                    stateFinal.recoveryToken[3].metaUSDBalance[i] / 100_000,
                    "Recovery token for metaUSD should be equal to initial balance of metaUSD"
                );
            }

            for (uint i; i < users.metaScUsdOwner.length; ++i) {
                //                console.log("eq", i, state0.metaVault.metaScUsdBalance[i], stateFinal.recoveryToken[5].metaScUsdBalance[i]);
                assertApproxEqAbs(
                    state0.metaVault.metaScUsdBalance[i],
                    stateFinal.recoveryToken[5].metaScUsdBalance[i],
                    stateFinal.recoveryToken[5].metaScUsdBalance[i] / 100_000,
                    "Recovery token for metaScUSD should be equal to initial balance of metaScUSD"
                );
            }
        }

        // ---------------------------------- check total supply of recovery tokens
        {
            assertEq(
                _getTotalAmountRecoveryTokens(recoveryTokens[0], stateFinal.recoveryToken[0].wmetaUSDBalance),
                IERC20(recoveryTokens[0]).totalSupply(),
                "Total supply of wmetaUSD recovery token should be equal to sum of balances"
            );

            assertEq(
                _getTotalAmountRecoveryTokens(recoveryTokens[1], stateFinal.recoveryToken[1].wmetaUsdcBalance),
                IERC20(recoveryTokens[1]).totalSupply(),
                "Total supply of wmetaUSDC recovery token should be equal to sum of balances"
            );

            assertEq(
                _getTotalAmountRecoveryTokens(recoveryTokens[2], stateFinal.recoveryToken[2].wmetaScUsdBalance),
                IERC20(recoveryTokens[2]).totalSupply(),
                "Total supply of wmetaScUSD recovery token should be equal to sum of balances"
            );

            assertEq(
                _getTotalAmountRecoveryTokens(recoveryTokens[3], stateFinal.recoveryToken[3].metaUSDBalance),
                IERC20(recoveryTokens[3]).totalSupply(),
                "Total supply of metaUSD recovery token should be equal to sum of balances"
            );

            assertEq(
                _getTotalAmountRecoveryTokens(recoveryTokens[5], stateFinal.recoveryToken[5].metaScUsdBalance),
                IERC20(recoveryTokens[5]).totalSupply(),
                "Total supply of metaScUSD recovery token should be equal to sum of balances"
            );

            assertEq(
                IERC20(recoveryTokens[4]).totalSupply(),
                IERC20(recoveryTokens[4]).balanceOf(multisig),
                "Total supply of metaUSDC recovery token should be equal to multisig balance" // no large users for metaUSDC
            );
        }

        // ---------------------------------- remove broken vaults
        {
            uint vaultIndex1 = _getVaultIndex(SonicConstantsLib.METAVAULT_METAUSDC, VAULT_1_USDC);
            uint vaultIndex2 = _getVaultIndex(SonicConstantsLib.METAVAULT_METAUSDC, VAULT_2_USDC);
            uint targetIndex = IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).vaults().length - 1;
            while (targetIndex == vaultIndex1 || targetIndex == vaultIndex2) {
                targetIndex--;
            }
            _setProportion(SonicConstantsLib.METAVAULT_METAUSDC, vaultIndex1, targetIndex, 0);

            _setProportion(SonicConstantsLib.METAVAULT_METAUSDC, vaultIndex2, targetIndex, 0);

            vaultIndex1 = _getVaultIndex(SonicConstantsLib.METAVAULT_METASCUSD, VAULT_3_SCUSD);
            vaultIndex2 = _getVaultIndex(SonicConstantsLib.METAVAULT_METASCUSD, VAULT_4_SCUSD);
            targetIndex = IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD).vaults().length - 1;
            while (targetIndex == vaultIndex1 || targetIndex == vaultIndex2) {
                targetIndex--;
            }
            _setProportion(SonicConstantsLib.METAVAULT_METASCUSD, vaultIndex1, targetIndex, 0);

            _setProportion(SonicConstantsLib.METAVAULT_METASCUSD, vaultIndex2, targetIndex, 0);

            vm.prank(multisig);
            IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).removeVault(VAULT_1_USDC);

            vm.prank(multisig);
            IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).removeVault(VAULT_2_USDC);

            vm.prank(multisig);
            IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD).removeVault(VAULT_3_SCUSD);

            vm.prank(multisig);
            IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD).removeVault(VAULT_4_SCUSD);
        }

        // ---------------------------------- ensure that exist small users are able to withdraw their funds
        {
            _withdrawAsSmallUserFromWrapped(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, SMALL_USERS[0]);
            _withdrawAsSmallUserFromWrapped(SonicConstantsLib.WRAPPED_METAVAULT_METAUSDC, SMALL_USERS[1]);
            _withdrawAsSmallUserFromWrapped(SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD, SMALL_USERS[2]);
            _withdrawAsSmallUserFromMetaVault(SonicConstantsLib.METAVAULT_METAUSD, SMALL_USERS[3]);
            _withdrawAsSmallUserFromMetaVault(SonicConstantsLib.METAVAULT_METAUSDC, SMALL_USERS[4]);
            _withdrawAsSmallUserFromMetaVault(SonicConstantsLib.METAVAULT_METASCUSD, SMALL_USERS[5]);
        }

        // ---------------------------------- ensure that new users can deposit and withdraw
        // todo
    }

    //region ---------------------------------------------- Main logic
    function _redeemUnderlyingEmergency(address wrapped_, address cVault_, address[] memory users) internal {
        WithdrawUnderlyingLocal memory v;

        //console.log("_redeemUnderlyingEmergency.start", wrapped_, cVault_);
        v.metaVault = IMetaVault(IWrappedMetaVault(wrapped_).metaVault());

        v.owners = new address[](users.length);
        uint[] memory shares = new uint[](users.length);
        v.minAmountsOut = new uint[](users.length);
        v.paused = new bool[](users.length);
        v.decimals = IWrappedMetaVault(wrapped_).decimals();

        uint totalMetaVaultTokensToWithdraw;
        uint totalMetaVaultTokens = v.metaVault.maxWithdrawUnderlying(cVault_, wrapped_) * 9999 / 10000;

        if (totalMetaVaultTokens != 0) {
            //            (uint priceMetaVaultToken,) = _metaVault.price();
            uint wrappedPrice = 10 ** (18 - v.decimals) * IWrappedMetaVault(wrapped_).totalAssets() * 1e18
                / IWrappedMetaVault(wrapped_).totalSupply();

            for (uint i = 0; i < users.length; ++i) {
                uint maxShares = IWrappedMetaVault(wrapped_).balanceOf(users[i]);
                if (maxShares < 2) continue;

                uint maxAmount = maxShares * wrappedPrice / 1e18;
                //console.log("user, maxShares, maxAmount", users[i], maxShares, maxAmount);

                uint amount = totalMetaVaultTokensToWithdraw + maxAmount > totalMetaVaultTokens
                    ? totalMetaVaultTokens - totalMetaVaultTokensToWithdraw
                    : maxAmount;
                // console.log("totalMetaVaultTokensToWithdraw, totalMetaVaultTokens", totalMetaVaultTokensToWithdraw, totalMetaVaultTokens);

                if (amount < 2) {
                    // console.log("User is skipped", i, users[i]);
                    continue; // Skip users with no balance
                }

                v.owners[v.count] = users[i];
                shares[v.count] = amount * 1e18 / wrappedPrice;

                v.minAmountsOut[v.count] = _getExpectedUnderlying(
                    IVault(cVault_).strategy(), v.metaVault, (shares[v.count] - 1) * wrappedPrice / 1e18
                );
                totalMetaVaultTokensToWithdraw += amount;

                if (amount == maxAmount) {
                    shares[v.count] = 0;
                }

                v.count++;
                if (totalMetaVaultTokensToWithdraw == totalMetaVaultTokens) break;
            }

            if (v.count != 0) {
                (v.owners, shares, v.minAmountsOut, v.paused) =
                    _reduceArrays(v.count, v.owners, shares, v.minAmountsOut, v.paused);

                _showAmounts(wrapped_, cVault_, v.owners, shares, v.minAmountsOut, true);

                vm.prank(multisig);
                WrappedMetaVault(wrapped_).redeemUnderlyingEmergency(
                    cVault_, v.owners, shares, v.minAmountsOut, v.paused
                );
            }
        }
        //console.log("_redeemUnderlyingEmergency.END");
    }

    function _withdrawUnderlyingEmergency(address metaVault_, address cVault_, address[] memory users) internal {
        WithdrawUnderlyingLocal memory v;

        //console.log("_withdrawUnderlyingEmergency.start", metaVault_, cVault_);
        v.owners = new address[](users.length);
        uint[] memory amounts = new uint[](users.length);
        v.minAmountsOut = new uint[](users.length);
        v.metaVault = IMetaVault(metaVault_);
        v.paused = new bool[](users.length);

        uint snapshot = vm.snapshotState();
        for (uint i = 0; i < users.length; ++i) {
            uint maxAmount = v.metaVault.maxWithdrawUnderlying(cVault_, users[i]);
            if (maxAmount < (10 ** v.metaVault.decimals())) continue;
            uint balance = v.metaVault.balanceOf(users[i]);

            vm.roll(block.number + 6);
            vm.prank(users[i]);
            v.metaVault.withdrawUnderlying(cVault_, maxAmount, 0, users[i], users[i]);
            vm.roll(block.number + 6);

            amounts[v.count] = maxAmount == balance ? 0 : maxAmount;
            v.owners[v.count] = users[i];
            v.minAmountsOut[v.count] = _getExpectedUnderlying(IVault(cVault_).strategy(), v.metaVault, maxAmount) - 1;
            v.count++;

            if (maxAmount != balance) break;
        }
        vm.revertToState(snapshot);

        if (v.count != 0) {
            (v.owners, amounts, v.minAmountsOut, v.paused) =
                _reduceArrays(v.count, v.owners, amounts, v.minAmountsOut, v.paused);

            _showAmounts(metaVault_, cVault_, v.owners, amounts, v.minAmountsOut, false);

            vm.prank(multisig);
            v.metaVault.withdrawUnderlyingEmergency(cVault_, v.owners, amounts, v.minAmountsOut, v.paused);
        }
        //console.log("_withdrawUnderlyingEmergency.END");
    }

    function _depositToMetaVault(address metaVault_) internal returns (uint amount, address asset) {
        IMetaVault _metaVault = IMetaVault(metaVault_);
        uint _totalSupply = _metaVault.totalSupply();

        address[] memory assets = _metaVault.assetsForDeposit();
        (uint priceAsset,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(assets[0]);

        uint[] memory amountsMax = new uint[](assets.length);
        amountsMax[0] = _totalSupply * 1e18 / priceAsset / 10 ** 12 * 101 / 100;
        deal(assets[0], multisig, amountsMax[0]);

        vm.prank(multisig);
        IERC20(assets[0]).approve(metaVault_, amountsMax[0]);

        //console.log("user balance before", _metaVault.balanceOf(multisig));

        vm.prank(multisig);
        _metaVault.depositAssets(assets, amountsMax, 0, multisig);

        //        console.log("deposit to metavault", metaVault_, amountsMax[0], assets[0]);
        //        console.log("user balance after", _metaVault.balanceOf(multisig));

        assertGt(
            _metaVault.totalSupply(),
            _totalSupply * 2,
            "Total supply of meta vault tokens should increase at least twice"
        );

        return (amountsMax[0], assets[0]);
    }

    function _withdrawAsSmallUserFromWrapped(address wrapped_, address user) internal {
        uint _balance = IWrappedMetaVault(wrapped_).balanceOf(user);
        assertGt(_balance, 0, "Small user should have not empty balance in wrapped vault");

        address receiver = makeAddr("receiver");
        address _asset = IWrappedMetaVault(wrapped_).asset();

        uint expected = _balance;

        vm.roll(block.number + 6);
        vm.prank(user);
        IWrappedMetaVault(wrapped_).withdraw(_balance, receiver, user, type(uint).max);

        uint actual = IERC20(_asset).balanceOf(receiver);
        assertApproxEqAbs(
            actual, expected, expected / 100_000, "Small user should receive expected amount of underlying asset 1"
        );
    }

    function _withdrawAsSmallUserFromMetaVault(address metaVault_, address user) internal {
        uint _balance = IMetaVault(metaVault_).balanceOf(user);
        assertGt(_balance, 0, "Small user should have not empty balance in meta vault");

        address[] memory _assets = IMetaVault(metaVault_).assetsForWithdraw();

        (uint price,) = IMetaVault(metaVault_).price();
        (uint priceAsset,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(_assets[0]);

        uint expectedUsd = _balance * price / 1e18 / 10 ** (18 - IERC20Metadata(_assets[0]).decimals());

        uint balanceBefore = IERC20(_assets[0]).balanceOf(user);

        vm.roll(block.number + 6);
        vm.prank(user);
        IMetaVault(metaVault_).withdrawAssets(_assets, _balance, new uint[](1));
        uint balanceAfter = IERC20(_assets[0]).balanceOf(user);

        assertApproxEqAbs(
            (balanceAfter - balanceBefore) * priceAsset / 1e18,
            expectedUsd,
            expectedUsd / 100_000,
            "Small user should receive expected amount of underlying asset 2"
        );
    }
    //endregion ---------------------------------------------- Main logic

    //region ---------------------------------------------- Internal
    function _getExpectedUnderlying(
        IStrategy strategy,
        IMetaVault metaVault_,
        uint amountToWithdraw
    ) internal view returns (uint) {
        (uint priceAsset,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(
            IAToken(strategy.underlying()).UNDERLYING_ASSET_ADDRESS()
        );
        (uint priceMetaVault,) = metaVault_.price();

        // Assume here that AToken to asset is 1:1
        return amountToWithdraw * priceMetaVault / priceAsset * 10 ** IERC20Metadata(strategy.underlying()).decimals() // decimals of the underlying asset
            / 1e18;
    }

    function _getMetaVaultTokensByUnderlying(
        IStrategy strategy,
        IMetaVault metaVault_,
        uint underlyingAmount
    ) internal view returns (uint) {
        (uint priceAsset,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(
            IAToken(strategy.underlying()).UNDERLYING_ASSET_ADDRESS()
        );
        (uint priceMetaVault,) = metaVault_.price();

        // Assume here that AToken to asset is 1:1
        return underlyingAmount * 1e18 / priceMetaVault * priceAsset
            / 10 ** IERC20Metadata(strategy.underlying()).decimals(); // decimals of the underlying asset
    }

    function _getUsers() internal view returns (UserAddresses memory dest) {
        dest.wmetaUSDOwner = _toDynamicArray(WRAPPED_META_USD_LARGEST_HOLDERS);
        dest.metaUSDOwner = _toDynamicArray(META_USD_LARGEST_HOLDERS);
        dest.wmetaUsdcOwner = _toDynamicArray(WRAPPED_META_USDC_LARGEST_HOLDERS);
        //dest.metaUsdcOwner = _toDynamicArray(META_USDC_LARGEST_HOLDERS);
        dest.wmetaScUsdOwner = _toDynamicArray(WRAPPED_META_SCUSD_LARGEST_HOLDERS);
        dest.metaScUsdOwner = _toDynamicArray(META_SCUSD_LARGEST_HOLDERS);

        return dest;
    }

    function _getState(UserAddresses memory users) internal view returns (State memory state) {
        state.vaultUnderlyingBalance = new uint[](4);
        state.vaultUnderlyingBalance[0] = IERC20(IVault(VAULT_1_USDC).strategy().underlying()).balanceOf(VAULT_1_USDC);
        state.vaultUnderlyingBalance[1] = IERC20(IVault(VAULT_2_USDC).strategy().underlying()).balanceOf(VAULT_2_USDC);
        state.vaultUnderlyingBalance[2] = IERC20(IVault(VAULT_3_SCUSD).strategy().underlying()).balanceOf(VAULT_3_SCUSD);
        state.vaultUnderlyingBalance[3] = IERC20(IVault(VAULT_4_SCUSD).strategy().underlying()).balanceOf(VAULT_4_SCUSD);

        state.metaVault.wmetaUSDBalance =
            _getUserBalances(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, users.wmetaUSDOwner);
        state.metaVault.metaUSDBalance = _getUserBalances(SonicConstantsLib.METAVAULT_METAUSD, users.metaUSDOwner);
        state.metaVault.wmetaUsdcBalance =
            _getUserBalances(SonicConstantsLib.WRAPPED_METAVAULT_METAUSDC, users.wmetaUsdcOwner);
        //state.metaVault.metaUsdcBalance = _getUserBalances(SonicConstantsLib.METAVAULT_METAUSDC, users.metaUsdcOwner);
        state.metaVault.wmetaScUsdBalance =
            _getUserBalances(SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD, users.wmetaScUsdOwner);
        state.metaVault.metaScUsdBalance = _getUserBalances(SonicConstantsLib.METAVAULT_METASCUSD, users.metaScUsdOwner);

        for (uint i; i < 4; ++i) {
            state.underlying[i].wmetaUSDBalance =
                _getUserBalances(IVault(CREDIX_VAULTS[i]).strategy().underlying(), users.wmetaUSDOwner);
            state.underlying[i].metaUSDBalance =
                _getUserBalances(IVault(CREDIX_VAULTS[i]).strategy().underlying(), users.metaUSDOwner);
            state.underlying[i].wmetaUsdcBalance =
                _getUserBalances(IVault(CREDIX_VAULTS[i]).strategy().underlying(), users.wmetaUsdcOwner);
            //state.underlying[i].metaUsdcBalance = _getUserBalances(IVault(CREDIX_VAULTS[i]).strategy().underlying(), users.metaUsdcOwner);
            state.underlying[i].wmetaScUsdBalance =
                _getUserBalances(IVault(CREDIX_VAULTS[i]).strategy().underlying(), users.wmetaScUsdOwner);
            state.underlying[i].metaScUsdBalance =
                _getUserBalances(IVault(CREDIX_VAULTS[i]).strategy().underlying(), users.metaScUsdOwner);
        }

        state.recoveryToken = new UserBalances[](recoveryTokens.length);
        for (uint i; i < recoveryTokens.length; ++i) {
            state.recoveryToken[i].wmetaUSDBalance = _getUserBalances(recoveryTokens[i], users.wmetaUSDOwner);
            state.recoveryToken[i].metaUSDBalance = _getUserBalances(recoveryTokens[i], users.metaUSDOwner);
            state.recoveryToken[i].wmetaUsdcBalance = _getUserBalances(recoveryTokens[i], users.wmetaUsdcOwner);
            //state.recoveryToken[i].metaUsdcBalance = _getUserBalances(recoveryTokens[i], users.metaUsdcOwner);
            state.recoveryToken[i].wmetaScUsdBalance = _getUserBalances(recoveryTokens[i], users.wmetaScUsdOwner);
            state.recoveryToken[i].metaScUsdBalance = _getUserBalances(recoveryTokens[i], users.metaScUsdOwner);
        }

        state.metaUSDMultisigBalance = IERC20(SonicConstantsLib.METAVAULT_METAUSD).balanceOf(multisig);
        state.metaUSDTotalSupply = IERC20(SonicConstantsLib.METAVAULT_METAUSD).totalSupply();

        state.metaUsdcMultisigBalance = IERC20(SonicConstantsLib.METAVAULT_METAUSDC).balanceOf(multisig);
        state.metaUsdcTotalSupply = IERC20(SonicConstantsLib.METAVAULT_METAUSDC).totalSupply();

        state.metaScUsdMultisigBalance = IERC20(SonicConstantsLib.METAVAULT_METASCUSD).balanceOf(multisig);
        state.metaScUsdTotalSupply = IERC20(SonicConstantsLib.METAVAULT_METASCUSD).totalSupply();

        //        console.log("Multisig balances metaUSD, metaUSDC, metaScUSD", state.metaUSDMultisigBalance, state.metaUsdcMultisigBalance, state.metaScUsdMultisigBalance);
        //        console.log("Total supply metaUSD, metaUSDC, metaScUSD", state.metaUSDTotalSupply, state.metaUsdcTotalSupply, state.metaScUsdTotalSupply);

        (state.wmetaUSDPrice,) =
            IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);
        state.wmetaUSDPriceDirectCalculations = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD)
            .totalAssets() * 1e18 / IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).totalSupply();
        //        console.log("state.wmetaUSDPrice", state.wmetaUSDPrice);
        //        console.log("state.wmetaUSDPriceDirectCalculations", state.wmetaUSDPriceDirectCalculations);

        state.wmetaUsdcPrice = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSDC).totalAssets() * 1e18
            / IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSDC).totalSupply();
        state.wmetaScUsdPrice = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD).totalAssets() * 1e18
            / IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD).totalSupply();
        //        console.log("Prices metaUSD, metaUSDC, metaScUSD", state.wmetaUSDPrice, state.wmetaUsdcPrice, state.wmetaScUsdPrice);

        (state.usdcPrice,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(SonicConstantsLib.TOKEN_USDC);

        state.credixVaultMetavaultBalance[0] = IVault(CREDIX_VAULTS[0]).balanceOf(SonicConstantsLib.METAVAULT_METAUSDC);
        state.credixVaultMetavaultBalance[1] = IVault(CREDIX_VAULTS[1]).balanceOf(SonicConstantsLib.METAVAULT_METAUSDC);
        state.credixVaultMetavaultBalance[2] = IVault(CREDIX_VAULTS[2]).balanceOf(SonicConstantsLib.METAVAULT_METASCUSD);
        state.credixVaultMetavaultBalance[3] = IVault(CREDIX_VAULTS[3]).balanceOf(SonicConstantsLib.METAVAULT_METASCUSD);

        for (uint i; i < 4; ++i) {
            state.credixVaultTotalSupply[i] = IVault(CREDIX_VAULTS[i]).totalSupply();
            //            console.log("Credix vault", i, CREDIX_VAULTS[i], state.credixVaultTotalSupply[i]);
            //            console.log("Credix vault mv", i, CREDIX_VAULTS[i], state.credixVaultMetavaultBalance[i]);
        }

        return state;
    }

    function _getUserBalances(
        address metaVault_,
        address[] memory users
    ) internal view returns (uint[] memory balances) {
        balances = new uint[](users.length);
        for (uint i = 0; i < users.length; ++i) {
            balances[i] = IERC20(metaVault_).balanceOf(users[i]);
        }
        return balances;
    }

    function _createRealRecoveryToken(address metaVault_, bytes32 salt) internal returns (address _recoveryToken) {
        vm.prank(multisig);
        _recoveryToken = metaVaultFactory.deployRecoveryToken(salt, metaVault_);

        assertEq(IRecoveryToken(_recoveryToken).target(), metaVault_, "recovery token target should be metaVault_");

        for (uint i; i < CREDIX_VAULTS.length; ++i) {
            vm.prank(multisig);
            IMetaVault(metaVault_).setRecoveryToken(CREDIX_VAULTS[i], address(_recoveryToken));
        }

        recoveryTokens.push(address(_recoveryToken));
        return _recoveryToken;
    }

    function _whitelistVault(address metaVault_, address userToWhiteList) internal {
        vm.prank(multisig);
        IMetaVault(metaVault_).changeWhitelist(userToWhiteList, true);
    }

    function _reduceArrays(
        uint count,
        address[] memory owners,
        uint[] memory amounts,
        uint[] memory minAmountsOut,
        bool[] memory paused
    )
        internal
        pure
        returns (
            address[] memory reducedOwners,
            uint[] memory reducedAmounts,
            uint[] memory reducedMinAmountsOut,
            bool[] memory reducedPaused
        )
    {
        if (count != 0) {
            reducedOwners = new address[](count);
            reducedAmounts = new uint[](count);
            reducedMinAmountsOut = new uint[](count);
            reducedPaused = new bool[](count);

            for (uint i = 0; i < count; ++i) {
                reducedOwners[i] = owners[i];
                reducedAmounts[i] = amounts[i];
                reducedMinAmountsOut[i] = minAmountsOut[i];
                reducedPaused[i] = paused[i];
            }
        }

        return (reducedOwners, reducedAmounts, reducedMinAmountsOut, reducedPaused);
    }

    function _getTotalAmountRecoveryTokens(
        address recoveryToken,
        uint[] memory balances
    ) internal view returns (uint total) {
        for (uint i = 0; i < balances.length; ++i) {
            total += balances[i];
        }
        return total + IERC20(recoveryToken).balanceOf(multisig);
    }
    //endregion ---------------------------------------------- Internal

    //region ---------------------------------------------- _toDynamicArray
    function _toDynamicArray(address[COUNT_WRAPPED_META_USD_USERS] memory arr)
        internal
        pure
        returns (address[] memory dynamicArray)
    {
        dynamicArray = new address[](arr.length);
        for (uint i = 0; i < arr.length; ++i) {
            dynamicArray[i] = arr[i];
        }
    }

    function _toDynamicArray(address[COUNT_META_USD_USERS] memory arr)
        internal
        pure
        returns (address[] memory dynamicArray)
    {
        dynamicArray = new address[](arr.length);
        for (uint i = 0; i < arr.length; ++i) {
            dynamicArray[i] = arr[i];
        }
    }

    function _toDynamicArray(address[COUNT_WRAPPED_META_USDC_USERS] memory arr)
        internal
        pure
        returns (address[] memory dynamicArray)
    {
        dynamicArray = new address[](arr.length);
        for (uint i = 0; i < arr.length; ++i) {
            dynamicArray[i] = arr[i];
        }
    }

    function _toDynamicArray(address[COUNT_WRAPPED_META_SCUSD_USERS] memory arr)
        internal
        pure
        returns (address[] memory dynamicArray)
    {
        dynamicArray = new address[](arr.length);
        for (uint i = 0; i < arr.length; ++i) {
            dynamicArray[i] = arr[i];
        }
    }

    function _toDynamicArray(address[COUNT_META_SCUSD_USERS] memory arr)
        internal
        pure
        returns (address[] memory dynamicArray)
    {
        dynamicArray = new address[](arr.length);
        for (uint i = 0; i < arr.length; ++i) {
            dynamicArray[i] = arr[i];
        }
    }
    //endregion ---------------------------------------------- _toDynamicArray

    //region ---------------------------------------------- Helpers
    function _upgradeMetaVault(address metaVault_) internal {
        address vaultImplementation = address(new MetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(vaultImplementation);
        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(metaVault_);
        vm.prank(multisig);
        metaVaultFactory.upgradeMetaProxies(metaProxies);
    }

    function _upgradeAmfStrategy(address strategy_) public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        // deploy new impl and upgrade
        address strategyImplementation = address(new AaveMerklFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.AAVE_MERKL_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategy_);
    }

    function _upgradeSiloStrategy(address strategy_) public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        // deploy new impl and upgrade
        address strategyImplementation = address(new SiloStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO, strategyImplementation);

        factory.upgradeStrategyProxy(strategy_);
    }

    function _upgradeCVault(address cVault_) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        // deploy new impl and upgrade
        address vaultImplementation = address(new CVault());
        vm.prank(multisig);
        factory.setVaultImplementation(VaultTypeLib.COMPOUNDING, vaultImplementation);
        factory.upgradeVaultProxy(address(cVault_));
    }

    function _upgradeWrappedMetaVaults() internal {
        address newWrapperImplementation = address(new WrappedMetaVault());

        vm.startPrank(multisig);
        metaVaultFactory.setWrappedMetaVaultImplementation(newWrapperImplementation);

        address[] memory proxies = new address[](3);
        proxies[0] = SonicConstantsLib.WRAPPED_METAVAULT_METAUSD;
        proxies[1] = SonicConstantsLib.WRAPPED_METAVAULT_METAUSDC;
        proxies[2] = SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD;

        metaVaultFactory.upgradeMetaProxies(proxies);
        vm.stopPrank();
    }

    function _showAmounts(
        address parentVault,
        address cVault_,
        address[] memory owners,
        uint[] memory amounts,
        uint[] memory minAmountsOut,
        bool shares
    ) internal pure {
        console.log("============ Start withdraw (meta/wrapped, c-vault):", parentVault, cVault_);
        console.log("owner", shares ? "shares" : "amounts", "minAmountsOut");
        for (uint i = 0; i < owners.length; ++i) {
            console.log(owners[i], amounts[i], minAmountsOut[i]);
        }
        console.log("============ End withdraw");
    }

    function _getVaultIndex(address metaVault_, address vault_) internal view returns (uint) {
        address[] memory vaults = IMetaVault(metaVault_).vaults();
        for (uint i = 0; i < vaults.length; ++i) {
            if (vaults[i] == vault_) {
                return i;
            }
        }
        revert(string(abi.encodePacked("_getVaultIndex: Vault not found")));
    }

    /// @param value Set 1e16 to be able to withdraw or 0 to be able to remove
    function _setProportion(address metaVault_, uint targetIndex, uint fromIndex, uint value) internal {
        uint total = 0;
        uint[] memory props = IMetaVault(metaVault_).currentProportions();
        for (uint i = 0; i < props.length; ++i) {
            if (i != targetIndex && i != fromIndex) {
                total += props[i];
            }
        }

        props[fromIndex] = 1e18 - total - value;
        props[targetIndex] = value;

        vm.prank(multisig);
        IMetaVault(metaVault_).setTargetProportions(props);

        // _showProportions(metaVault_);
        // console.log(metaVault_.vaultForDeposit(), metaVault_.vaultForWithdraw());
    }

    function _upgradePlatform() internal {
        metaVaultFactory = IMetaVaultFactory(SonicConstantsLib.METAVAULT_FACTORY);

        address[] memory proxies = new address[](1);
        proxies[0] = address(metaVaultFactory);

        address[] memory implementations = new address[](1);
        implementations[0] = address(new MetaVaultFactory());

        vm.prank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.08.0-alpha", proxies, implementations);

        skip(1 days);

        vm.prank(multisig);
        IPlatform(PLATFORM).upgrade();
    }

    function _setupMetaVaultFactory() internal {
        address recoveryTokenImplementation = address(new RecoveryToken());
        vm.prank(multisig);
        metaVaultFactory.setRecoveryTokenImplementation(recoveryTokenImplementation);
    }

    function _upgradeFactory() internal {
        // deploy new Factory implementation
        address newImpl = address(new Factory());

        // get the proxy address for the factory
        address factoryProxy = address(IPlatform(PLATFORM).factory());

        // prank as the platform because only it can upgrade
        vm.prank(PLATFORM);
        IProxy(factoryProxy).upgrade(newImpl);
    }

    //endregion ---------------------------------------------- Helpers
}
