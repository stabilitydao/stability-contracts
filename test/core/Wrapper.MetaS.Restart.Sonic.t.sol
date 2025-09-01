// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {RecoveryToken} from "../../src/core/vaults/RecoveryToken.sol";
import {AaveMerklFarmStrategy} from "../../src/strategies/AaveMerklFarmStrategy.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {IAToken} from "../../src/integrations/aave/IAToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPool} from "../../src/integrations/aave/IPool.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IRecoveryToken} from "../../src/interfaces/IRecoveryToken.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";
import {MetaVaultFactory} from "../../src/core/MetaVaultFactory.sol";
import {console, Test} from "forge-std/Test.sol";

contract WrapperMetaSRestartSonicTest is Test {
    // uint public constant FORK_BLOCK = 42601861; // Aug-12-2025 03:58:17 AM +UTC
    uint public constant FORK_BLOCK = 42752713; // Aug-13-2025 05:01:05 AM +UTC

    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVaultFactory public metaVaultFactory;
    IPriceReader public priceReader;
    address public multisig;
    IWrappedMetaVault public wrappedMetaVault;

    uint internal constant COUNT_WRAPPED_META_S = 18;
    uint internal constant COUNT_META_S = 48;
    uint internal constant COUNT_WRAPPED_META_WS = 1;
    uint internal constant COUNT_META_WS = 1;

    address[COUNT_WRAPPED_META_S] internal WRAPPED_META_S_LARGEST_HOLDERS;
    address[COUNT_META_S] internal META_S_LARGEST_HOLDERS;
    address[COUNT_WRAPPED_META_WS] internal WRAPPED_META_WS_LARGEST_HOLDERS;
    address[COUNT_META_WS] internal META_WS_LARGEST_HOLDERS;

    // broken vaults in metaWS
    address public constant VAULT_1_WS = SonicConstantsLib.VAULT_C_Credix_wS_AMFa0;
    address public constant VAULT_2_WS = SonicConstantsLib.VAULT_C_Credix_wS_AMFa5;

    address[2] internal CREDIX_VAULTS;

    /// @notice [WMetaS, WMetaWS, MetaS, MetaWS]
    address[] internal recoveryTokens;

    /// @notice [WMetaS, WMetaWS, MetaS, MetaWS]
    address[4] internal SMALL_USERS;

    struct UserAddresses {
        address[] wmetaSOwner;
        address[] metaSOwner;
        address[] wmetaWsOwner;
        address[] metaWsOwner;
    }

    struct UserBalances {
        uint[] wmetaSBalance;
        uint[] metaSBalance;
        uint[] wmetaWsBalance;
        uint[] metaWsBalance;
    }

    struct State {
        uint wmetaSBalanceInMetaS;
        uint wmetaWsBalanceInMetaWs;
        uint wmetaSPrice;
        uint wmetaSPriceDirectCalculations;
        uint wmetaWsPrice;
        uint wsPrice;
        uint wmetaSTotalAssets;
        uint wmetaWsTotalAssets;
        uint wmetaSTotalSupply;
        uint wmetaWsTotalSupply;
        uint metaSMultisigBalance;
        uint metaSTotalSupply;
        uint metaWsMultisigBalance;
        uint metaWsTotalSupply;
        uint[] vaultUnderlyingBalance;
        UserBalances metaVault;
        UserBalances[2] underlying;
        UserBalances[] recoveryToken;
        uint[2] credixVaultTotalSupply;
        uint[2] credixVaultMetavaultBalance;
    }

    struct WithdrawUnderlyingLocal {
        IMetaVault metaVault;
        address[] owners;
        uint[] minAmountsOut;
        bool[] paused;
        uint count;
        uint decimals;
        uint totalAmounts;
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        multisig = IPlatform(PLATFORM).multisig();
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        metaVaultFactory = IMetaVaultFactory(SonicConstantsLib.METAVAULT_FACTORY);
        wrappedMetaVault = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD);

        CREDIX_VAULTS = [VAULT_1_WS, VAULT_2_WS];

        WRAPPED_META_S_LARGEST_HOLDERS = [
            0xC37fa1c70D77bdEd373C551a92bAbcee44a9d04E,
            0x1c1791911483E98875D162355feC47f37613f0FB,
            0xD58f0042811A2Af932d8eA2D7466123ce9052Cde,
            0xCe6c0bd926A76D715C829bE4965ad064447d754F,
            0x1b648ade1eF219C87987CD60eBa069A7FAf1621f,
            0x83827DF1aCFc523288fC3fdFc87236bc3A746080,
            0x7aF31CF5475b2b91F202d5811b5487f114821190,
            0xf0a85BA66b3F0858Dc466Cd2BD75c5aAD0cB3A19,
            0x2a1842baC18058078F682e1996f763480081174A,
            0x34b611E1B5d5441ab013B7eE2D8226a7D4FdeeE7,
            0xeb7DF1C8BFb37F6470788A1F8b20F37e46Ca383e,
            0x23Cd671c5FB77251579Ae915Dc3581Bf099338ee,
            0x2493b7809F8ED73224A6867A8b82b7329FA598a7,
            0xe8B8f2467d096740f9F71a3a98B3E424FBc98531,
            0x6cbd743d9b97DA1855E64893D3226F8eDCa16e76,
            0xb6fFAF2d839f630554B4cd7ffc922D60B52F5abC,
            0x28aa4F9ffe21365473B64C161b566C3CdeAD0108,
            0x349A27b247016B4cce4f5ab7B89689F6ED9958f5
        ];

        META_S_LARGEST_HOLDERS = [
            0x1680779cfd4e3779fe5339DaA863439215C9e4e4,
            0x10790532244b49b7a51Af3403dCD917381B3DF9F,
            0xe22A5e05F2D0CAB8a49d0C3c49819f0d03DA96C3,
            0x6dD8b1bD490e14bF3DA72450D6d6112276Ac986e,
            0x24e9A18A75fAceedd14aEeE845C0b8c66f112F91,
            0x3c5Aac016EF2F178e8699D6208796A2D67557fe2,
            0x3eFed426257B1493e4FaD8f54361649642f5b43E,
            0xdF5e92e18c282B61b509Fb3223BaC6c4d0C8dEE6,
            0x8C9C2f167792254C651FcA36CA40Ed9a229e5921,
            0xb4cE0c954bB129D8039230F701bb6503dca1Ee8c,
            0x55B533f484E9aeBDc30460b59f1E3FfCe06D7942,
            0x8040fA90f682EC9d6a1D6CC0CD14C996710940fE,
            0xa3Ed9C58CBC9CcB0305E6d9885BbfFe15dff45c2,
            0x308c267632d51872cd10d1eB73C1a45159AE860E,
            0xe8770F09190054248f64243732b71A043A7725B2,
            0x1d255b9862bab86Ebbc79d105795F33CABE5Cc21,
            0x2d8FeDb175fd645595FfD95D3432b0A1e93f82b1,
            0x34b611E1B5d5441ab013B7eE2D8226a7D4FdeeE7,
            0x17B72bf643a1c8356D2bB264A42bFCD4dfa3661C,
            0xD353eCd864966601b456f0b498D6866Cb0986A60,
            0x68aeDee7DC9da33A1E7D32a6637361E409c40519,
            0x58f49739550F95dEAB7FeF8A1f20cEe46e50eD74,
            0x59603A3AB3e33F07A2B9a4419399d502a1Fb6a95,
            0x417DFBdA9573513BA0Bb137D1e85853b6Afbb461,
            0xd63295C755F84FCd57663Ea2e2f9E6fee1830139,
            0x99B943107eBCAc233EBE89478eFA7d1783c6D689,
            0xD41C0eC18dF28F6Be6942ADDAB960EB25B4232a3,
            0x2a1842baC18058078F682e1996f763480081174A,
            0xc2d5904602e2d76D3D04EC28A5A1c52E136C4475,
            0xE1C5A94Bfbfbeb910AD491F53578C5674D3C031b,
            0x2a18c99657F56D2973b8E6A1bc3bD403CeB00404,
            0x5d4361564cDF2c63Cd411934ec20b3CaD9553A3e,
            0xE945BfDE6344f64062B43B1C2856C5Fa5D58600E,
            0xA51A6F181D7BdE6F4fc445Ff844fa9329616C01a,
            0x795955044c990f85511F367b4f6Dc261D2048fFF,
            0x752f44dbA6c9AFcfaaEc26f90814411979B5b82F,
            0x80dD5ed80908321c8A08Da17d7121D3d2Fb032DA,
            0x9aC21fA62d237E9198D41A1dF1DE5E2fbf843071,
            0x58235E19B7D6B1852F21649EC185a13aFA183248,
            0xE229396108E802190AcbFAF4972a81Ad79d814F3,
            0x7FbF1B4553D2bB814984593437f2d83D3d51330A,
            0xD84F88AC551b65fFD3007Fc536b02c9B643e983D,
            0xa7fa4910beF6aEbe19F0d609389E37c103eeC9b5,
            0x582b4d38eE61f8d42b348c9D65871004571AE8A5,
            0x02443d1fCb2a76C99Bf9BDf89de7F048d26eaDbA,
            0xE2cbb3353013Fb8DCF7098ed925A9c442a674080,
            0xD2625cA08ECD15693584e8B7E3E54c3a5A761C1B,
            0x89923bbbED3d508914c99E8a9f19d41aED42Ff17
        ];

        WRAPPED_META_WS_LARGEST_HOLDERS = [0xb5e6b895734409Df411a052195eb4EE7e40d8696];

        META_WS_LARGEST_HOLDERS = [0x752f44dbA6c9AFcfaaEc26f90814411979B5b82F];

        SMALL_USERS = [
            0xaC041Df48dF9791B0654f1Dbbf2CC8450C5f2e9D,
            0xF2Bc8850E4a0e35bc039C0a06fe3cD941a75dB56,
            0x093308DC6b31e4bfE980405ae8a80748fCd3E4b7,
            0x88888887C3ebD4a33E34a15Db4254C74C75E5D4A
        ];
    }

    /// @notice Restart MetaS: withdraw all broken underlying, replace it by real assets and recovery tokens
    function testRestartMetaS() public {
        UserAddresses memory users = _getUsers();
        // ---------------------------------- upgrade strategies and vaults
        console.log("Upgrade");
        {
            _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaS);
            _upgradeMetaVault(SonicConstantsLib.METAVAULT_metawS);
            _upgradeWrappedMetaVaults();

            for (uint i; i < 2; ++i) {
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
            _upgradePlatform();
            _setupMetaVaultFactory();

            _createRealRecoveryToken(SonicConstantsLib.WRAPPED_METAVAULT_metaS, 0x00);
            _createRealRecoveryToken(SonicConstantsLib.WRAPPED_METAVAULT_metawS, bytes32(uint(0x01)));

            _createRealRecoveryToken(SonicConstantsLib.METAVAULT_metaS, bytes32(uint(0x03)));
            _createRealRecoveryToken(SonicConstantsLib.METAVAULT_metawS, bytes32(uint(0x04)));
        }

        // ---------------------------------- whitelist vaults
        console.log("Whitelist");
        {
            _whitelistVault(SonicConstantsLib.METAVAULT_metaS, SonicConstantsLib.WRAPPED_METAVAULT_metaS);

            _whitelistVault(SonicConstantsLib.METAVAULT_metawS, SonicConstantsLib.METAVAULT_metaS);
            _whitelistVault(SonicConstantsLib.METAVAULT_metawS, SonicConstantsLib.WRAPPED_METAVAULT_metawS);
        }

        // ---------------------------------- save initial state
        console.log("Get state");
        State memory state0 = _getState(users);

        // ---------------------------------- withdraw underlying in emergency, provide recovery tokens for large users
        console.log("Withdraw underlying to users");
        {
            // metaWs vault
            for (uint i; i < 2; i++) {
                console.log("!!!!!!!!!! Withdraw from MetaWs.CVault", i, CREDIX_VAULTS[i]);
                _redeemUnderlyingEmergency(
                    SonicConstantsLib.WRAPPED_METAVAULT_metawS, CREDIX_VAULTS[i], users.wmetaWsOwner
                );
                _withdrawUnderlyingEmergency(SonicConstantsLib.METAVAULT_metawS, CREDIX_VAULTS[i], users.metaWsOwner);
            }

            // metaS vault
            for (uint i; i < 2; i++) {
                console.log("!!!!!!!!!! Withdraw from MetaS.CVault", i, CREDIX_VAULTS[i]);
                _redeemUnderlyingEmergency(
                    SonicConstantsLib.WRAPPED_METAVAULT_metaS, CREDIX_VAULTS[i], users.wmetaSOwner
                );
                _withdrawUnderlyingEmergency(SonicConstantsLib.METAVAULT_metaS, CREDIX_VAULTS[i], users.metaSOwner);
            }
        }

        // ---------------------------------- check current state
        console.log("Get state");
        _getState(users);

        // ---------------------------------- deposit into metaUSD by multisig to be able to withdraw all left broken underlying
        {
            console.log("!!!!!!!!!!!!!!!!!!!!!!!! Deposit to metaS");
            (uint amount, address asset) = _depositToMetaVault(SonicConstantsLib.METAVAULT_metaS);
            console.log("MetaS: amount, asset", amount, IERC20Metadata(asset).symbol());

            console.log("!!!!!!!!!!!!!!!!!!!!!!!! Deposit to metaWs");
            (amount, asset) = _depositToMetaVault(SonicConstantsLib.METAVAULT_metawS);
            console.log("MetaWs: amount, asset", amount, IERC20Metadata(asset).symbol());
        }

        // ---------------------------------- check current state
        console.log("Get state");
        _getState(users);

        // ---------------------------------- withdraw underlying in emergency for multisig
        console.log("Withdraw underlying to multisig");
        {
            address[] memory govUsers = new address[](1);
            govUsers[0] = multisig;
            for (uint i; i < 2; i++) {
                console.log("------- Withdraw leftovers from MetaS.CVault", i, CREDIX_VAULTS[i]);
                _withdrawUnderlyingEmergency(SonicConstantsLib.METAVAULT_metaS, CREDIX_VAULTS[i], govUsers);
            }

            for (uint i; i < 2; i++) {
                console.log("------- Withdraw leftovers from MetaWs.CVault", i, CREDIX_VAULTS[i]);
                _withdrawUnderlyingEmergency(SonicConstantsLib.METAVAULT_metawS, CREDIX_VAULTS[i], govUsers);
            }
        }

        // ---------------------------------- check current state: ensure that there is 0 broken underlying in metaUSD
        State memory stateFinal = _getState(users);

        {
            for (uint i; i < 2; i++) {
                assertApproxEqAbs(
                    stateFinal.credixVaultMetavaultBalance[i], 0, 1e11, "Underlying balance in Credix vault should be 0"
                );
            }
            assertApproxEqAbs(
                stateFinal.credixVaultTotalSupply[0],
                28810731988307383734,
                10,
                "Vault 1 - only direct deposits should be left"
            );
            assertApproxEqAbs(
                stateFinal.credixVaultTotalSupply[1],
                1224903202417982033992,
                10,
                "Vault 2 - only direct deposits should be left"
            );

            assertApproxEqAbs(stateFinal.wmetaSPrice, state0.wmetaSPrice, 1, "S-Wrapped price should be the same 1");
            assertApproxEqAbs(
                stateFinal.wmetaSPriceDirectCalculations,
                state0.wmetaSPriceDirectCalculations,
                state0.wmetaSPriceDirectCalculations / 100_000,
                "S-Wrapped price should be the same 2"
            );
            assertApproxEqAbs(
                stateFinal.wmetaSPrice,
                state0.wmetaSPriceDirectCalculations,
                state0.wmetaSPriceDirectCalculations / 100_000,
                "S-Wrapped price should be the same 3"
            );
            assertApproxEqAbs(
                stateFinal.wmetaWsPrice,
                state0.wmetaWsPrice,
                state0.wmetaWsPrice / 100_000,
                "Usdc-Wrapped price should be the same"
            );
        }

        // ---------------------------------- check meta vault balances
        {
            for (uint i; i < users.wmetaSOwner.length; ++i) {
                if (state0.metaVault.wmetaSBalance[i] > 10e18) {
                    // large user
                    assertApproxEqAbs(stateFinal.metaVault.wmetaSBalance[i], 0, 1, "Large user has no wmetaS");
                }
            }

            for (uint i; i < users.wmetaWsOwner.length; ++i) {
                if (state0.metaVault.wmetaWsBalance[i] > 10e18) {
                    // large user
                    assertApproxEqAbs(stateFinal.metaVault.wmetaWsBalance[i], 0, 1, "Large user has no wmetaWs");
                }
            }

            for (uint i; i < users.metaSOwner.length; ++i) {
                if (state0.metaVault.metaSBalance[i] > 10e18) {
                    // large user
                    assertApproxEqAbs(stateFinal.metaVault.metaSBalance[i], 0, 1, "Large user has no metaS");
                }
            }

            for (uint i; i < users.metaWsOwner.length; ++i) {
                if (state0.metaVault.metaWsBalance[i] > 10e18) {
                    // large user
                    //                    console.log(i, users.metaWsOwner[i],
                    //                        stateFinal.metaVault.metaWsBalance[i],
                    //                        state0.metaVault.metaWsBalance[i]
                    //                    );
                    assertApproxEqAbs(stateFinal.metaVault.metaWsBalance[i], 0, 1, "Large user has no metaWs");
                }
            }
        }

        // ---------------------------------- check amounts of recovery tokens
        {
            //            console.log("Recovery token", recoveryTokens[0]);
            for (uint i; i < users.wmetaSOwner.length; ++i) {
                //                console.log("i, user, balance", i, users.wmetaSOwner[i], state0.metaVault.wmetaSBalance[i]);
                //                console.log("i, recovery tokens", i, stateFinal.recoveryToken[0].wmetaSBalance[i]);
                //                console.log("state0.wmetaSPrice", state0.wmetaSPrice, state0.wsPrice);
                assertApproxEqAbs(
                    state0.metaVault.wmetaSBalance[i] * state0.wmetaSPrice / state0.wsPrice, // amount of meta vault tokens
                    stateFinal.recoveryToken[0].wmetaSBalance[i],
                    stateFinal.recoveryToken[0].wmetaSBalance[i] / 100_000,
                    "Recovery token for wmetaS should be equal to initial balance of wmetaS"
                );
            }

            for (uint i; i < users.wmetaWsOwner.length; ++i) {
                //                console.log("eq", i, state0.metaVault.wmetaUsdcBalance[i] * state0.wmetaUsdcPrice / 1e18, stateFinal.recoveryToken[1].wmetaUsdcBalance[i]);
                assertApproxEqAbs(
                    state0.metaVault.wmetaWsBalance[i] * state0.wmetaWsPrice / 1e18, // amount of meta vault tokens
                    stateFinal.recoveryToken[1].wmetaWsBalance[i],
                    stateFinal.recoveryToken[1].wmetaWsBalance[i] / 100_000,
                    "Recovery token for wmetaWs should be equal to initial balance of wmetaWs"
                );
            }

            for (uint i; i < users.metaSOwner.length; ++i) {
                //                console.log("eq", i, state0.metaVault.metaUSDBalance[i], stateFinal.recoveryToken[3].metaUSDBalance[i]);
                assertApproxEqAbs(
                    state0.metaVault.metaSBalance[i],
                    stateFinal.recoveryToken[2].metaSBalance[i],
                    stateFinal.recoveryToken[2].metaSBalance[i] / 100_000,
                    "Recovery token for metaS should be equal to initial balance of metaS"
                );
            }

            for (uint i; i < users.metaWsOwner.length; ++i) {
                //                console.log("eq", i, state0.metaVault.metaScUsdBalance[i], stateFinal.recoveryToken[5].metaScUsdBalance[i]);
                assertApproxEqAbs(
                    state0.metaVault.metaWsBalance[i],
                    stateFinal.recoveryToken[3].metaWsBalance[i],
                    stateFinal.recoveryToken[3].metaWsBalance[i] / 100_000,
                    "Recovery token for metaWs should be equal to initial balance of metaWs"
                );
            }
        }

        // ---------------------------------- check total supply of recovery tokens
        {
            assertEq(
                _getTotalAmountRecoveryTokens(recoveryTokens[0], stateFinal.recoveryToken[0].wmetaSBalance),
                IERC20(recoveryTokens[0]).totalSupply(),
                "Total supply of wmetaS recovery token should be equal to sum of balances"
            );

            assertEq(
                _getTotalAmountRecoveryTokens(recoveryTokens[1], stateFinal.recoveryToken[1].wmetaWsBalance),
                IERC20(recoveryTokens[1]).totalSupply(),
                "Total supply of wmetaWs recovery token should be equal to sum of balances"
            );

            assertEq(
                _getTotalAmountRecoveryTokens(recoveryTokens[2], stateFinal.recoveryToken[2].metaSBalance),
                IERC20(recoveryTokens[2]).totalSupply(),
                "Total supply of metaS recovery token should be equal to sum of balances"
            );

            assertEq(
                _getTotalAmountRecoveryTokens(recoveryTokens[3], stateFinal.recoveryToken[3].metaWsBalance),
                IERC20(recoveryTokens[3]).totalSupply(),
                "Total supply of metaWs recovery token should be equal to sum of balances"
            );
        }

        // ---------------------------------- remove broken vaults
        {
            uint vaultIndex1 = _getVaultIndex(SonicConstantsLib.METAVAULT_metawS, VAULT_1_WS);
            uint vaultIndex2 = _getVaultIndex(SonicConstantsLib.METAVAULT_metawS, VAULT_2_WS);
            uint targetIndex = 0;

            assertNotEq(targetIndex, vaultIndex1, "targetIndex != vaultIndex1");
            assertNotEq(targetIndex, vaultIndex2, "targetIndex != vaultIndex2");
            assertGt(vaultIndex2, vaultIndex1, "vaultIndex2 > vaultIndex1");

            _setProportion(SonicConstantsLib.METAVAULT_metawS, vaultIndex2, targetIndex, 0);
            _setProportion(SonicConstantsLib.METAVAULT_metawS, vaultIndex1, targetIndex, 0);

            vm.prank(multisig);
            IMetaVault(SonicConstantsLib.METAVAULT_metawS).removeVault(VAULT_1_WS);

            vm.prank(multisig);
            IMetaVault(SonicConstantsLib.METAVAULT_metawS).removeVault(VAULT_2_WS);
        }

        // ---------------------------------- ensure that exist small users are able to withdraw their funds
        {
            _withdrawAsSmallUserFromWrapped(SonicConstantsLib.WRAPPED_METAVAULT_metaS, SMALL_USERS[0]);
            _withdrawAsSmallUserFromWrapped(SonicConstantsLib.WRAPPED_METAVAULT_metawS, SMALL_USERS[1]);
            _withdrawAsSmallUserFromMetaVault(SonicConstantsLib.METAVAULT_metaS, SMALL_USERS[2]);
            _withdrawAsSmallUserFromMetaVault(SonicConstantsLib.METAVAULT_metawS, SMALL_USERS[3]);
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
        uint totalMetaVaultTokens = v.metaVault.maxWithdrawUnderlying(cVault_, wrapped_) - 1e8; //* 999999999 / 1000000000;

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

                v.totalAmounts += amount;
                if (amount == maxAmount) {
                    shares[v.count] = 0;
                }

                v.count++;
                if (totalMetaVaultTokensToWithdraw == totalMetaVaultTokens) break;
            }

            console.log("Total amounts to redeem:", v.totalAmounts);

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

            v.totalAmounts += maxAmount;
            amounts[v.count] = maxAmount == balance ? 0 : maxAmount;
            v.owners[v.count] = users[i];
            v.minAmountsOut[v.count] = _getExpectedUnderlying(IVault(cVault_).strategy(), v.metaVault, maxAmount) - 1;
            v.count++;

            if (maxAmount != balance) break;
        }
        vm.revertToState(snapshot);
        console.log("Total amounts to withdraw:", v.totalAmounts);

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
        amountsMax[0] = _totalSupply * 1e18 / priceAsset * 101 / 100;
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
        dest.wmetaSOwner = _toDynamicArray(WRAPPED_META_S_LARGEST_HOLDERS);
        dest.metaSOwner = _toDynamicArray(META_S_LARGEST_HOLDERS);
        dest.wmetaWsOwner = _toDynamicArray(WRAPPED_META_WS_LARGEST_HOLDERS);
        dest.metaWsOwner = _toDynamicArray(META_WS_LARGEST_HOLDERS);

        return dest;
    }

    function _getState(UserAddresses memory users) internal view returns (State memory state) {
        state.vaultUnderlyingBalance = new uint[](2);
        state.vaultUnderlyingBalance[0] = IERC20(IVault(VAULT_1_WS).strategy().underlying()).balanceOf(VAULT_1_WS);
        state.vaultUnderlyingBalance[1] = IERC20(IVault(VAULT_2_WS).strategy().underlying()).balanceOf(VAULT_2_WS);

        state.wmetaSBalanceInMetaS =
            IERC20(SonicConstantsLib.METAVAULT_metaS).balanceOf(SonicConstantsLib.WRAPPED_METAVAULT_metaS);

        state.wmetaWsBalanceInMetaWs =
            IERC20(SonicConstantsLib.METAVAULT_metawS).balanceOf(SonicConstantsLib.WRAPPED_METAVAULT_metawS);

        //        console.log("wmetaSBalanceInMetaS", state.wmetaSBalanceInMetaS);
        //        console.log("wmetaWsBalanceInMetaWs", state.wmetaWsBalanceInMetaWs);

        state.metaVault.wmetaSBalance = _getUserBalances(SonicConstantsLib.WRAPPED_METAVAULT_metaS, users.wmetaSOwner);
        state.metaVault.metaSBalance = _getUserBalances(SonicConstantsLib.METAVAULT_metaS, users.metaSOwner);
        state.metaVault.wmetaWsBalance =
            _getUserBalances(SonicConstantsLib.WRAPPED_METAVAULT_metawS, users.wmetaWsOwner);
        state.metaVault.metaWsBalance = _getUserBalances(SonicConstantsLib.METAVAULT_metawS, users.metaWsOwner);

        for (uint i; i < 2; ++i) {
            state.underlying[i].wmetaSBalance =
                _getUserBalances(IVault(CREDIX_VAULTS[i]).strategy().underlying(), users.wmetaSOwner);
            state.underlying[i].metaSBalance =
                _getUserBalances(IVault(CREDIX_VAULTS[i]).strategy().underlying(), users.metaSOwner);
            state.underlying[i].wmetaWsBalance =
                _getUserBalances(IVault(CREDIX_VAULTS[i]).strategy().underlying(), users.wmetaWsOwner);
            state.underlying[i].metaWsBalance =
                _getUserBalances(IVault(CREDIX_VAULTS[i]).strategy().underlying(), users.metaWsOwner);
        }

        state.recoveryToken = new UserBalances[](recoveryTokens.length);
        for (uint i; i < recoveryTokens.length; ++i) {
            state.recoveryToken[i].wmetaSBalance = _getUserBalances(recoveryTokens[i], users.wmetaSOwner);
            state.recoveryToken[i].metaSBalance = _getUserBalances(recoveryTokens[i], users.metaSOwner);
            state.recoveryToken[i].wmetaWsBalance = _getUserBalances(recoveryTokens[i], users.wmetaWsOwner);
            state.recoveryToken[i].metaWsBalance = _getUserBalances(recoveryTokens[i], users.metaWsOwner);
        }

        state.wmetaSTotalAssets = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_metaS).totalAssets();

        state.wmetaWsTotalAssets = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_metawS).totalAssets();

        state.wmetaSTotalSupply = IERC20(SonicConstantsLib.WRAPPED_METAVAULT_metaS).totalSupply();

        state.wmetaWsTotalSupply = IERC20(SonicConstantsLib.WRAPPED_METAVAULT_metawS).totalSupply();

        state.metaSMultisigBalance = IERC20(SonicConstantsLib.METAVAULT_metaS).balanceOf(multisig);
        state.metaSTotalSupply = IERC20(SonicConstantsLib.METAVAULT_metaS).totalSupply();

        state.metaWsMultisigBalance = IERC20(SonicConstantsLib.METAVAULT_metawS).balanceOf(multisig);
        state.metaWsTotalSupply = IERC20(SonicConstantsLib.METAVAULT_metawS).totalSupply();

        (state.wsPrice,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(SonicConstantsLib.TOKEN_wS);

        (state.wmetaSPrice,) =
            IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(SonicConstantsLib.WRAPPED_METAVAULT_metaS);
        state.wmetaSPriceDirectCalculations = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_metaS).totalAssets()
            * state.wsPrice / IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_metaS).totalSupply();

        state.wmetaWsPrice = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_metawS).totalAssets() * 1e18
            / IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_metawS).totalSupply();

        state.credixVaultMetavaultBalance[0] = IVault(CREDIX_VAULTS[0]).balanceOf(SonicConstantsLib.METAVAULT_metawS);
        state.credixVaultMetavaultBalance[1] = IVault(CREDIX_VAULTS[1]).balanceOf(SonicConstantsLib.METAVAULT_metawS);

        for (uint i; i < 2; ++i) {
            state.credixVaultTotalSupply[i] = IVault(CREDIX_VAULTS[i]).totalSupply();
            console.log("Credix vault", i, CREDIX_VAULTS[i], state.credixVaultTotalSupply[i]);
            console.log("Credix vault mv", i, CREDIX_VAULTS[i], state.credixVaultMetavaultBalance[i]);
        }

        return state;
    }

    function _getUserBalances(address token, address[] memory users) internal view returns (uint[] memory balances) {
        // console.log("!!!!!!!!!!!!!!!!!!!!! balances of", token, IERC20Metadata(token).symbol());
        balances = new uint[](users.length);
        for (uint i = 0; i < users.length; ++i) {
            balances[i] = IERC20(token).balanceOf(users[i]);
            // console.log("balance of user", i, users[i], balances[i]);
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
    function _toDynamicArray(address[COUNT_WRAPPED_META_S] memory arr)
        internal
        pure
        returns (address[] memory dynamicArray)
    {
        dynamicArray = new address[](arr.length);
        for (uint i = 0; i < arr.length; ++i) {
            dynamicArray[i] = arr[i];
        }
    }

    function _toDynamicArray(address[COUNT_META_S] memory arr) internal pure returns (address[] memory dynamicArray) {
        dynamicArray = new address[](arr.length);
        for (uint i = 0; i < arr.length; ++i) {
            dynamicArray[i] = arr[i];
        }
    }

    function _toDynamicArray(address[COUNT_WRAPPED_META_WS] memory arr)
        internal
        pure
        returns (address[] memory dynamicArray)
    {
        dynamicArray = new address[](arr.length);
        for (uint i = 0; i < arr.length; ++i) {
            dynamicArray[i] = arr[i];
        }
    }

    // it's commented because COUNT_WRAPPED_META_WS is equal to COUNT_META_WS
    //    function _toDynamicArray(address[COUNT_META_WS] memory arr)
    //        internal
    //        pure
    //        returns (address[] memory dynamicArray)
    //    {
    //        dynamicArray = new address[](arr.length);
    //        for (uint i = 0; i < arr.length; ++i) {
    //            dynamicArray[i] = arr[i];
    //        }
    //    }
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
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.AAVE_MERKL_FARM,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: false,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategy_);
    }

    function _upgradeSiloStrategy(address strategy_) public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        // deploy new impl and upgrade
        address strategyImplementation = address(new SiloStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: false,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategy_);
    }

    function _upgradeCVault(address cVault_) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        // deploy new impl and upgrade
        address vaultImplementation = address(new CVault());
        vm.prank(multisig);
        factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: VaultTypeLib.COMPOUNDING,
                implementation: vaultImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: 1e10
            })
        );
        factory.upgradeVaultProxy(address(cVault_));
    }

    function _upgradeWrappedMetaVaults() internal {
        address newWrapperImplementation = address(new WrappedMetaVault());

        vm.startPrank(multisig);
        metaVaultFactory.setWrappedMetaVaultImplementation(newWrapperImplementation);

        address[] memory proxies = new address[](2);
        proxies[0] = SonicConstantsLib.WRAPPED_METAVAULT_metaS;
        proxies[1] = SonicConstantsLib.WRAPPED_METAVAULT_metawS;

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
        IPlatform(PLATFORM).cancelUpgrade(); // cancel exist announcing

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

    //endregion ---------------------------------------------- Helpers
}
