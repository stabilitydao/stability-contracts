// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ALMPositionNameLib} from "./ALMPositionNameLib.sol";
import {CommonLib} from "../../core/libs/CommonLib.sol";
import {IFactory} from "../../interfaces/IFactory.sol";
import {IAmmAdapter} from "../../interfaces/IAmmAdapter.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {IFarmingStrategy} from "../../interfaces/IFarmingStrategy.sol";
import {IUniProxy} from "../../integrations/gamma/IUniProxy.sol";
import {IUniswapV3Pool} from "../../integrations/uniswapv3/IUniswapV3Pool.sol";
import {IQuoter} from "../../integrations/uniswapv3/IQuoter.sol";
import {IOToken} from "../../integrations/retro/IOToken.sol";
import {IHypervisor} from "../../integrations/gamma/IHypervisor.sol";
import {UniswapV3MathLib} from "./UniswapV3MathLib.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {LPStrategyLib} from "./LPStrategyLib.sol";

/// @title Library for GRMF strategy code splitting
library GRMFLib {
    using SafeERC20 for IERC20;

    uint internal constant _PRECISION = 1e36;

    /// @custom:storage-location erc7201:stability.GammaRetroFarmStrategy
    struct GammaRetroFarmStrategyStorage {
        IUniProxy uniProxy;
        address paymentToken;
        address flashPool;
        address oPool;
        address uToPaymentTokenPool;
        address quoter;
        bool flashOn;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error NotFlashPool();
    error PairReentered();

    function uniswapV3FlashCallback(
        address platform,
        string memory ammAdapterId,
        GammaRetroFarmStrategyStorage storage $,
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f,
        uint fee1
    ) external {
        address flashPool = $.flashPool;
        address paymentToken = $.paymentToken;
        address oToken = $f._rewardAssets[0];
        address uToken = getOtherTokenFromPool($.oPool, oToken);

        if (msg.sender != flashPool) {
            revert NotFlashPool();
        }
        if (!$.flashOn) {
            revert PairReentered();
        }

        // Exercise the oToken
        uint paymentTokenAmount = IERC20(paymentToken).balanceOf(address(this));
        uint oTokenAmt = IERC20(oToken).balanceOf(address(this));

        //slither-disable-next-line unused-return
        IOToken(oToken).exercise(oTokenAmt, paymentTokenAmount, address(this));

        // Swap underlying to payment token
        address swapper = IPlatform(platform).swapper();

        ISwapper.PoolData[] memory route = new ISwapper.PoolData[](1);
        route[0].pool = $.uToPaymentTokenPool;
        route[0].ammAdapter = IPlatform(platform).ammAdapter(keccak256(bytes(ammAdapterId))).proxy;
        route[0].tokenIn = uToken;
        route[0].tokenOut = paymentToken;
        ISwapper(swapper).swapWithRoute(
            route, balance(uToken), LPStrategyLib.SWAP_ASSETS_PRICE_IMPACT_TOLERANCE
        );

        // Pay off our loan
        uint pairDebt = paymentTokenAmount + fee1;
        IERC20(paymentToken).safeTransfer(flashPool, pairDebt);

        $.flashOn = false;
    }

    function initVariants(address platform_, string memory strategyLogicId, string memory ammAdapterId)
    public
    view
    returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        IAmmAdapter _ammAdapter = IAmmAdapter(IPlatform(platform_).ammAdapter(keccak256(bytes(ammAdapterId))).proxy);
        addresses = new address[](0);
        ticks = new int24[](0);

        IFactory.Farm[] memory farms = IFactory(IPlatform(platform_).factory()).farms();
        uint len = farms.length;
        //slither-disable-next-line uninitialized-local
        uint localTtotal;
        // nosemgrep
        for (uint i; i < len; ++i) {
            // nosemgrep
            IFactory.Farm memory farm = farms[i];
            // nosemgrep
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyLogicId)) {
                ++localTtotal;
            }
        }

        variants = new string[](localTtotal);
        nums = new uint[](localTtotal);
        localTtotal = 0;
        // nosemgrep
        for (uint i; i < len; ++i) {
            // nosemgrep
            IFactory.Farm memory farm = farms[i];
            // nosemgrep
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyLogicId)) {
                nums[localTtotal] = i;
                //slither-disable-next-line calls-loop
                variants[localTtotal] = generateDescription(farm, _ammAdapter);
                ++localTtotal;
            }
        }
    }

    function claimRevenue(
        IStrategy.StrategyBaseStorage storage __$__,
        IFarmingStrategy.FarmingStrategyBaseStorage storage _$_,
        GammaRetroFarmStrategyStorage storage $
    )
        external
        returns (
            address[] memory __assets,
            uint[] memory __amounts,
            address[] memory __rewardAssets,
            uint[] memory __rewardAmounts
        )
    {
        __assets = __$__._assets;
        __amounts = new uint[](2);
        __rewardAssets = _$_._rewardAssets;
        uint rwLen = __rewardAssets.length;
        __rewardAmounts = new uint[](rwLen);

        // should we swap or flash excercise
        address oToken = __rewardAssets[0];
        uint oTokenAmount = balance(oToken);
        address oPool = $.oPool;

        if (oTokenAmount > 0) {
            address uToken = getOtherTokenFromPool(oPool, oToken);
            bool needSwap = _shouldWeSwap(oToken, uToken, oTokenAmount, oPool, $.quoter);

            if (!needSwap) {
                // Get payment token amount needed to exercise oTokens.
                uint amountNeeded = IOToken(oToken).getDiscountedPrice(oTokenAmount);

                // Enter flash loan.
                $.flashOn = true;
                IUniswapV3Pool($.flashPool).flash(address(this), 0, amountNeeded, "");
                __rewardAssets[0] = $.paymentToken;
            }
        }

        for (uint i; i < rwLen; ++i) {
            __rewardAmounts[i] = balance(__rewardAssets[i]);
        }
    }

    function _shouldWeSwap(
        address oToken,
        address uToken,
        uint amount,
        address pool,
        address quoter
    ) internal returns (bool should) {
        // Whats the amount of underlying we get for flashSwapping.
        uint discount = IOToken(oToken).discount();
        uint flashAmount = amount * (100 - discount) / 100;

        // How much we get for just swapping through LP.
        uint24 fee = IUniswapV3Pool(pool).fee();
        uint swapAmount = IQuoter(quoter).quoteExactInputSingle(oToken, uToken, fee, amount, 0);

        if (swapAmount > flashAmount) {
            should = true;
        }
    }

    function getOtherTokenFromPool(address pool, address token) public view returns (address) {
        address token0 = IUniswapV3Pool(pool).token0();
        address token1 = IUniswapV3Pool(pool).token1();
        return token == token0 ? token1 : token0;
    }

    function balance(address token) public view returns (uint) {
        return IERC20(token).balanceOf(address(this));
    }

    function generateDescription(
        IFactory.Farm memory farm,
        IAmmAdapter _ammAdapter
    ) public view returns (string memory) {
        //slither-disable-next-line calls-loop
        return string.concat(
            "Earn ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(farm.rewardAssets), ", "),
            " on Retro by ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(_ammAdapter.poolTokens(farm.pool)), "-"),
            " Gamma ",
            //slither-disable-next-line calls-loop
            ALMPositionNameLib.getName(farm.nums[0]),
            " LP"
        );
    }

    /// @dev proportion of 1e18
    function getProportion0(address pool_, address alm_) external view returns (uint) {
        IHypervisor hypervisor = IHypervisor(alm_);
        //slither-disable-next-line unused-return
        (, int24 tick,,,,,) = IUniswapV3Pool(pool_).slot0();
        uint160 sqrtPrice = UniswapV3MathLib.getSqrtRatioAtTick(tick);
        uint price = UniswapV3MathLib.mulDiv(uint(sqrtPrice) * uint(sqrtPrice), _PRECISION, 2 ** (96 * 2));
        (uint pool0, uint pool1) = hypervisor.getTotalAmounts();
        //slither-disable-next-line divide-before-multiply
        uint pool0PricedInToken1 = pool0 * price / _PRECISION;
        //slither-disable-next-line divide-before-multiply
        return 1e18 * pool0PricedInToken1 / (pool0PricedInToken1 + pool1);
    }
}
