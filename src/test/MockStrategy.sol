// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IMockERC20.sol";
import "../strategies/base/LPStrategyBase.sol";
import "../strategies/libs/StrategyIdLib.sol";
import "../core/libs/CommonLib.sol";

contract MockStrategy is LPStrategyBase {
    string public constant VERSION = "10.99.99";

    uint private _depositedToken0;
    uint private _depositedToken1;
    uint private _fee0;
    uint private _fee1;

    bool private _depositReturnZero;

    /// @inheritdoc IStrategy
    function description() external pure returns (string memory) {
        return "";
    }

    function setLastApr(uint apr) external {
        StrategyBaseStorage storage $ = _getStrategyBaseStorage();
        $.lastApr = apr;
    }

    function initialize(
        address[] memory addresses,
        uint[] memory, /*nums*/
        int24[] memory /*ticks*/
    ) public initializer {
        require(addresses[3] != address(0), "Strategy: underlying token cant be zero for this strategy");

        __LPStrategyBase_init(
            LPStrategyBaseInitParams({
                id: StrategyIdLib.DEV,
                platform: addresses[0],
                vault: addresses[1],
                pool: addresses[2],
                underlying: addresses[3]
            })
        );
    }

    function toggleDepositReturnZero() external {
        _depositReturnZero = !_depositReturnZero;
    }

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external pure returns (bool isReady) {
        isReady = true;
    }

    function initVariants(address)
        public
        pure
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        variants = new string[](2);
        variants[0] = "Collect fees in mock pool A";
        variants[1] = "Collect fees in mock pool B";
        addresses = new address[](4);
        addresses[0] = address(1);
        addresses[1] = address(2);
        addresses[2] = address(3);
        addresses[3] = address(4);
        nums = new uint[](0);
        ticks = new int24[](0);
    }

    function getSpecificName() external pure override returns (string memory, bool) {
        return ("Good Params", true);
    }

    function extra() external pure returns (bytes32) {
        bytes3 color = 0x558ac5;
        bytes3 bgColor = 0x121319;
        return CommonLib.bytesToBytes32(abi.encodePacked(color, bgColor));
    }

    function ammAdapterId() public pure override returns (string memory) {
        return "MOCKSWAP";
    }

    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.DEV;
    }

    function triggerFuse() external {
        StrategyBaseStorage storage $ = _getStrategyBaseStorage();
        $.total = 0;
    }

    /*    function untriggerFuse(uint total_) external {
        total = total_;
    }*/

    function setFees(uint fee0_, uint fee1_) external {
        _fee0 = fee0_;
        _fee1 = fee1_;
    }

    function getAssetsProportions() external view returns (uint[] memory proportions) {
        proportions = new uint[](2);
        proportions[0] = _getProportion0(pool());
        proportions[1] = 1e18 - proportions[0];
    }

    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        StrategyBaseStorage storage $ = _getStrategyBaseStorage();
        assets_ = $._assets;
        amounts_ = new uint[](2);

        // because assets on strategy balance
        //        amounts_[0] = _depositedToken0;
        //        amounts_[1] = _depositedToken1;
    }

    function _getProportion0(address /*pool*/ ) internal pure returns (uint) {
        return 5e17;
    }

    function _depositAssets(uint[] memory amounts, bool /*claimRevenue*/ ) internal override returns (uint value) {
        // no msg.sender checks
        StrategyBaseStorage storage $ = _getStrategyBaseStorage();
        uint[] memory amountsConsumed;
        (amountsConsumed, value) = _previewDepositAssets(amounts);
        _depositedToken0 += amountsConsumed[0];
        _depositedToken1 += amountsConsumed[1];
        $.total += value;
        IMockERC20($._underlying).mint(value);
        if (_depositReturnZero) {
            value = 0;
        }
    }

    function depositUnderlying(uint amount) external override returns (uint[] memory amountsConsumed) {
        // no msg.sender checks
        // require(_depositedToken0 > 0, "Mock: deposit assets first");
        StrategyBaseStorage storage $ = _getStrategyBaseStorage();
        uint addedToken0 = _depositedToken0 * amount / $.total;
        uint addedToken1 = _depositedToken1 * amount / $.total;
        _depositedToken0 += addedToken0;
        _depositedToken1 += addedToken1;
        amountsConsumed = new uint[](2);
        amountsConsumed[0] = addedToken0;
        amountsConsumed[1] = addedToken1;

        IMockERC20($._assets[0]).mint(addedToken0);
        IMockERC20($._assets[1]).mint(addedToken1);

        $.total += amount;

        // cover base strategy internal method
        _previewDepositUnderlying(0);
    }

    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        // no msg.sender checks
        StrategyBaseStorage storage $ = _getStrategyBaseStorage();
        amountsOut = new uint[](2);
        amountsOut[0] = _depositedToken0 * value / $.total;
        amountsOut[1] = _depositedToken1 * value / $.total;
        $.total -= value;
        IERC20($._assets[0]).transfer(receiver, amountsOut[0]);
        IERC20($._assets[1]).transfer(receiver, amountsOut[1]);
        _depositedToken0 -= amountsOut[0];
        _depositedToken1 -= amountsOut[1];
    }

    function withdrawUnderlying(uint amount, address receiver) external override {
        // no msg.sender checks
        StrategyBaseStorage storage $ = _getStrategyBaseStorage();
        bool fuseTriggered = $.total == 0;

        if (!fuseTriggered) {
            _depositedToken0 -= _depositedToken0 * amount / $.total;
            _depositedToken1 -= _depositedToken1 * amount / $.total;
            $.total -= amount;
        } else {
            uint balance = IERC20($._underlying).balanceOf(address(this));
            _depositedToken0 -= _depositedToken0 * amount / balance;
            _depositedToken1 -= _depositedToken1 * amount / balance;
        }

        IERC20($._underlying).transfer(receiver, amount);
    }

    function _claimRevenue()
        internal
        virtual
        override
        returns (
            address[] memory __assets,
            uint[] memory __amounts,
            address[] memory __rewardAssets,
            uint[] memory __rewardAmounts
        )
    {
        StrategyBaseStorage storage $ = _getStrategyBaseStorage();
        IMockERC20($._assets[0]).mint(_fee0);
        IMockERC20($._assets[1]).mint(_fee1);
        __amounts = new uint[](2);
        __amounts[0] = _fee0;
        __amounts[1] = _fee1;
        _fee0 = 0;
        _fee1 = 0;
        __assets = $._assets;

        __rewardAssets = new address[](0);
        __rewardAmounts = new uint[](0);
    }

    function _compound() internal virtual override {}

    function getRevenue() external pure override returns (address[] memory __assets, uint[] memory amounts) {
        __assets = new address[](0);
        amounts = new uint[](0);
    }

    function _liquidateRewards(
        address, /*exchangeAsset*/
        address[] memory, /*rewardAssets_*/
        uint[] memory /*rewardAmounts_*/
    ) internal pure override returns (uint earnedExchangeAsset) {}
}
