// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LogDeployLib, console} from "../script/libs/LogDeployLib.sol";
import {VaultTypeLib} from "../src/core/libs/VaultTypeLib.sol";
import {Proxy} from "../src/core/proxy/Proxy.sol";
import {CVault} from "../src/core/vaults/CVault.sol";
import {PriceReader} from "../src/core/PriceReader.sol";
import {IPlatformDeployer} from "../src/interfaces/IPlatformDeployer.sol";
import {IPlatform} from "../src/interfaces/IPlatform.sol";
import {ISwapper} from "../src/interfaces/ISwapper.sol";
import {IFactory} from "../src/interfaces/IFactory.sol";
import {IPriceReader} from "../src/interfaces/IPriceReader.sol";
import {IBalancerAdapter} from "../src/interfaces/IBalancerAdapter.sol";
import {CommonLib} from "../src/core/libs/CommonLib.sol";
import {AmmAdapterIdLib} from "../src/adapters/libs/AmmAdapterIdLib.sol";
import {DeployAdapterLib} from "../script/libs/DeployAdapterLib.sol";
import {Api3Adapter} from "../src/adapters/Api3Adapter.sol";
import {IBalancerGauge} from "../src/integrations/balancer/IBalancerGauge.sol";
import {StrategyIdLib} from "../src/strategies/libs/StrategyIdLib.sol";
import {BeetsStableFarm} from "../src/strategies/BeetsStableFarm.sol";
import {StrategyDeveloperLib} from "../src/strategies/libs/StrategyDeveloperLib.sol";
import {IGaugeEquivalent} from "../src/integrations/equalizer/IGaugeEquivalent.sol";
import {EqualizerFarmStrategy} from "../src/strategies/EqualizerFarmStrategy.sol";
import {BeetsWeightedFarm} from "../src/strategies/BeetsWeightedFarm.sol";
import {IGaugeV2_CL} from "../src/integrations/swapx/IGaugeV2_CL.sol";
import {IGaugeV2} from "../src/integrations/swapx/IGaugeV2.sol";
import {IICHIVault} from "../src/integrations/ichi/IICHIVault.sol";
import {IchiSwapXFarmStrategy} from "../src/strategies/IchiSwapXFarmStrategy.sol";
import {SwapXFarmStrategy} from "../src/strategies/SwapXFarmStrategy.sol";
import {IHypervisor} from "../src/integrations/gamma/IHypervisor.sol";
import {ALMPositionNameLib} from "../src/strategies/libs/ALMPositionNameLib.sol";
import {ALMLib} from "../src/strategies/libs/ALMLib.sol";
import {GammaUniswapV3MerklFarmStrategy} from "../src/strategies/GammaUniswapV3MerklFarmStrategy.sol";
import {SiloFarmStrategy} from "../src/strategies/SiloFarmStrategy.sol";
import {ISiloIncentivesController} from "../src/integrations/silo/ISiloIncentivesController.sol";
import {IGaugeV3} from "../src/integrations/shadow/IGaugeV3.sol";
import {ALMShadowFarmStrategy} from "../src/strategies/ALMShadowFarmStrategy.sol";
import {SiloLeverageStrategy} from "../src/strategies/SiloLeverageStrategy.sol";
import {SiloAdvancedLeverageStrategy} from "../src/strategies/SiloAdvancedLeverageStrategy.sol";
import {GammaEqualizerFarmStrategy} from "../src/strategies/GammaEqualizerFarmStrategy.sol";

/// @dev Sonic network [chainId: 146] data library
//   _____             _
//  / ____|           (_)
// | (___   ___  _ __  _  ___
//  \___ \ / _ \| '_ \| |/ __|
//  ____) | (_) | | | | | (__
// |_____/ \___/|_| |_|_|\___|
//
/// @author Alien Deployer (https://github.com/a17)
library SonicLib {
    // initial addresses
    address public constant MULTISIG = 0xF564EBaC1182578398E94868bea1AbA6ba339652;

    // ERC20
    address public constant TOKEN_wS = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
    address public constant TOKEN_wETH = 0x50c42dEAcD8Fc9773493ED674b675bE577f2634b;
    address public constant TOKEN_USDC = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address public constant TOKEN_stS = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;
    address public constant TOKEN_BEETS = 0x2D0E0814E62D80056181F5cd932274405966e4f0;
    address public constant TOKEN_EURC = 0xe715cbA7B5cCb33790ceBFF1436809d36cb17E57;
    address public constant TOKEN_EQUAL = 0xddF26B42C1d903De8962d3F79a74a501420d5F19;
    address public constant TOKEN_scUSD = 0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE;
    address public constant TOKEN_GOGLZ = 0x9fDbC3f8Abc05Fa8f3Ad3C17D2F806c1230c4564;
    address public constant TOKEN_SACRA = 0x7AD5935EA295c4E743e4f2f5B4CDA951f41223c2;
    address public constant TOKEN_SACRA_GEM_1 = 0xfC0dd337b92Baa949bC5D25FD9A99Cb3b6873204;
    address public constant TOKEN_SWPx = 0xA04BC7140c26fc9BB1F36B1A604C7A5a88fb0E70;
    address public constant TOKEN_scETH = 0x3bcE5CB273F0F148010BbEa2470e7b5df84C7812;
    address public constant TOKEN_atETH = 0x284D81e48fBc782Aa9186a03a226690aEA5cBe0E;
    address public constant TOKEN_AUR = 0x7F144F8691CbA3d2EfD8e5bcf042f9303EE31a46;
    address public constant TOKEN_auUSDC = 0xd6a69EBFa44f78cEe454A2Df2C77751A42f8f38c;
    //address public constant TOKEN_NAVI = 0x6881B80ea7C858E4aEEf63893e18a8A36f3682f3;
    //address public constant TOKEN_ECO = 0x7A08Bf5304094CA4C7b4132Ef62b5EDc4a3478B7;
    //address public constant TOKEN_INDI = 0x4EEC869d847A6d13b0F6D1733C5DEC0d1E741B4f;
    address public constant TOKEN_BRUSH = 0xE51EE9868C1f0d6cd968A8B8C8376Dc2991BFE44;
    //address public constant TOKEN_TYSG = 0x56192E94434c4fd3278b4Fa53039293fB00DE3DB;
    //address public constant TOKEN_Missor = 0xf26B3Fd147619Df61D4c1D0a9F7200B31A73FAfa;
    //address public constant TOKEN_WOOF = 0x7F883dA3B0d77978075f7C9c03E1B9F461CA1B8d; // extra cheap
    //address public constant TOKEN_DONKS = 0x0a54364631Ea37813a63edb3bBa1C46f8d8304B2;
    //address public constant TOKEN_TAILS = 0x41211648C51AcB9A5F39A93C657e894A0bdB88e4;
    //address public constant TOKEN_THC = 0x17Af1Df44444AB9091622e4Aa66dB5BB34E51aD5;
    address public constant TOKEN_FS = 0xBC0d0650412EF353D672c0Bbd12eFFF90591B251;
    address public constant TOKEN_sDOG = 0x50Bc6e1DfF8039A4b967c1BF507ba5eA13fa18B6;
    address public constant TOKEN_MOON = 0x486B6Fa0419b33a0c7A6e4698c231D7E2f2D5299;
    address public constant TOKEN_OS = 0xb1e25689D55734FD3ffFc939c4C3Eb52DFf8A794;
    address public constant TOKEN_SHADOW = 0x3333b97138D4b086720b5aE8A7844b1345a33333;
    address public constant TOKEN_xSHADOW = 0x5050bc082FF4A74Fb6B0B04385dEfdDB114b2424;
    address public constant TOKEN_sGEM1 = 0x9A08cD5691E009cC72E2A4d8e7F2e6EE14E96d6d;
    address public constant TOKEN_stkscUSD = 0x4D85bA8c3918359c78Ed09581E5bc7578ba932ba;
    address public constant TOKEN_wstkscUSD = 0x9fb76f7ce5FCeAA2C42887ff441D46095E494206;
    address public constant TOKEN_stkscETH = 0x455d5f11Fea33A8fa9D3e285930b478B6bF85265;
    address public constant TOKEN_wstkscETH = 0xE8a41c62BB4d5863C6eadC96792cFE90A1f37C47;
    address public constant TOKEN_wOS = 0x9F0dF7799f6FDAd409300080cfF680f5A23df4b1;
    address public constant TOKEN_STBL = 0x78a76316F66224CBaCA6e70acB24D5ee5b2Bd2c7;
    address public constant TOKEN_anS = 0x0C4E186Eae8aCAA7F7de1315D5AD174BE39Ec987;
    address public constant TOKEN_wanS = 0xfA85Fe5A8F5560e9039C04f2b0a90dE1415aBD70;
    //address public constant TOKEN_fBOMB = 0xEdF8b632b537d5993Adb5e2E15882CD791c284cB;
    //address public constant TOKEN_EGGS = 0xf26Ff70573ddc8a90Bd7865AF8d7d70B8Ff019bC;
    address public constant TOKEN_frxUSD = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
    address public constant TOKEN_sfrxUSD = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
    address public constant TOKEN_x33 = 0x3333111A391cC08fa51353E9195526A70b333333;
    address public constant TOKEN_DIAMONDS = 0xdBde38013d44aE23baDC4cd8081271B8028eCaF4;
    address public constant TOKEN_aUSDC = 0x578Ee1ca3a8E1b54554Da1Bf7C583506C4CD11c6;
    address public constant TOKEN_PT_aUSDC_14AUG2025 = 0x930441Aa7Ab17654dF5663781CA0C02CC17e6643;
    address public constant TOKEN_PT_stS_29MAY2025 = 0x420df605D062F8611EFb3F203BF258159b8FfFdE;
    address public constant TOKEN_PT_wstkscUSD_29MAY2025 = 0xBe27993204Ec64238F71A527B4c4D5F4949034C3;
    address public constant TOKEN_PT_wstkscETH_29MAY2025 = 0xa2161E75EDf50d70544e6588788A5732A3105c00;
    address public constant TOKEN_PT_wOS_29MAY2025 = 0x46eb02b9F47634c4fab3110CC7ADc1C6311DfAC1;

    // AMMs
    address public constant POOL_BEETS_wS_stS = 0x374641076B68371e69D03C417DAc3E5F236c32FA;
    address public constant POOL_BEETS_BEETS_stS = 0x10ac2F9DaE6539E77e372aDB14B1BF8fBD16b3e8;
    address public constant POOL_BEETS_wS_USDC = 0xE93a5fc4Ba77179F6843b30cff33a97d89FF441C;
    address public constant POOL_BEETS_USDC_scUSD = 0xCd4D2b142235D5650fFA6A38787eD0b7d7A51c0C;
    address public constant POOL_BEETS_scUSD_stS = 0x25ca5451CD5a50AB1d324B5E64F32C0799661891;
    address public constant POOL_BEETS_USDC_stS = 0x713FB5036dC70012588d77a5B066f1Dd05c712d7;
    address public constant POOL_BEETS_V3_SILO_VAULT_25_wS_anS = 0x944D4AE892dE4BFd38742Cc8295d6D5164c5593C;
    address public constant POOL_SUSHI_wS_USDC = 0xE72b6DD415cDACeAC76616Df2C9278B33079E0D3;
    address public constant POOL_EQUALIZER_USDC_WETH = 0xbCbC5777537c0D0462fb82BA48Eeb6cb361E853f;
    address public constant POOL_EQUALIZER_wS_stS = 0xB75C9073ea00AbDa9ff420b5Ae46fEe248993380;
    address public constant POOL_EQUALIZER_wS_USDC = 0xdc85F86d5E3189e0d4a776e6Ae3B3911eC7B0133;
    address public constant POOL_EQUALIZER_wS_EQUAL = 0x139f8eCC5fC8Ef11226a83911FEBecC08476cfB1;
    address public constant POOL_EQUALIZER_USDC_scUSD = 0xB78CdF29F7E563ea447feBB5b48DDe9bC3278Ba4;
    address public constant POOL_EQUALIZER_wS_GOGLZ = 0x832e2bb9579f6fF038d3E704Fa1BB5B6B18a6521;
    //address public constant POOL_EQUALIZER_wS_NAVI = 0x25f21F51b3D6322E165b80C9fdE31104CB82df04;
    //address public constant POOL_EQUALIZER_wS_ECO = 0x93B3Db87d07e4925274174CbD650EFdcd8885Cc6;
    //address public constant POOL_EQUALIZER_ECO_EQUAL = 0x88615ba8aa369f2f27E4a6e8f66fdE85F1Ce15ec;
    //address public constant POOL_EQUALIZER_wS_INDI = 0x913B1c9924F563692b3A306C90C9fDe9f825Ca27;
    //address public constant POOL_EQUALIZER_wS_BRUSH = 0x38cFA6cB37d074B6E954C52d10a4cf0e4268607b;
    //address public constant POOL_EQUALIZER_WETH_Missor = 0x0d84Cb89787047aF1B671F12f589898F7fC8cDce;
    //address public constant POOL_EQUALIZER_wS_DONKS = 0xB51DCB7D0adBF69A817bA1BBB62b637A3123ba54;
    //address public constant POOL_EQUALIZER_wS_TAILS = 0x84f66B604604bA80d67742106c5D9c98A6bE4EB3;
    //address public constant POOL_EQUALIZER_wS_THC = 0x3E6daa42268a5097De68ab39e48B860B9B55f589;
    //address public constant POOL_EQUALIZER_wS_FS = 0x110026eefCe21c356598Ded1B637B01aa67434A1;
    //address public constant POOL_EQUALIZER_wS_sDOG = 0x7Fd1213b759aA864fcfaFDb3cc8c8105F1eec01c;
    address public constant POOL_SWAPX_CL_wS_SACRA = 0x875819746112630cEe95aA78E4327cd4837Da70D;
    address public constant POOL_SWAPX_CL_wS_SWPx = 0xbeca246A76942502f61bFe88F60bbc87DaFefe80;
    address public constant POOL_SWAPX_CL_USDC_SWPx = 0x467865E7Ce29E7ED8f362D51Fd7141117B234b44;
    address public constant POOL_SWAPX_CL_wS_stS = 0xD760791B29e7894FB827A94Ca433254bb5aFB653;
    address public constant POOL_SWAPX_CL_wS_USDC = 0x5C4B7d607aAF7B5CDE9F09b5F03Cf3b5c923AEEa;
    address public constant POOL_SWAPX_CL_USDC_WETH = 0xeC4Ee7d6988Ab06F7a8DAaf8C5FDfFdE6321Be68;
    address public constant POOL_SWAPX_CL_USDC_scUSD = 0xDd35c88B1754879EF86BBF3A24F81fCCA5Eb6B5D;
    address public constant POOL_SWAPX_CL_wS_scETH = 0xFC64BD7c84F7Dc1387D6E752679a533F22f6F1DB;
    address public constant POOL_SWAPX_CL_USDC_stS = 0x5DDbeF774488cc68266d5F15bFB08eaA7cd513F9;
    address public constant POOL_SWAPX_CL_atETH_scETH = 0xCe39D66872015a8d1B2070725E6BFc687A418bD0;
    address public constant POOL_SWAPX_CL_wS_SACRA_GEM_1 = 0x5e1Cb0d1196FF3451204fC40415A81a4d24Ec7eD;
    address public constant POOL_SWAPX_CL_wS_OS = 0xa76Beaf111BaD5dD866fa4835D66b9aA2Eb1FdEc;
    address public constant POOL_SWAPX_CL_scETH_WETH = 0xDa2fDdeb3D654E1F32E2664d8d95C9329e34E5c8;
    address public constant POOL_SWAPX_CL_wstkscUSD_scUSD = 0xEd08f5caD599E7F523d6B3FD598005B43aA003bb;
    address public constant POOL_SWAPX_CL_sfrxUSD_frxUSD = 0x7d709a567BA2fdBbB92E94E5fE74b9cbbc590835;
    address public constant POOL_SWAPX_CL_frxUSD_scUSD = 0x63a66Dd60b0F2812249802477adA8a890A030Eca;
    address public constant POOL_SWAPX_USDC_scUSD = 0xBb8aE5b889243561ac9261F22F592B72250AFd1F;
    address public constant POOL_SWAPX_wS_GOGLZ = 0xE6aA7CA47DDb6203e71d4D1497959Da51F87AA98;
    address public constant POOL_SWAPX_AUR_auUSDC = 0xf9b7a6Da525f6f05910f99b298bb792025128C6f;
    address public constant POOL_SWAPX_USDC_AUR = 0xE87080413295b7a3B9c63F82a3337a882750F974;
    address public constant POOL_SWAPX_wS_TYSG = 0x24f5cd888057A721F1ACD7CBA1Afa7A8384c3e12;
    address public constant POOL_SWAPX_wS_ECO = 0x03281b6F11D943157A973cDB6B39B747501BDBBa;
    address public constant POOL_SWAPX_wS_WOOF = 0x61974F520630B11E2aF36e2C92Cf0C0920Dd487A;
    address public constant POOL_SWAPX_wS_sDOG = 0xbF23E7fC58b7094D17fe52ef8bdE979aa06b8916;
    address public constant POOL_SWAPX_wS_MOON = 0x8218825E5964e17D872adCEfA4C72D73c0D44021;
    address public constant POOL_SWAPX_wS_FS = 0xB545EA688f4d14d37B91df6370d75C922f4e9232;
    address public constant POOL_SWAPX_USDC_STBL = 0x4D864C2CFb4c11A2CeE4C2d5cBfa318c7B7e14F8;
    address public constant POOL_SWAPX_fBOMB_EGGS = 0xEBEeC250676833b96505D8e2967215E91C74e477;
    address public constant POOL_UNISWAPV3_wS_USDC_3000 = 0xEcb04e075503Bd678241f00155AbCB532c0a15Eb;
    address public constant POOL_UNISWAPV3_wS_WETH_3000 = 0x21043D7Ad92d9e7bC45C055AF29771E37307B111;
    address public constant POOL_UNISWAPV3_USDC_WETH_500 = 0xCfD41dF89D060b72eBDd50d65f9021e4457C477e;
    address public constant POOL_UNISWAPV3_USDC_scUSD_100 = 0xDFCDAD314b0b96AB8890391e3F0540278E3B80F7;
    address public constant POOL_SHADOW_wS_SHADOW = 0xF19748a0E269c6965a84f8C98ca8C47A064D4dd0;
    address public constant POOL_SHADOW_CL_wS_WETH = 0xB6d9B069F6B96A507243d501d1a23b3fCCFC85d3;
    address public constant POOL_SHADOW_CL_wS_BRUSH_5000 = 0xB8bda81EcCb1a21198899ac8F1f2F73C82bD7695;
    address public constant POOL_SHADOW_CL_wS_USDC = 0x324963c267C354c7660Ce8CA3F5f167E05649970;
    address public constant POOL_SHADOW_CL_wS_GOGLZ_5000 = 0x1f4eFC47e5A5Ab6539d95A76e2dDE6d74462acEa;
    address public constant POOL_SHADOW_CL_sGEM1_scUSD_20000 = 0x1ADcAaF67307453a3995a7FFf78b8CBEc1eFd00F;
    address public constant POOL_SHADOW_CL_SACRA_scUSD_20000 = 0x350598C4C17dDC02049e34Bfdf4555422d2d670E;
    address public constant POOL_SHADOW_CL_USDC_scUSD_100 = 0x2C13383855377faf5A562F1AeF47E4be7A0f12Ac;
    address public constant POOL_SHADOW_CL_scETH_WETH_100 = 0xC291CA0a0a0e793dC6A0442a34E1607Ce1905389;
    address public constant POOL_SHADOW_CL_stkscUSD_scUSD_3000 = 0x666805eBf99E2E797D09e07b7e255ad0e67B086B;
    address public constant POOL_SHADOW_CL_scETH_stkscETH_250 = 0x286Cc998298d9D0242C9ad30cdB587E0b2f59f22;
    address public constant POOL_SHADOW_CL_USDC_EGGS = 0x66A8289bdD968D1157eB1a608f60a87759632cd6;
    address public constant POOL_SHADOW_CL_x33_SHADOW = 0xBB528A050a3b3b998a9651F893Fa46162967A04C;
    // address public constant POOL_EQUALIZER_wS_USDC = 0xb1BC4B830FCbA2184B92e15b9133c41160518038;
    // address public constant POOL_EQUALIZER_WETH_wS = 0x81ACF1C9BCC452b634D6DA33DB3f8D96e2CD1c73;
    // address public constant POOL_EQUALIZER_USDC_WETH = 0xfe809A1D337Bdfc98B77A1067e3819f66d8AD23F;
    address public constant POOL_EQUALIZER_wS_DIAMONDS = 0x2db92f3cf994520aC480d6692e956Ab7d8A24dcE;
    address public constant POOL_PENDLE_PT_aUSDC_14AUG2025 = 0x3F5EA53d1160177445B1898afbB16da111182418;
    address public constant POOL_PENDLE_PT_stS_29MAY2025 = 0x3aeF1d372d0a7a7E482F465Bc14A42D78f920392;
    address public constant POOL_PENDLE_PT_wstkscUSD_29MAY2025 = 0x6e4e95FaB7db1f0524b4b0a05F0b9c96380b7Dfa;
    address public constant POOL_PENDLE_PT_wstkscETH_29MAY2025 = 0xd14117baf6EC5D12BE68CD06e763A4B82C9B6d1D;
    address public constant POOL_PENDLE_PT_wOS_29MAY2025 = 0x4E82347Bc41CFD5d62cEF483C7f0a739a8158963;

    // ALMs
    address public constant ALM_ICHI_SWAPX_SACRA_wS = 0x13939Ac0f09dADe88F8b1d86C26daD934d973081;
    address public constant ALM_ICHI_SWAPX_wS_SACRA = 0x32D1E0647fD2AE199bB0599Fe62A95e522C11bf3;
    address public constant ALM_ICHI_SWAPX_stS_wS = 0xa68D5DbAe00960De66DdEaD4d53faea39f21983b;
    address public constant ALM_ICHI_SWAPX_wS_stS = 0xfD10ac67449C16F368a4BB49f544E0A865A77614;
    address public constant ALM_ICHI_SWAPX_SACRA_GEM_1_wS = 0x515626bC050c6fc1B000be7F4FDa71422CaD3e09;
    address public constant ALM_ICHI_SWAPX_wS_SACRA_GEM_1 = 0xB97908b0Bec1Fac52281d108a56B055B633FDf67;
    address public constant ALM_ICHI_SWAPX_wS_USDC = 0x5F62d612c69fF7BE3FBd9a0cD530D57bCbC7b642;
    address public constant ALM_ICHI_SWAPX_USDC_wS = 0xc263e421Df94bdf57B27120A9B7B8534A6901D95;
    address public constant ALM_ICHI_SWAPX_scUSD_USDC = 0x776C31466F19D4e2c71bCE16c0549a8Bc0E37e17;
    address public constant ALM_ICHI_SWAPX_USDC_scUSD = 0xF77CeeD15596BfC127D17bA45dEA9767BC349Be0;
    address public constant ALM_ICHI_SWAPX_atETH_scETH = 0x20737388dbc9F7E56f4Cc69D41DA62C96B355DB0;
    address public constant ALM_ICHI_SWAPX_scETH_atETH = 0xD7A7f09a31Dcf76689Ff7046264a52Fc0D8feb72;
    address public constant ALM_ICHI_SWAPX_wS_SWPx = 0xfDEc32751Faade573B285C8CC606677beE656A4C;
    address public constant ALM_ICHI_SWAPX_USDC_SWPx = 0x5De651be21beeDe8ABE808D1425b278ac4a3604B;
    address public constant ALM_ICHI_SWAPX_stS_USDC = 0x79cFAb400429c81f1656DF4D65363cb5FD340509;
    address public constant ALM_ICHI_SWAPX_USDC_stS = 0x86D13feF5e2F4F96c2c592aE7Fd096EB5AC424AC;
    address public constant ALM_ICHI_SWAPX_wS_OS = 0x36dA3b8156C421118d1cc27956454C49eeC5fC1B;
    address public constant ALM_ICHI_SWAPX_OS_wS = 0xc4A71981DC8ee8ee704b6217DaebAd6ECe185aeb;
    address public constant ALM_ICHI_SWAPX_WETH_scETH = 0x0f385EEa80cB6909A1dbA5CDc763e97F8589f47D;
    address public constant ALM_ICHI_SWAPX_scETH_WETH = 0x6E8A8037533aA74FfFEb92390E443294d034d769;
    address public constant ALM_ICHI_SWAPX_wstscUSD_scUSD = 0x3B4645fb65fd4BaFf4ac1425e876Ab6Fc6D8eD0f;
    address public constant ALM_ICHI_SWAPX_scUSD_wstscUSD = 0xb9A95F011b74dD3ECE3e13bC5c1ebb24518Bc244;
    address public constant ALM_ICHI_SWAPX_frxUSD_sfrxUSD = 0x65B970bcB133650D02B4D96901f2F5c855D1F2f7;
    address public constant ALM_ICHI_SWAPX_sfrxUSD_frxUSD = 0xe33108E60906C3122C76e8F3e68a9c272F8DcD1B;
    address public constant ALM_ICHI_SWAPX_frxUSD_scUSD = 0x1B282d69a54a983714bB6Bea8cAAcB29D4cb45B5;
    address public constant ALM_GAMMA_UNISWAPV3_wS_USDC_3000 = 0x318E378b6EC1590315e5e8160A2eF28308AE7Cfc;
    address public constant ALM_GAMMA_UNISWAPV3_wS_WETH_3000 = 0x2Ea8A8ba347011FEF2a7E0A276354B90B4927cBC;
    address public constant ALM_GAMMA_UNISWAPV3_USDC_WETH_500 = 0x2fA5E2E2a49de9375047225b7cea4997e8203AA4;
    address public constant ALM_GAMMA_UNISWAPV3_USDC_scUSD_100 = 0xBd3332466d13588B1BFe8673B58190645bFE26bE;
    address public constant ALM_GAMMA_EQUALIZER_wS_USDC = 0xC225FA4e6fFE9cc248518004946B48B76b9E4dFE;
    address public constant ALM_GAMMA_EQUALIZER_WETH_wS = 0x2Fcc0d25c4CD2084e402c16DB68FBE206A36A46F;
    address public constant ALM_GAMMA_EQUALIZER_USDC_WETH = 0xBc7D3b581cd4c4f34fC2942491Fa803761C574e2;

    // Beets
    address public constant BEETS_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant BEETS_BALANCER_HELPERS = 0x8E9aa87E45e92bad84D5F8DD1bff34Fb92637dE9;
    address public constant BEETS_GAUGE_wS_stS = 0x8476F3A8DA52092e7835167AFe27835dC171C133;
    address public constant BEETS_GAUGE_USDC_scUSD = 0x33B29bcf17e866A35941e07CbAd54f1807B337f5;
    address public constant BEETS_GAUGE_scUSD_stS = 0xa472438718Fe7785107fCbE584d39183a6420D36;
    address public constant BEETS_GAUGE_USDC_stS = 0xb3Bf2c247A599DFcEf06791b1668Fe9456677923;
    address public constant BEETS_V3_ROUTER = 0x6077b9801B5627a65A5eeE70697C793751D1a71c;

    // Equalizer
    address public constant EQUALIZER_ROUTER_03 = 0xcC6169aA1E879d3a4227536671F85afdb2d23fAD;
    address public constant EQUALIZER_GAUGE_USDC_WETH = 0xf8F2462A8Fa08Df933C0d6bbaf34108Fd7af526E;
    address public constant EQUALIZER_GAUGE_wS_stS = 0x0DA2e6e170990dCDd046880fADC17ADF759B869e;
    address public constant EQUALIZER_GAUGE_wS_USDC = 0x9b55Fbd8Cd27B81aCc6adfd42D441858FeDe4326;
    address public constant EQUALIZER_GAUGE_USDC_scUSD = 0x8c030811a8C5E1890dAd1F5E581D28ac8740c532;
    address public constant EQUALIZER_GAUGE_wS_GOGLZ = 0x9E06a65E545b4Bd762158f6Bc34656DEe9693a4D;
    address public constant EQUALIZER_GAUGE_wS_NAVI = 0xe33588B5507E7c1D8Dd8367Cd8C7CE406DAeb019;
    address public constant EQUALIZER_GAUGE_wS_ECO = 0xE9DB22DC69129FD131CB744e8E638A8FA084e66e;
    address public constant EQUALIZER_GAUGE_ECO_EQUAL = 0xDAC4c0fcd65C71070E1b14f1deA8Ce48E746B2fD;
    //address public constant EQUALIZER_GAUGE_wS_INDI = 0x15c2B42F6001758edDd9Cd13f327cdc812E5795D;
    //address public constant EQUALIZER_GAUGE_wS_BRUSH = 0xA4Df0a210a5E242BE68E8a2b780ecc854ADD3583;
    //address public constant EQUALIZER_GAUGE_WETH_Missor = 0x199aF40E819CED6e7a56B2C06296e292d10C4727;
    //address public constant EQUALIZER_GAUGE_wS_DONKS = 0xD3b67f0DE1Bf85aCCD538BB1CE214a635605A0c2;
    //address public constant EQUALIZER_GAUGE_wS_TAILS = 0x8C0B131c178505EA8b7a06fd6db0422392Cf8AB3;
    //address public constant EQUALIZER_GAUGE_wS_THC = 0x4C09EcEc77Bd56ea28CE85DA6a2A4E39de997e35;
    //address public constant EQUALIZER_GAUGE_wS_FS = 0x152A791a2B3E415d482F4Bc608A328f3ebE37A5D;
    //address public constant EQUALIZER_GAUGE_wS_sDOG = 0xa9366d013bE7E7151f251cb47133Ed14aa3cFCdC;
    address public constant EQUALIZER_GAUGE_GAMMA_wS_USDC = 0xa4B6867eEad7B373642f86253c5367bA84E12f76;
    address public constant EQUALIZER_GAUGE_GAMMA_WETH_wS = 0x28b96E430ecC193c07318325f6a8af17c44333D8;
    address public constant EQUALIZER_GAUGE_GAMMA_USDC_WETH = 0xdC44bf3bF760e88DdaC7667C2386A0D5B6668b47;

    // SwapX
    address public constant SWAPX_ROUTER_V2 = 0xF5F7231073b3B41c04BA655e1a7438b1a7b29c27;
    address public constant SWAPX_GAUGE_ICHI_SACRA_wS = 0x413610103721Df45C7E8333D5E34Bb39975762f3;
    address public constant SWAPX_GAUGE_ICHI_wS_SACRA = 0x2a2EF9F07c998140eA3709826e28157971F85d30;
    address public constant SWAPX_GAUGE_ICHI_stS_wS = 0x2f9e2852de03c42c13d3dCdD2C57c0b3cF0382c1;
    address public constant SWAPX_GAUGE_ICHI_wS_stS = 0xC693c6fc1d2b44DfB5C5aa05Ca2b02A91DB97528;
    address public constant SWAPX_GAUGE_ICHI_SACRA_GEM_1_wS = 0xF46AeD788930E6Dd7f5881b9aeDf692dD6552d58;
    address public constant SWAPX_GAUGE_ICHI_wS_SACRA_GEM_1 = 0xCe9f06c3d88fe91F16A8fb5489860677a2358d6F;
    address public constant SWAPX_GAUGE_ICHI_wS_USDC = 0xdcE26623440B34a93e748e131577049a8d84DdEd;
    address public constant SWAPX_GAUGE_ICHI_USDC_wS = 0x29d10053BE597E0eBe6BD0434c4f4b750F0f3b69;
    address public constant SWAPX_GAUGE_ICHI_scUSD_USDC = 0x4604782BcD6F749B271Fc9d14BFd583be6e5a6cf;
    address public constant SWAPX_GAUGE_ICHI_USDC_scUSD = 0x640429B0633851F487639BcDd8Ed523DDf1Bbff8;
    address public constant SWAPX_GAUGE_ICHI_atETH_scETH = 0xBBb10f33DCDd50BD4317459A4B051FC319B29585;
    address public constant SWAPX_GAUGE_ICHI_scETH_atETH = 0x9ce7Cf104E8C11b77da6d0a6cdA542B8F53e84d4;
    address public constant SWAPX_GAUGE_ICHI_wS_SWPx = 0x701A6eB7879B9da39662950DCCAfC5C81e0b60B0;
    address public constant SWAPX_GAUGE_ICHI_USDC_SWPx = 0xbEE97F13cc7a681436eE8dE71926B8faD6F10B0f;
    address public constant SWAPX_GAUGE_ICHI_stS_USDC = 0x7791ECC02Ce43f877DF2D39d8073572Ded64617e;
    address public constant SWAPX_GAUGE_ICHI_USDC_stS = 0x6bd21754fB317ABA1F112c3d01904669e7D34803;
    address public constant SWAPX_GAUGE_ICHI_wS_OS = 0x7FCd694E0c24bF12DCbD471DF38601059F2b8093;
    address public constant SWAPX_GAUGE_ICHI_OS_wS = 0x3a4A0040475575638beB4051d8950ea21686ce27;
    address public constant SWAPX_GAUGE_ICHI_WETH_scETH = 0x882A10B15F2cdC893a5109C4b4B562674aBb18b0;
    address public constant SWAPX_GAUGE_ICHI_scETH_WETH = 0x0ceEb9B74f2b94CAC261E92e484f368efF8ab681;
    address public constant SWAPX_GAUGE_ICHI_wstkscUSD_scUSD = 0xA57898F2076277670394807F0456413BF595b25D;
    address public constant SWAPX_GAUGE_ICHI_scUSD_wstkscUSD = 0xECDd1Df06b5b0C598348678F83B74ADDcbD45835;
    address public constant SWAPX_GAUGE_ICHI_frxUSD_sfrxUSD = 0xCEA30c3ba4a6d987855dAA86534dCb49A7dd2894;
    address public constant SWAPX_GAUGE_ICHI_sfrxUSD_frxUSD = 0xe59E52f99A0f8443Dc420Bb532856FAFd7Dd32d8;
    address public constant SWAPX_GAUGE_ICHI_frxUSD_scUSD = 0xB02506CAe9FC5BB61E21c11d7E0614cd56f4b131;
    address public constant SWAPX_GAUGE_USDC_scUSD = 0x2036D05eCA7fe86cD224927883490A255EF552BA;
    address public constant SWAPX_GAUGE_wS_GOGLZ = 0x5D671DE88045626e50Be05C1D438b2B9908cFa97;
    address public constant SWAPX_GAUGE_AUR_auUSDC = 0xca958280Ba083545C36A64e1AED18075317E3529;
    address public constant SWAPX_GAUGE_wS_TYSG = 0xB7B6fC72CbC8E8FA67737f83e945Db2795a66Ef7;
    address public constant SWAPX_GAUGE_wS_ECO = 0xa49c12D9542eB16494CF1980556f1bE437aCb212;
    address public constant SWAPX_GAUGE_wS_WOOF = 0xc1742f8898d343b4909D29E7F1061EB2aC92e999;
    address public constant SWAPX_GAUGE_wS_sDOG = 0x48C3fF29dAEaC7aFa7785A3977Aab247e6761576;
    address public constant SWAPX_GAUGE_wS_MOON = 0x9ad399ecC102212b4677B0Dbbc82c07ae1c74Cc5;
    address public constant SWAPX_GAUGE_wS_FS = 0x1cb9f6179A6A24f1A3756b6f6A14E5C5Fd3c0347;
    address public constant SWAPX_GAUGE_USDC_STBL = 0x17D11842cCECd5166BFC6c6D7aAa440476A9F883;
    address public constant SWAPX_GAUGE_fBOMB_EGGS = 0x2E5228cFEcFEFA439f92Aa4823E5593de5bFcB7D;

    // Silo
    address public constant SILO_LENS = 0xE05966aee69CeCD677a30f469812Ced650cE3b5E;
    address public constant SILO_GAUGE_wS_008 = 0x0dd368Cd6D8869F2b21BA3Cb4fd7bA107a2e3752;
    address public constant SILO_GAUGE_wS_020 = 0x2D3d269334485d2D876df7363e1A50b13220a7D8;
    address public constant SILO_VAULT_3_stS = 0x396922EF30Cf012973343f7174db850c7D265278;
    address public constant SILO_VAULT_3_wS = 0x47d8490Be37ADC7Af053322d6d779153689E13C1;
    address public constant SILO_VAULT_23_wstkscUSD = 0x4E09FF794D255a123b00efa30162667A8054a845;
    address public constant SILO_VAULT_23_USDC = 0x5954ce6671d97D24B782920ddCdBB4b1E63aB2De;
    address public constant SILO_VAULT_26_wstkscETH = 0xE8e1A980a7fc8D47D337d704FA73FBb81eE55C25;
    address public constant SILO_VAULT_26_wETH = 0x219656F33c58488D09d518BaDF50AA8CdCAcA2Aa;
    address public constant SILO_VAULT_22_wOS = 0x1d7E3726aFEc5088e11438258193A199F9D5Ba93;
    address public constant SILO_VAULT_22_wS = 0x112380065A2cb73A5A429d9Ba7368cc5e8434595;
    address public constant SILO_VAULT_25_wanS = 0x21580de05C4F3d6D6a5345b03a898C33B872Ab51;
    address public constant SILO_VAULT_25_wS = 0x016C306e103FbF48EC24810D078C65aD13c5f11B;
    address public constant SILO_VAULT_46_PT_aUSDC_14AUG = 0x558d6D6D53270ae8ba622daF123983D9F3c21792;
    address public constant SILO_VAULT_46_scUSD = 0xe6605932e4a686534D19005BB9dB0FBA1F101272;
    address public constant SILO_VAULT_40_PT_stS_29MAY = 0x058766008d237faF3B05eeEebABc73C64d677bAE;
    address public constant SILO_VAULT_40_wS = 0x24F7692af5231d559219d07c65276Ad8C8ceE9A3;
    address public constant SILO_VAULT_37_PT_wstkscUSD_29MAY = 0x854475b78880767e246163031b5bE44f14426c26;
    address public constant SILO_VAULT_37_frxUSD = 0xdA14A41DbdA731F03A94cb722191639DD22b35b2;

    // Gamma
    address public constant GAMMA_UNISWAPV3_UNIPROXY = 0xcD5A60eb030300661cAf97244aE98e1D5A70f2c8;
    address public constant GAMMA_EQUALIZER_UNIPROXY = 0x38f61169D8bcc08cE303401A13332259F557B35f;

    // Shadow
    address public constant SHADOW_NFT = 0x12E66C8F215DdD5d48d150c8f46aD0c6fB0F4406;
    address public constant SHADOW_ROUTER = 0x1D368773735ee1E678950B7A97bcA2CafB330CDc;
    address public constant SHADOW_GAUGE_CL_wS_WETH = 0xF5C7598C953E49755576CDA6b2B2A9dAaf89a837;
    address public constant SHADOW_GAUGE_CL_wS_USDC = 0xe879d0E44e6873cf4ab71686055a4f6817685f02;
    address public constant SHADOW_GAUGE_CL_SACRA_scUSD_20000 = 0xbf2EdE70EB05E3A15d43A8D33BDf3A4156e98932;

    // Oracles
    address public constant ORACLE_API3_USDC_USD = 0xD3C586Eec1C6C3eC41D276a23944dea080eDCf7f;
    address public constant ORACLE_API3_wS_USD = 0x726D2E87d73567ecA1b75C063Bd09c1493655918;
    address public constant ORACLE_PYTH_stS_USD = 0xfdbA54F2F4242Df3DbD34C72C8983E40d7C19CBE;
    address public constant ORACLE_PYTH_scUSD_USD = 0xC55C8c98Bd7359C587Cd9a5D999ab4720608F18C;

    //noinspection NoReturn
    function platformDeployParams() internal pure returns (IPlatformDeployer.DeployPlatformParams memory p) {
        p.multisig = MULTISIG;
        p.version = "25.01.0-alpha";
        p.buildingPermitToken = address(0);
        p.buildingPayPerVaultToken = TOKEN_wS;
        p.networkName = "Sonic";
        p.networkExtra = CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0xfec160), bytes3(0x000000)));
        p.targetExchangeAsset = TOKEN_wS;
        p.gelatoAutomate = address(0);
        p.gelatoMinBalance = 1e16;
        p.gelatoDepositAmount = 2e16;
        p.fee = 30_000;
        p.feeShareVaultManager = 10_000;
        p.feeShareStrategyLogic = 40_000;
    }

    function deployAndSetupInfrastructure(address platform, bool showLog) internal {
        IFactory factory = IFactory(IPlatform(platform).factory());

        //region ----- Deployed Platform -----
        if (showLog) {
            console.log("Deployed Stability platform", IPlatform(platform).platformVersion());
            console.log("Platform address: ", platform);
        }
        //endregion

        //region ----- Deploy and setup vault types -----
        _addVaultType(factory, VaultTypeLib.COMPOUNDING, address(new CVault()), 10e6);
        //endregion

        //region ----- Deploy and setup oracle adapters -----
        IPriceReader priceReader = PriceReader(IPlatform(platform).priceReader());
        // Api3
        {
            Proxy proxy = new Proxy();
            proxy.initProxy(address(new Api3Adapter()));
            Api3Adapter adapter = Api3Adapter(address(proxy));
            adapter.initialize(platform);
            address[] memory assets = new address[](1);
            assets[0] = TOKEN_USDC;
            address[] memory priceFeeds = new address[](1);
            priceFeeds[0] = ORACLE_API3_USDC_USD;
            adapter.addPriceFeeds(assets, priceFeeds);
            priceReader.addAdapter(address(adapter));
            LogDeployLib.logDeployAndSetupOracleAdapter("Api3", address(adapter), showLog);
        }
        //endregion

        //region ----- Deploy AMM adapters -----
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.UNISWAPV3);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE);
        IBalancerAdapter(
            IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE))).proxy
        ).setupHelpers(BEETS_BALANCER_HELPERS);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.BALANCER_WEIGHTED);
        IBalancerAdapter(IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.BALANCER_WEIGHTED))).proxy)
            .setupHelpers(BEETS_BALANCER_HELPERS);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.SOLIDLY);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.ALGEBRA_V4);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.ERC_4626);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.BALANCER_V3_STABLE);
        IBalancerAdapter(IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.BALANCER_V3_STABLE))).proxy)
            .setupHelpers(BEETS_V3_ROUTER);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.PENDLE);
        LogDeployLib.logDeployAmmAdapters(platform, showLog);
        //endregion

        //region ----- Setup Swapper -----
        {
            (ISwapper.AddPoolData[] memory bcPools, ISwapper.AddPoolData[] memory pools) = routes();
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            swapper.addBlueChipsPools(bcPools, false);
            swapper.addPools(pools, false);
            address[] memory tokenIn = new address[](6);
            tokenIn[0] = TOKEN_wS;
            tokenIn[1] = TOKEN_stS;
            tokenIn[2] = TOKEN_BEETS;
            tokenIn[3] = TOKEN_EQUAL;
            tokenIn[4] = TOKEN_USDC;
            tokenIn[5] = TOKEN_DIAMONDS;
            uint[] memory thresholdAmount = new uint[](6);
            thresholdAmount[0] = 1e12;
            thresholdAmount[1] = 1e16;
            thresholdAmount[2] = 1e10;
            thresholdAmount[3] = 1e12;
            thresholdAmount[4] = 1e4;
            thresholdAmount[5] = 1e15;
            swapper.setThresholds(tokenIn, thresholdAmount);
            LogDeployLib.logSetupSwapper(platform, showLog);
        }
        //endregion

        //region ----- Add farms -----
        factory.addFarms(farms());
        LogDeployLib.logAddedFarms(address(factory), showLog);
        //endregion

        //region ----- Add strategy available init params -----
        IFactory.StrategyAvailableInitParams memory p;
        p.initAddresses = new address[](4);
        p.initAddresses[0] = SILO_VAULT_3_stS;
        p.initAddresses[1] = SILO_VAULT_3_wS;
        p.initAddresses[2] = BEETS_VAULT;
        p.initAddresses[3] = SILO_LENS;
        p.initNums = new uint[](1);
        p.initNums[0] = 1;
        p.initTicks = new int24[](0);
        factory.setStrategyAvailableInitParams(StrategyIdLib.SILO_LEVERAGE, p);
        p.initAddresses = new address[](4);
        p.initAddresses[0] = SILO_VAULT_23_wstkscUSD;
        p.initAddresses[1] = SILO_VAULT_23_USDC;
        p.initAddresses[2] = BEETS_VAULT;
        p.initAddresses[3] = SILO_LENS;
        p.initNums = new uint[](1);
        p.initNums[0] = 87_00;
        p.initTicks = new int24[](0);
        factory.setStrategyAvailableInitParams(StrategyIdLib.SILO_ADVANCED_LEVERAGE, p);
        //endregion -- Add strategy available init params -----

        //region ----- Deploy strategy logics -----
        _addStrategyLogic(factory, StrategyIdLib.BEETS_STABLE_FARM, address(new BeetsStableFarm()), true);
        _addStrategyLogic(factory, StrategyIdLib.BEETS_WEIGHTED_FARM, address(new BeetsWeightedFarm()), true);
        _addStrategyLogic(factory, StrategyIdLib.EQUALIZER_FARM, address(new EqualizerFarmStrategy()), true);
        _addStrategyLogic(factory, StrategyIdLib.ICHI_SWAPX_FARM, address(new IchiSwapXFarmStrategy()), true);
        _addStrategyLogic(factory, StrategyIdLib.SWAPX_FARM, address(new SwapXFarmStrategy()), true);
        _addStrategyLogic(
            factory, StrategyIdLib.GAMMA_UNISWAPV3_MERKL_FARM, address(new GammaUniswapV3MerklFarmStrategy()), true
        );
        _addStrategyLogic(factory, StrategyIdLib.SILO_FARM, address(new SiloFarmStrategy()), true);
        _addStrategyLogic(factory, StrategyIdLib.ALM_SHADOW_FARM, address(new ALMShadowFarmStrategy()), true);
        _addStrategyLogic(factory, StrategyIdLib.SILO_LEVERAGE, address(new SiloLeverageStrategy()), false);
        _addStrategyLogic(
            factory, StrategyIdLib.SILO_ADVANCED_LEVERAGE, address(new SiloAdvancedLeverageStrategy()), false
        );
        _addStrategyLogic(factory, StrategyIdLib.GAMMA_EQUALIZER_FARM, address(new GammaEqualizerFarmStrategy()), true);
        LogDeployLib.logDeployStrategies(platform, showLog);
        //endregion

        //region ----- Add DeX aggregators -----
        address[] memory dexAggRouter = new address[](1);
        dexAggRouter[0] = IPlatform(platform).swapper();
        IPlatform(platform).addDexAggregators(dexAggRouter);
        //endregion
    }

    function routes()
        public
        pure
        returns (ISwapper.AddPoolData[] memory bcPools, ISwapper.AddPoolData[] memory pools)
    {
        //region ----- BC pools ----
        bcPools = new ISwapper.AddPoolData[](2);
        bcPools[0] = _makePoolData(POOL_SWAPX_CL_wS_stS, AmmAdapterIdLib.ALGEBRA_V4, TOKEN_stS, TOKEN_wS);
        bcPools[1] = _makePoolData(POOL_SUSHI_wS_USDC, AmmAdapterIdLib.UNISWAPV3, TOKEN_USDC, TOKEN_wS);
        //endregion ----- BC pools ----

        //region ----- Pools ----
        pools = new ISwapper.AddPoolData[](32);
        uint i;
        pools[i++] = _makePoolData(POOL_SWAPX_CL_wS_stS, AmmAdapterIdLib.ALGEBRA_V4, TOKEN_wS, TOKEN_stS);
        pools[i++] = _makePoolData(POOL_SWAPX_CL_wS_stS, AmmAdapterIdLib.ALGEBRA_V4, TOKEN_stS, TOKEN_wS);
        pools[i++] = _makePoolData(POOL_BEETS_BEETS_stS, AmmAdapterIdLib.BALANCER_WEIGHTED, TOKEN_BEETS, TOKEN_stS);
        pools[i++] = _makePoolData(POOL_SUSHI_wS_USDC, AmmAdapterIdLib.UNISWAPV3, TOKEN_USDC, TOKEN_wS);
        pools[i++] = _makePoolData(POOL_SHADOW_CL_USDC_scUSD_100, AmmAdapterIdLib.UNISWAPV3, TOKEN_scUSD, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_EQUALIZER_wS_EQUAL, AmmAdapterIdLib.SOLIDLY, TOKEN_EQUAL, TOKEN_wS);
        pools[i++] = _makePoolData(POOL_SWAPX_CL_USDC_WETH, AmmAdapterIdLib.ALGEBRA_V4, TOKEN_wETH, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_EQUALIZER_wS_GOGLZ, AmmAdapterIdLib.SOLIDLY, TOKEN_GOGLZ, TOKEN_wS);
        pools[i++] = _makePoolData(POOL_SWAPX_CL_wS_SWPx, AmmAdapterIdLib.ALGEBRA_V4, TOKEN_SWPx, TOKEN_wS);
        pools[i++] = _makePoolData(POOL_SWAPX_CL_wS_SACRA, AmmAdapterIdLib.ALGEBRA_V4, TOKEN_SACRA, TOKEN_wS);
        pools[i++] =
            _makePoolData(POOL_SWAPX_CL_wS_SACRA_GEM_1, AmmAdapterIdLib.ALGEBRA_V4, TOKEN_SACRA_GEM_1, TOKEN_wS);
        pools[i++] = _makePoolData(POOL_SWAPX_USDC_AUR, AmmAdapterIdLib.SOLIDLY, TOKEN_AUR, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_SWAPX_AUR_auUSDC, AmmAdapterIdLib.SOLIDLY, TOKEN_auUSDC, TOKEN_AUR);
        pools[i++] = _makePoolData(POOL_SHADOW_wS_SHADOW, AmmAdapterIdLib.SOLIDLY, TOKEN_SHADOW, TOKEN_wS);
        pools[i++] = _makePoolData(POOL_SHADOW_CL_wS_BRUSH_5000, AmmAdapterIdLib.UNISWAPV3, TOKEN_BRUSH, TOKEN_wS);
        pools[i++] = _makePoolData(POOL_SHADOW_CL_scETH_WETH_100, AmmAdapterIdLib.UNISWAPV3, TOKEN_scETH, TOKEN_wETH);

        pools[i++] =
            _makePoolData(POOL_SWAPX_CL_wstkscUSD_scUSD, AmmAdapterIdLib.ALGEBRA_V4, TOKEN_wstkscUSD, TOKEN_scUSD);
        pools[i++] = _makePoolData(TOKEN_wstkscUSD, AmmAdapterIdLib.ERC_4626, TOKEN_stkscUSD, TOKEN_wstkscUSD);

        pools[i++] = _makePoolData(TOKEN_wstkscETH, AmmAdapterIdLib.ERC_4626, TOKEN_wstkscETH, TOKEN_stkscETH);
        pools[i++] =
            _makePoolData(POOL_SHADOW_CL_scETH_stkscETH_250, AmmAdapterIdLib.UNISWAPV3, TOKEN_stkscETH, TOKEN_scETH);

        pools[i++] = _makePoolData(POOL_SWAPX_CL_wS_OS, AmmAdapterIdLib.ALGEBRA_V4, TOKEN_OS, TOKEN_wS);
        pools[i++] = _makePoolData(TOKEN_wOS, AmmAdapterIdLib.ERC_4626, TOKEN_wOS, TOKEN_OS);

        pools[i++] = _makePoolData(SILO_VAULT_25_wS, AmmAdapterIdLib.ERC_4626, SILO_VAULT_25_wS, TOKEN_wS);
        pools[i++] = _makePoolData(
            POOL_BEETS_V3_SILO_VAULT_25_wS_anS, AmmAdapterIdLib.BALANCER_V3_STABLE, TOKEN_anS, SILO_VAULT_25_wS
        );
        pools[i++] = _makePoolData(TOKEN_wanS, AmmAdapterIdLib.ERC_4626, TOKEN_wanS, TOKEN_anS);

        pools[i++] = _makePoolData(POOL_SWAPX_CL_frxUSD_scUSD, AmmAdapterIdLib.ALGEBRA_V4, TOKEN_frxUSD, TOKEN_scUSD);
        pools[i++] =
            _makePoolData(POOL_SWAPX_CL_sfrxUSD_frxUSD, AmmAdapterIdLib.ALGEBRA_V4, TOKEN_sfrxUSD, TOKEN_frxUSD);

        pools[i++] =
            _makePoolData(POOL_SHADOW_CL_x33_SHADOW, AmmAdapterIdLib.UNISWAPV3, TOKEN_x33, TOKEN_SHADOW);
        
        pools[i++] = _makePoolData(POOL_EQUALIZER_wS_DIAMONDS, AmmAdapterIdLib.SOLIDLY, TOKEN_DIAMONDS, TOKEN_wS);

        pools[i++] = _makePoolData(POOL_PENDLE_PT_aUSDC_14AUG2025, AmmAdapterIdLib.PENDLE, TOKEN_PT_aUSDC_14AUG2025, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_PENDLE_PT_wstkscUSD_29MAY2025, AmmAdapterIdLib.PENDLE, TOKEN_PT_wstkscUSD_29MAY2025, TOKEN_stkscUSD);
        pools[i++] = _makePoolData(POOL_PENDLE_PT_stS_29MAY2025, AmmAdapterIdLib.PENDLE, TOKEN_PT_stS_29MAY2025, TOKEN_stS);

        //endregion ----- Pools ----
    }

    function farms() public view returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](34);
        uint i;

        _farms[i++] = _makeBeetsStableFarm(BEETS_GAUGE_wS_stS);
        _farms[i++] = _makeBeetsStableFarm(BEETS_GAUGE_USDC_scUSD);
        _farms[i++] = _makeEqualizerFarm(EQUALIZER_GAUGE_USDC_WETH);
        _farms[i++] = _makeEqualizerFarm(EQUALIZER_GAUGE_wS_stS);
        _farms[i++] = _makeEqualizerFarm(EQUALIZER_GAUGE_wS_USDC);
        _farms[i++] = _makeEqualizerFarm(EQUALIZER_GAUGE_USDC_scUSD);
        _farms[i++] = _makeBeetsWeightedFarm(BEETS_GAUGE_scUSD_stS);
        _farms[i++] = _makeEqualizerFarm(EQUALIZER_GAUGE_wS_GOGLZ);
        _farms[i++] = _makeIchiSwapXFarm(SWAPX_GAUGE_ICHI_SACRA_wS);
        _farms[i++] = _makeIchiSwapXFarm(SWAPX_GAUGE_ICHI_wS_SACRA);
        _farms[i++] = _makeIchiSwapXFarm(SWAPX_GAUGE_ICHI_stS_wS);
        _farms[i++] = _makeIchiSwapXFarm(SWAPX_GAUGE_ICHI_wS_stS);
        _farms[i++] = _makeIchiSwapXFarm(SWAPX_GAUGE_ICHI_SACRA_GEM_1_wS);
        _farms[i++] = _makeIchiSwapXFarm(SWAPX_GAUGE_ICHI_wS_SACRA_GEM_1);
        _farms[i++] = _makeSwapXFarm(SWAPX_GAUGE_USDC_scUSD);
        _farms[i++] = _makeSwapXFarm(SWAPX_GAUGE_wS_GOGLZ);
        _farms[i++] = _makeSwapXFarm(SWAPX_GAUGE_AUR_auUSDC);
        _farms[i++] = _makeBeetsWeightedFarm(BEETS_GAUGE_USDC_stS);
        _farms[i++] =
            _makeGammaUniswapV3MerklFarm(ALM_GAMMA_UNISWAPV3_wS_USDC_3000, ALMPositionNameLib.NARROW, TOKEN_wS);
        _farms[i++] =
            _makeGammaUniswapV3MerklFarm(ALM_GAMMA_UNISWAPV3_wS_WETH_3000, ALMPositionNameLib.NARROW, TOKEN_wS);
        _farms[i++] =
            _makeGammaUniswapV3MerklFarm(ALM_GAMMA_UNISWAPV3_USDC_WETH_500, ALMPositionNameLib.NARROW, TOKEN_wS);
        _farms[i++] =
            _makeGammaUniswapV3MerklFarm(ALM_GAMMA_UNISWAPV3_USDC_scUSD_100, ALMPositionNameLib.STABLE, TOKEN_wS);
        _farms[i++] = _makeSiloFarm(SILO_GAUGE_wS_008);
        _farms[i++] = _makeSiloFarm(SILO_GAUGE_wS_020);
        _farms[i++] = _makeIchiSwapXFarm(SWAPX_GAUGE_ICHI_sfrxUSD_frxUSD); // farm 24
        _farms[i++] = _makeALMShadowFarm(SHADOW_GAUGE_CL_wS_WETH, ALMLib.ALGO_FILL_UP, 3000, 1200);
        _farms[i++] = _makeALMShadowFarm(SHADOW_GAUGE_CL_wS_WETH, ALMLib.ALGO_FILL_UP, 1500, 600);
        _farms[i++] = _makeALMShadowFarm(SHADOW_GAUGE_CL_wS_USDC, ALMLib.ALGO_FILL_UP, 3000, 1200);
        _farms[i++] = _makeALMShadowFarm(SHADOW_GAUGE_CL_wS_USDC, ALMLib.ALGO_FILL_UP, 1500, 600);
        _farms[i++] = _makeALMShadowFarm(SHADOW_GAUGE_CL_SACRA_scUSD_20000, ALMLib.ALGO_FILL_UP, 120000, 40000);
        _farms[i++] = _makeALMShadowFarm(SHADOW_GAUGE_CL_SACRA_scUSD_20000, ALMLib.ALGO_FILL_UP, 800, 400);
        _farms[i++] = _makeGammaEqualizerFarm(ALM_GAMMA_EQUALIZER_wS_USDC, ALMPositionNameLib.NARROW, EQUALIZER_GAUGE_GAMMA_wS_USDC);
        _farms[i++] = _makeGammaEqualizerFarm(ALM_GAMMA_EQUALIZER_WETH_wS, ALMPositionNameLib.NARROW, EQUALIZER_GAUGE_GAMMA_WETH_wS);
        _farms[i++] = _makeGammaEqualizerFarm(ALM_GAMMA_EQUALIZER_USDC_WETH, ALMPositionNameLib.NARROW, EQUALIZER_GAUGE_GAMMA_USDC_WETH);
    }

    function _makeALMShadowFarm(
        address gauge,
        uint algoId,
        int24 range,
        int24 triggerRange
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IGaugeV3(gauge).pool();
        farm.strategyLogicId = StrategyIdLib.ALM_SHADOW_FARM;
        farm.rewardAssets = IGaugeV3(gauge).getRewardTokens();
        farm.addresses = new address[](3);
        farm.addresses[0] = gauge;
        farm.addresses[1] = IGaugeV3(gauge).nfpManager();
        farm.addresses[2] = TOKEN_xSHADOW;
        farm.nums = new uint[](1);
        farm.nums[0] = algoId;
        farm.ticks = new int24[](2);
        farm.ticks[0] = range;
        farm.ticks[1] = triggerRange;
        return farm;
    }

    function _makeGammaUniswapV3MerklFarm(
        address hypervisor,
        uint preset,
        address rewardAsset
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IHypervisor(hypervisor).pool();
        farm.strategyLogicId = StrategyIdLib.GAMMA_UNISWAPV3_MERKL_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = rewardAsset;
        farm.addresses = new address[](2);
        farm.addresses[0] = GAMMA_UNISWAPV3_UNIPROXY;
        farm.addresses[1] = hypervisor;
        farm.nums = new uint[](1);
        farm.nums[0] = preset;
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeGammaEqualizerFarm(
        address hypervisor,
        uint preset,
        address gauge
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IHypervisor(hypervisor).pool();
        farm.strategyLogicId = StrategyIdLib.GAMMA_EQUALIZER_FARM;
        uint len = IGaugeEquivalent(gauge).rewardsListLength();
        farm.rewardAssets = new address[](len);
        for (uint i; i < len; ++i) {
            farm.rewardAssets[i] = IGaugeEquivalent(gauge).rewardTokens(i);
        }
        farm.addresses = new address[](3);
        farm.addresses[0] = GAMMA_EQUALIZER_UNIPROXY;
        farm.addresses[1] = hypervisor;
        farm.addresses[2] = gauge;
        farm.nums = new uint[](1);
        farm.nums[0] = preset;
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeSwapXFarm(address gauge) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IGaugeV2(gauge).TOKEN();
        farm.strategyLogicId = StrategyIdLib.SWAPX_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = IGaugeV2(gauge).rewardToken();
        farm.addresses = new address[](2);
        farm.addresses[0] = gauge;
        farm.addresses[1] = SWAPX_ROUTER_V2;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeIchiSwapXFarm(address gauge) internal view returns (IFactory.Farm memory) {
        address alm = IGaugeV2_CL(gauge).TOKEN();
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IICHIVault(alm).pool();
        farm.strategyLogicId = StrategyIdLib.ICHI_SWAPX_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = IGaugeV2_CL(gauge).rewardToken();
        farm.addresses = new address[](2);
        farm.addresses[0] = alm;
        farm.addresses[1] = gauge;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeBeetsStableFarm(address gauge) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IBalancerGauge(gauge).lp_token();
        farm.strategyLogicId = StrategyIdLib.BEETS_STABLE_FARM;
        uint len = IBalancerGauge(gauge).reward_count();
        farm.rewardAssets = new address[](len);
        for (uint i; i < len; ++i) {
            farm.rewardAssets[i] = IBalancerGauge(gauge).reward_tokens(i);
        }
        farm.addresses = new address[](1);
        farm.addresses[0] = gauge;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeBeetsWeightedFarm(address gauge) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IBalancerGauge(gauge).lp_token();
        farm.strategyLogicId = StrategyIdLib.BEETS_WEIGHTED_FARM;
        uint len = IBalancerGauge(gauge).reward_count();
        farm.rewardAssets = new address[](len);
        for (uint i; i < len; ++i) {
            farm.rewardAssets[i] = IBalancerGauge(gauge).reward_tokens(i);
        }
        farm.addresses = new address[](1);
        farm.addresses[0] = gauge;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeEqualizerFarm(address gauge) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IGaugeEquivalent(gauge).stake();
        farm.strategyLogicId = StrategyIdLib.EQUALIZER_FARM;
        uint len = IGaugeEquivalent(gauge).rewardsListLength();
        farm.rewardAssets = new address[](len);
        for (uint i; i < len; ++i) {
            farm.rewardAssets[i] = IGaugeEquivalent(gauge).rewardTokens(i);
        }
        farm.addresses = new address[](2);
        farm.addresses[0] = gauge;
        farm.addresses[1] = EQUALIZER_ROUTER_03;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeSiloFarm(address gauge) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.strategyLogicId = StrategyIdLib.SILO_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = TOKEN_wS;
        farm.addresses = new address[](2);
        farm.addresses[0] = gauge;
        farm.addresses[1] = ISiloIncentivesController(gauge).SHARE_TOKEN();
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makePoolData(
        address pool,
        string memory ammAdapterId,
        address tokenIn,
        address tokenOut
    ) internal pure returns (ISwapper.AddPoolData memory) {
        return ISwapper.AddPoolData({pool: pool, ammAdapterId: ammAdapterId, tokenIn: tokenIn, tokenOut: tokenOut});
    }

    function _addVaultType(IFactory factory, string memory id, address implementation, uint buildingPrice) internal {
        factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: id,
                implementation: implementation,
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: buildingPrice
            })
        );
    }

    function _addStrategyLogic(IFactory factory, string memory id, address implementation, bool farming) internal {
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: id,
                implementation: address(implementation),
                deployAllowed: true,
                upgradeAllowed: true,
                farming: farming,
                tokenId: type(uint).max
            }),
            StrategyDeveloperLib.getDeveloper(id)
        );
    }

    function testChainLib() external {}
}
