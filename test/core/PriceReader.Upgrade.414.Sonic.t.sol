// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

//import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {PriceReader, IPriceReader, IPlatform} from "../../src/core/PriceReader.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {UniswapV3Adapter} from "../../src/adapters/UniswapV3Adapter.sol";
import {SolidlyAdapter} from "../../src/adapters/SolidlyAdapter.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";

/// @notice #348
contract PriceReaderUpgrade414SonicTest is Test {
    uint public constant FORK_BLOCK = 51622705; // Oct-23-2025 06:32:10 AM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public multisig;
    IPriceReader public priceReader;

    /// @notice Example of Solidly pool with unknown asset (ERC-20: U$D (U$D)) required for bad path test only
    address public constant POOL_SHADOW_USDC_USSSDC = 0x45B2D556724786BDD3893fC5AEEE02d38635Df46;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
    }

    function setUp() public {
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        multisig = IPlatform(PLATFORM).multisig();
        _upgradePlatform();
    }

    function testGetTwaPriceSolidlyAdapter() public view {
        (uint price,) = priceReader.getPrice(SonicConstantsLib.TOKEN_STBL);
        (uint twaPrice,) = priceReader.getTwaPrice(
            SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.POOL_SHADOW_STBL_USDC, AmmAdapterIdLib.SOLIDLY, 300
        );

        //        console.log("price", price);
        //        console.log("twaPrice", twaPrice);

        assertApproxEqAbs(price, twaPrice, price * 3 / 10, "current price ~ twa price");
        assertNotEq(price, twaPrice, "current price != twa price");
    }

    function testGetTwaPriceSolidlyAdapterZeroPeriodCurrentPrice() public view {
        (uint price,) = priceReader.getPrice(SonicConstantsLib.TOKEN_STBL);
        (uint twaPrice,) = priceReader.getTwaPrice(
            SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.POOL_SHADOW_STBL_USDC, AmmAdapterIdLib.SOLIDLY, 0
        );

        //        console.log("price", price);
        //        console.log("twaPrice", twaPrice);

        assertEq(
            price, twaPrice, "current price == twa price (assume here that swapper takes price through SolidlyAdapter)"
        );
    }

    function testGetTwaPriceUniswapAdapter() public view {
        (uint price,) = priceReader.getPrice(SonicConstantsLib.TOKEN_STBL);
        (uint twaPrice,) = priceReader.getTwaPrice(
            SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.POOL_SHADOW_CL_STBL_USDC, AmmAdapterIdLib.UNISWAPV3, 300
        );

        //        console.log("price", price);
        //        console.log("twaPrice", twaPrice);

        assertApproxEqAbs(price, twaPrice, price * 3 / 10, "current price ~ twa price");
        assertNotEq(price, twaPrice, "current price != twa price");
    }

    function testGetTwaPriceBadPaths() public {
        // ---------------------------- unknown AMM adapter
        vm.expectRevert(PriceReader.UnknownAMMAdapter.selector);
        priceReader.getTwaPrice(
            SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.POOL_SHADOW_CL_STBL_USDC, "Unknown", 300
        );

        // ---------------------------- number of tokens in the pool is not 2
        vm.expectRevert(PriceReader.WrongNumberPoolTokens.selector);
        priceReader.getTwaPrice(
            SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.POOL_PENDLE_PT_SMSUSD_30OCT2025, AmmAdapterIdLib.PENDLE, 300
        );

        // ---------------------------- unknown token for the pool
        vm.expectRevert(PriceReader.TokenNotFound.selector);
        priceReader.getTwaPrice(SonicConstantsLib.TOKEN_STBL, POOL_SHADOW_USDC_USSSDC, AmmAdapterIdLib.SOLIDLY, 300);

        // ---------------------------- there is no price for token out
        (uint price, bool trusted) =
            priceReader.getTwaPrice(SonicConstantsLib.TOKEN_USDC, POOL_SHADOW_USDC_USSSDC, AmmAdapterIdLib.SOLIDLY, 300);
        assertEq(price, 0, "price == 0");
        assertEq(trusted, false, "trusted == false");
    }

    //region --------------------------------- Internal logic

    //endregion --------------------------------- Internal logic

    //region --------------------------------- Helpers
    function _upgradePlatform() internal {
        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](3);
        proxies[0] = address(priceReader);
        proxies[1] = platform.ammAdapter(keccak256(bytes(AmmAdapterIdLib.UNISWAPV3))).proxy;
        proxies[2] = platform.ammAdapter(keccak256(bytes(AmmAdapterIdLib.SOLIDLY))).proxy;

        address[] memory implementations = new address[](3);
        implementations[0] = address(new PriceReader());
        implementations[1] = address(new UniswapV3Adapter());
        implementations[2] = address(new SolidlyAdapter());

        vm.prank(multisig);
        IPlatform(PLATFORM).cancelUpgrade();

        vm.startPrank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.05.0-alpha", proxies, implementations);
        skip(1 days);
        IPlatform(PLATFORM).upgrade();
        vm.stopPrank();
    }
    //endregion --------------------------------- Helpers
}
