// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {RecoveryLib} from "../../src/tokenomics/libs/RecoveryLib.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {Recovery} from "../../src/tokenomics/Recovery.sol";
import {IUniswapV3Pool} from "../../src/integrations/uniswapv3/IUniswapV3Pool.sol";
import {UniswapV3Callee} from "../../src/test/UniswapV3Callee.sol";


contract RecoverySonicTest is Test {
    uint public constant FORK_BLOCK = 47854805; // Sep-23-2025 04:02:39 AM +UTC
    address multisig;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();
    }

    struct SingleTestCase {
        address recoveryToken;
        address recoveryPool;
    }

    //region --------------------------------- Unit tests
    function testRecoveryStorageLocation() public pure {
        assertEq(
            keccak256(abi.encode(uint(keccak256("erc7201:stability.Recovery")) - 1)) & ~bytes32(uint(0xff)),
            RecoveryLib._RECOVERY_STORAGE_LOCATION,
            "_RECOVERY_STORAGE_LOCATION"
        );
    }
    //endregion --------------------------------- Unit tests

    //region --------------------------------- Use Recovery with single recovery token

    function testSingleUser() public {
        // ------------------------- Setup
        Recovery recovery;
        {
            Proxy proxy = new Proxy();
            proxy.initProxy(address(new Recovery()));
            recovery = Recovery(address(proxy));
            recovery.initialize(SonicConstantsLib.PLATFORM);
        }
        {
            address[] memory pools = new address[](1);
            pools[0] = SonicConstantsLib.RECOVERY_POOL_CREDIX_METAUSD;

            vm.prank(multisig);
            recovery.addRecoveryPools(pools);
        }

        // ------------------------- User creates a position in the pool
        address user1 = makeAddr("user1");
        deal(SonicConstantsLib.RECOVERY_TOKEN_CREDIX_METAUSD, user1, 1e18);
        _openPosition(user1, IUniswapV3Pool(SonicConstantsLib.RECOVERY_POOL_CREDIX_METAUSD));

        // ------------------------- Recovery buys recovery tokens
        address[] memory tokens = new address[](1);
        tokens[0] = SonicConstantsLib.WRAPPED_METAVAULT_METAUSD;

        uint[] memory amounts = new uint[](1);
        amounts[0] = 1e18;

        deal(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, address(recovery), amounts[0]);
        recovery.registerTransferredAmounts(tokens, amounts);
    }

    //endregion --------------------------------- Use Recovery with single recovery token

    //region --------------------------------- Use Recovery with single recovery token
    function fixtureSingle() public pure returns (SingleTestCase[] memory) {
        SingleTestCase[] memory cases = new SingleTestCase[](6);
        cases[0] = SingleTestCase({
            recoveryToken: SonicConstantsLib.RECOVERY_TOKEN_CREDIX_METAUSD,
            recoveryPool: SonicConstantsLib.RECOVERY_POOL_CREDIX_METAUSD
        });
        cases[1] = SingleTestCase({
            recoveryToken: SonicConstantsLib.RECOVERY_TOKEN_CREDIX_WMETAUSD,
            recoveryPool: SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAUSD
        });
        cases[2] = SingleTestCase({
            recoveryToken: SonicConstantsLib.RECOVERY_TOKEN_CREDIX_WMETAUSDC,
            recoveryPool: SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAUSDC
        });
        cases[3] = SingleTestCase({
            recoveryToken: SonicConstantsLib.RECOVERY_TOKEN_CREDIX_WMETASCUSD,
            recoveryPool: SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETASCUSD
        });
        cases[4] = SingleTestCase({
            recoveryToken: SonicConstantsLib.RECOVERY_TOKEN_CREDIX_METAS,
            recoveryPool: SonicConstantsLib.RECOVERY_POOL_CREDIX_METAS
        });
        cases[5] = SingleTestCase({
            recoveryToken: SonicConstantsLib.RECOVERY_TOKEN_CREDIX_WMETAS,
            recoveryPool: SonicConstantsLib.RECOVERY_POOL_CREDIX_WMETAS
        });

        return cases;
    }

    function tableSingleTest(SingleTestCase memory single) public {
        // todo

        // ---------------------- User opens new position

        // ---------------------- Deal meta vault tokens for Recovery

        // ---------------------- Register meta vault tokens in Recovery

        // ---------------------- Check results

    }

    //endregion --------------------------------- Use Recovery with single recovery token


    //region --------------------------------- Uniswap v3 utils
    function _openPosition(address user, IUniswapV3Pool pool) internal {
        UniswapV3Callee callee = new UniswapV3Callee();

        IERC20 recoveryToken = IERC20(pool.token0());
        uint recoveryAmount = IERC20(recoveryToken).balanceOf(user);

        vm.prank(user);
        recoveryToken.transfer(address(callee), recoveryAmount);

        vm.prank(address(callee));
        recoveryToken.approve(address(pool), recoveryAmount);

        (, int24 tick, , , , , ) = pool.slot0();

        int24 tickSpacing = pool.tickSpacing();
        int24 tickLower = (tick / tickSpacing) * tickSpacing;
        int24 tickUpper = tickLower + tickSpacing;

        console.log("1");

        vm.prank(user);
        callee.mint(address(pool), user, tickLower, tickUpper, uint128(recoveryAmount));

        console.log("1");
    }
    //endregion --------------------------------- Uniswap v3 utils
}
