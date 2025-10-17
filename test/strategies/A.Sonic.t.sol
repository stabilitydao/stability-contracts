// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {IAToken} from "../../src/integrations/aave/IAToken.sol";
import {IPool} from "../../src/integrations/aave/IPool.sol";

contract AaveStrategyTestSonic is SonicSetup, UniversalTest {
    uint internal constant FORK_BLOCK = 31996320; // Jun-05-2025 09:19:04 AM +UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        // vm.rollFork(28237049); // May-20-2025 12:17:44 PM +UTC

        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
        // console.log("erc7201:stability.AaveStrategy");
        // console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.AaveStrategy")) - 1)) & ~bytes32(uint256(0xff)));
    }

    /// @notice Compare APR with https://stability.market/
    function testAaveStrategy() public universalTest {
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_WS);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_USDC);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_SCUSD);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_WETH);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_USDT);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_WOS);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_STS);
    }

    function _addStrategy(address aToken) internal {
        address[] memory initStrategyAddresses = new address[](1);
        initStrategyAddresses[0] = aToken;
        strategies.push(
            Strategy({
                id: StrategyIdLib.AAVE,
                pool: address(0),
                farmId: type(uint).max,
                strategyInitAddresses: initStrategyAddresses,
                strategyInitNums: new uint[](0)
            })
        );
    }

    /// @notice Deal doesn't work with aave tokens. So, deal the asset and mint aTokens instead.
    /// @dev https://github.com/foundry-rs/forge-std/issues/140
    function _dealUnderlying(address underlying, address to, uint amount) internal override {
        IPool pool = IPool(IAToken(underlying).POOL());

        address asset = IAToken(underlying).UNDERLYING_ASSET_ADDRESS();

        deal(asset, to, amount);

        vm.prank(to);
        IERC20(asset).approve(address(pool), amount);

        vm.prank(to);
        pool.deposit(asset, amount, to, 0);
    }
}
