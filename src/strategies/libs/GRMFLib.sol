// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ALMPositionNameLib.sol";
import "../../core/libs/CommonLib.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IAmmAdapter.sol";
import "../../interfaces/IStrategy.sol";
import "../../interfaces/IFarmingStrategy.sol";
import "../../integrations/gamma/IUniProxy.sol";
import "../../integrations/uniswapv3/IUniswapV3Pool.sol";
import "../../integrations/uniswapv3/IQuoter.sol";
import "../../integrations/retro/IOToken.sol";

/// @title Library for GRMF strategy code splitting
library GRMFLib {
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
    ) external view returns (string memory) {
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
}
