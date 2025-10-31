// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {IImpermaxV2SolidlyRouter01} from "../../src/integrations/impermax/IImpermaxV2SolidlyRouter01.sol";
import {IImpermaxBorrowableV2} from "../../src/integrations/impermax/IImpermaxBorrowableV2.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Permit} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IImpermaxCollateral} from "../../src/integrations/impermax/IImpermaxCollateral.sol";

/// @dev Borrow tx: https://sonicscan.org/tx/0x4486f0cc158d7ada27a5f72dc4a8cfbe0ab5b73329298e6be20b65ced28ec5a4
/// @dev Supply tx: https://sonicscan.org/tx/0x60a9a6447befa55d47eecf0dd5737768e824cd6a51231c79800d893dee2863b1
contract ImpermaxStudySonicTest is Test {
    uint internal constant FORK_BLOCK = 52766517; // Oct-31-2025 08:12:44 AM +UTC

    uint internal constant FORK_BORROW_TX_BLOCK = 51314094; // Oct-20-2025 01:29:00 PM UTC
    uint internal constant FORK_SUPPLY_TX_BLOCK = 51314070; // Oct-20-2025 01:28:30 PM UTC

    address internal constant LENDING_POOL_USDC_STBL = 0x7195d62A9E388ae21c7881CA29be8fadEb09379f;

    bytes internal constant BORROW_ACTION_DATA =
        hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000186a000000000000000000000000088888887c3ebd4a33e34a15db4254c74c75e5d4a0000000000000000000000000000000000000000000000000000000000000000";
    bytes internal constant BORROW_PERMITS_DATA =
        hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000060000000000000000000000000c2285af4f918c9bfd364cd7a5c403fba0f201a4300000000000000000000000000000000000000000000000000000000000186a00000000000000000000000000000000000000000000000000000000068ff67f400000000000000000000000000000000000000000000000000000000000000412d4498afde7893618241e30b773d1a883de0437dbf8988eab1fae343b8ba3703662e80e32503daf94b88c96e4b92cba9e20183940a0d3c668aa720c9a17fc6861b00000000000000000000000000000000000000000000000000000000000000";

    bytes internal constant SUPPLY_ACTION_DATA =
        hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000186a0000000000000000000000000000000000000000000000000092056aa1dd29836000000000000000000000000000000000000000000000000000000000000c35000000000000000000000000000000000000000000000000004902b550ee94c1b0000000000000000000000000000000000000000000000000000000000000000";
    bytes internal constant SUPPLY_PERMITS_DATA =
        hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000006000000000000000000000000029219dd400f2bf60e5a23d13be72b486d403889400000000000000000000000000000000000000000000000000000000000186a00000000000000000000000000000000000000000000000000000000068ff67f40000000000000000000000000000000000000000000000000000000000000041a843b54a3c3f8b760c534f1afa4de2799ed80ce51ee8bb16bd17f99f4dade13834879f4bcf6e833f826c3c5227ea19ede6a19cb3c1b3f7e277e72c73d8ca324e1b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000006000000000000000000000000078a76316f66224cbaca6e70acb24d5ee5b2bd2c7000000000000000000000000000000000000000000000000092056aa1dd298360000000000000000000000000000000000000000000000000000000068ff67f4000000000000000000000000000000000000000000000000000000000000004144526f83431c213b44290e7ebe8fe7be5afb255a1930cd304b2cd7efbe6775b03be2ca7b740c515ac4b087e381f03d5aabe6c841e3fbe4644b26e06ad9dd4e521b00000000000000000000000000000000000000000000000000000000000000";

    /// @dev ImpermaxV2SolidlyRouter01
    /// @dev from https://sonicscan.org/tx/0x4486f0cc158d7ada27a5f72dc4a8cfbe0ab5b73329298e6be20b65ced28ec5a4
    address internal constant ROUTER_ADDR = 0xB3B140dBcBC649eCeac74f30487A338e9D129331;
    /// @dev Owner address from the decoded Permit
    address internal constant OWNER_ADDR = 0x88888887C3ebD4a33E34a15Db4254C74C75E5D4A;
    /// @dev Token address (IMXB) from the decoded Permit
    address internal constant TOKEN_ADDR = 0xc2285Af4F918c9bFD364Cd7a5c403fBa0f201a43;

    /// @dev Values from the decoded Permit
    uint internal constant PERMIT_AMOUNT = 100000;
    uint internal constant DEADLINE = 1761568756;

    uint internal constant PERMIT_SUPPLY_AMOUNT_USDC = 100000;
    uint internal constant PERMIT_SUPPLY_AMOUNT_STBL = 657620834240862262;
    uint internal constant PERMIT_SUPPLY_DEADLINE = 1761568756;
    uint internal constant PERMIT_SUPPLY_AMOUNT0_MIN = 50000;
    uint internal constant PERMIT_SUPPLY_AMOUNT1_MIN = 328810417120431131;

    address internal constant TOKEN_A_USDC = SonicConstantsLib.TOKEN_USDC;
    address internal constant TOKEN_B_STBL = SonicConstantsLib.TOKEN_STBL;

    /// @dev BorrowPermit TypeHash from the original JS helper
    bytes32 internal constant BORROW_PERMIT_TYPEHASH = keccak256(
        abi.encodePacked("BorrowPermit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    );

    /// @dev SupplyPermit TypeHash from the original JS helper
    bytes32 internal constant SUPPLY_PERMIT_TYPEHASH = keccak256(
        abi.encodePacked("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    );

    bytes internal constant SIGNATURE_BORROW =
        hex"2d4498afde7893618241e30b773d1a883de0437dbf8988eab1fae343b8ba3703662e80e32503daf94b88c96e4b92cba9e20183940a0d3c668aa720c9a17fc6861b";

    bytes internal constant SIGNATURE_SUPPLY_USDC =
        hex"a843b54a3c3f8b760c534f1afa4de2799ed80ce51ee8bb16bd17f99f4dade13834879f4bcf6e833f826c3c5227ea19ede6a19cb3c1b3f7e277e72c73d8ca324e1b";
    bytes internal constant SIGNATURE_SUPPLY_STBL =
        hex"44526f83431c213b44290e7ebe8fe7be5afb255a1930cd304b2cd7efbe6775b03be2ca7b740c515ac4b087e381f03d5aabe6c841e3fbe4644b26e06ad9dd4e521b";

    uint internal constant TEST_PRIVATE_KEY = 15;
    /// @notice special stub-value to use predefined {OWNER_ADDR}
    uint internal constant SIGNER_PRIVATE_KEY_888 = 888;

    struct CreateSupplyPermitsDataLocal {
        address token;
        uint nonce;
        bytes32 digest;
        bytes signature;
    }

    struct AccountState {
        uint liquidity;
        uint shortfall;

        uint twapPrice112x112;
        uint collateralAmount;
        uint collateralExchangeRate;

        uint borrowBalance;
        uint borrowExchangeRate;

        uint price0;
        uint price1;

        uint debtValueInCollateral;
        uint ltv;

        uint balanceUSDC;
    }

    constructor() {
        // in each test
        // vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
    }

    function testDecodeBorrowTx() public {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BORROW_TX_BLOCK));
        // original tx: https://sonicscan.org/tx/0x4486f0cc158d7ada27a5f72dc4a8cfbe0ab5b73329298e6be20b65ced28ec5a4
        // block 51314094
        // timestamp: Oct-20-2025 01:29:00 PM UTC = 1760966940
        // IImpermaxV2SolidlyRouter01 router = IImpermaxV2SolidlyRouter01(ROUTER_ADDR);

        _showDecodedBorrowData(BORROW_ACTION_DATA, BORROW_PERMITS_DATA);

        //        permits.length 1
        //        permit[0].permitType 4
        //        permit[0].token 0xc2285Af4F918c9bFD364Cd7a5c403fBa0f201a43
        //        permit[0].amount 100000
        //        permit[0].deadline 1761568756
        //    0x2d4498afde7893618241e30b773d1a883de0437dbf8988eab1fae343b8ba3703662e80e32503daf94b88c96e4b92cba9e20183940a0d3c668aa720c9a17fc6861b
        //        actions.length 1
        //        action[0].actionType 0
        //        action[0].index 0
        //        action[0].amount 100000
        //        action[0].to 0x88888887C3ebD4a33E34a15Db4254C74C75E5D4A
    }

    function testDecodeSupplyTx() public {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BORROW_TX_BLOCK));

        _showDecodedSupplyData(SUPPLY_ACTION_DATA, SUPPLY_PERMITS_DATA);

        //        Logs:
        //        permits.length 2
        //        permit[0].permitType 0
        //        permit[0].token 0x29219dd400f2Bf60E5a23d13Be72B486D4038894
        //        permit[0].amount 100000
        //        permit[0].deadline 1761568756
        //    0xa843b54a3c3f8b760c534f1afa4de2799ed80ce51ee8bb16bd17f99f4dade13834879f4bcf6e833f826c3c5227ea19ede6a19cb3c1b3f7e277e72c73d8ca324e1b
        //        permit[1].token 0x78a76316F66224CBaCA6e70acB24D5ee5b2Bd2c7
        //        permit[1].amount 657620834240862262
        //        permit[1].deadline 1761568756
        //    0x44526f83431c213b44290e7ebe8fe7be5afb255a1930cd304b2cd7efbe6775b03be2ca7b740c515ac4b087e381f03d5aabe6c841e3fbe4644b26e06ad9dd4e521b

        //        actions.length 1
        //        action[0].actionType 8
        //        action[0].lpAmountUser 0
        //        action[0].amount0Desired 100000
        //        action[0].amount1Desired 657620834240862262
        //        action[0].amount0Min 50000
        //        action[0].amount1Min 328810417120431131
    }

    function testGenerateDataForBorrowTx() public {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BORROW_TX_BLOCK));

        // ---------------------- create actionData and permitsData
        bytes memory actionData = _createBorrowActionData();
        bytes memory permitsData = _createBorrowPermitsData(SIGNER_PRIVATE_KEY_888);

        // ---------------------- ensure that we get same data as original tx
        assertEq(actionData, BORROW_ACTION_DATA, "borrow action data");
        assertEq(permitsData, BORROW_PERMITS_DATA, "borrow supply data");
    }

    function testGenerateDataForSupplyTx() public {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_SUPPLY_TX_BLOCK));

        // ---------------------- create actionData and permitsData
        bytes memory actionData = _createSupplyActionData();
        bytes memory permitsData = _createSupplyPermitsData(SIGNER_PRIVATE_KEY_888);

        // ---------------------- ensure that we get same data as original tx
        assertEq(actionData, SUPPLY_ACTION_DATA, "supply action data");
        assertEq(permitsData, SUPPLY_PERMITS_DATA, "supply permits data");
    }

    function testBorrowByTestUser() public {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        address owner = vm.addr(TEST_PRIVATE_KEY);

        //------------------------------- Calculate desired amounts
        IImpermaxV2SolidlyRouter01 router = IImpermaxV2SolidlyRouter01(ROUTER_ADDR);
        (uint amount0, uint amount1) = router._optimalLiquidityUniV2(
            LENDING_POOL_USDC_STBL,
            PERMIT_SUPPLY_AMOUNT_USDC,
            PERMIT_SUPPLY_AMOUNT_STBL,
            PERMIT_SUPPLY_AMOUNT0_MIN,
            PERMIT_SUPPLY_AMOUNT1_MIN
        );

        //------------------------------- Deal and approve
        deal(TOKEN_A_USDC, owner, amount0);
        deal(TOKEN_B_STBL, owner, amount1);

        vm.prank(owner);
        IERC20(TOKEN_A_USDC).approve(ROUTER_ADDR, amount0);

        vm.prank(owner);
        IERC20(TOKEN_B_STBL).approve(ROUTER_ADDR, amount1);

        //------------------------------- supply
        {
            bytes memory actionsData = _createSupplyActionData(amount0, amount1, 0, 0);
            bytes memory permitsData =
                _createSupplyPermitsData(TEST_PRIVATE_KEY, amount0, amount1, block.timestamp + 600000);

            vm.prank(owner);
            router.execute(LENDING_POOL_USDC_STBL, actionsData, permitsData);

            console.log("amount0", amount0);
            console.log("amount1", amount1);
        }

        //------------------------------- check position status
        AccountState memory stateAfterSupply = _getAccountState(owner);
        _showAccountState(stateAfterSupply);

        //------------------------------- borrow in several steps
        {
            uint snapshot = vm.snapshotState();
            for (uint i; i < 4; ++i) {
                uint amountToBorrow = 0.0275e6;
                bytes memory actionsData = _createBorrowActionData(amountToBorrow, owner);
                bytes memory permitsData =
                    _createBorrowPermitsData(TEST_PRIVATE_KEY, amountToBorrow, block.timestamp + 600000);

                vm.prank(owner);
                router.execute(LENDING_POOL_USDC_STBL, actionsData, permitsData);

                //------------------------------- check position status
                console.log("==========================", i);
                AccountState memory stateAfterBorrow = _getAccountState(owner);
                _showAccountState(stateAfterBorrow);
                console.log("==========================");
            }
            vm.revertToState(snapshot);
        }

        //------------------------------- borrow max
        {
            uint amountToBorrow = _getMaxAmountToBorrow(owner);
            console.log("amountToBorrow", amountToBorrow);
            bytes memory actionsData = _createBorrowActionData(amountToBorrow, owner);
            bytes memory permitsData =
                _createBorrowPermitsData(TEST_PRIVATE_KEY, amountToBorrow, block.timestamp + 600000);

            vm.prank(owner);
            router.execute(LENDING_POOL_USDC_STBL, actionsData, permitsData);

            //------------------------------- check position status
            AccountState memory stateAfterBorrow = _getAccountState(owner);
            _showAccountState(stateAfterBorrow);
        }
    }

    function testBorrowByTestMultisig() public {
        address owner = makeAddr("test multisig");
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        //------------------------------- Calculate desired amounts
        IImpermaxV2SolidlyRouter01 router = IImpermaxV2SolidlyRouter01(ROUTER_ADDR);
        (uint amount0, uint amount1) = router._optimalLiquidityUniV2(
            LENDING_POOL_USDC_STBL,
            PERMIT_SUPPLY_AMOUNT_USDC,
            PERMIT_SUPPLY_AMOUNT_STBL,
            PERMIT_SUPPLY_AMOUNT0_MIN,
            PERMIT_SUPPLY_AMOUNT1_MIN
        );

        //------------------------------- Deal and approve
        deal(TOKEN_A_USDC, owner, amount0);
        deal(TOKEN_B_STBL, owner, amount1);

        vm.prank(owner);
        IERC20(TOKEN_A_USDC).approve(ROUTER_ADDR, amount0);

        vm.prank(owner);
        IERC20(TOKEN_B_STBL).approve(ROUTER_ADDR, amount1);

        //------------------------------- supply
        {
            bytes memory actionsData = _createSupplyActionData(amount0, amount1, 0, 0);
            bytes memory permitsData = _createPermitsDataEmpty();

            vm.prank(owner);
            router.execute(LENDING_POOL_USDC_STBL, actionsData, permitsData);

            console.log("amount0", amount0);
            console.log("amount1", amount1);
        }

        //------------------------------- check position status
        AccountState memory stateAfterSupply = _getAccountState(owner);
        _showAccountState(stateAfterSupply);

        //------------------------------- borrow in several steps
        address borrow0 = _getTokenBorrow0(LENDING_POOL_USDC_STBL);

        {

            uint snapshot = vm.snapshotState();
            for (uint i; i < 4; ++i) {
                uint amountToBorrow = 0.0275e6;
                bytes memory actionsData = _createBorrowActionData(amountToBorrow, owner);
                bytes memory permitsData = _createPermitsDataEmpty();

                vm.prank(owner);
                IImpermaxBorrowableV2(borrow0).borrowApprove(ROUTER_ADDR, amountToBorrow);

                vm.prank(owner);
                router.execute(LENDING_POOL_USDC_STBL, actionsData, permitsData);

                //------------------------------- check position status
                console.log("==========================", i);
                AccountState memory stateAfterBorrow = _getAccountState(owner);
                _showAccountState(stateAfterBorrow);
                console.log("==========================");
            }
            vm.revertToState(snapshot);
        }

        //------------------------------- borrow max
        {
            uint amountToBorrow = _getMaxAmountToBorrow(owner);
            console.log("amountToBorrow", amountToBorrow);
            bytes memory actionsData = _createBorrowActionData(amountToBorrow, owner);
            bytes memory permitsData = _createPermitsDataEmpty();

            vm.prank(owner);
            IImpermaxBorrowableV2(borrow0).borrowApprove(ROUTER_ADDR, amountToBorrow);

            vm.prank(owner);
            router.execute(LENDING_POOL_USDC_STBL, actionsData, permitsData);

            //------------------------------- check position status
            AccountState memory stateAfterBorrow = _getAccountState(owner);
            _showAccountState(stateAfterBorrow);
        }
    }

    function testBorrowByRealMultisig() public {
        address owner = SonicConstantsLib.MULTISIG;
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        //------------------------------- check position status
        AccountState memory state0 = _getAccountState(owner);
        _showAccountState(state0);

        //------------------------------- borrow
        {
            address borrow0 = _getTokenBorrow0(LENDING_POOL_USDC_STBL);

            uint amountToBorrow = 10_000e6;
            console.log("amountToBorrow, max amount", amountToBorrow, _getMaxAmountToBorrow(owner));
            bytes memory actionsData = _createBorrowActionData(amountToBorrow, owner);
            bytes memory permitsData = _createPermitsDataEmpty();

            console.log("Action data");
            console.logBytes(actionsData);
            console.log("Permits data");
            console.logBytes(permitsData);

            vm.prank(owner);
            IImpermaxBorrowableV2(borrow0).borrowApprove(ROUTER_ADDR, amountToBorrow);

            vm.prank(owner);
            IImpermaxV2SolidlyRouter01(ROUTER_ADDR).execute(LENDING_POOL_USDC_STBL, actionsData, permitsData);

            AccountState memory stateAfterBorrow = _getAccountState(owner);
            _showAccountState(stateAfterBorrow);
        }

        //------------------------------ repay
        {
            uint amountToRepay = 10_000e6;

            bytes memory actionsData = _createRepayActionData(amountToRepay);
            bytes memory permitsData = _createPermitsDataEmpty();

            vm.prank(owner);
            IERC20(TOKEN_A_USDC).approve(ROUTER_ADDR, amountToRepay);

            vm.prank(owner);
            IImpermaxV2SolidlyRouter01(ROUTER_ADDR).execute(LENDING_POOL_USDC_STBL, actionsData, permitsData);

            AccountState memory stateAfterRepay = _getAccountState(owner);
            _showAccountState(stateAfterRepay);
        }
    }

    function testBorrowByRealMultisigUseConstData() public {
        address owner = SonicConstantsLib.MULTISIG;
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        //------------------------------- check position status
        AccountState memory state0 = _getAccountState(owner);
        _showAccountState(state0);

        //------------------------------- borrow
        {
            address borrow0 = _getTokenBorrow0(LENDING_POOL_USDC_STBL);

            uint amountToBorrow = 10_000e6;
            console.log("amountToBorrow, max amount", amountToBorrow, _getMaxAmountToBorrow(owner));
            bytes memory actionsData =
                hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002540be400000000000000000000000000f564ebac1182578398e94868bea1aba6ba3396520000000000000000000000000000000000000000000000000000000000000000";
            bytes memory permitsData =
                hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000";


//            vm.prank(owner);
//            IImpermaxBorrowableV2(borrow0).borrowApprove(ROUTER_ADDR, amountToBorrow);

            console.log("Exist borrowAllowance", IImpermaxBorrowableV2(borrow0).borrowAllowance(owner, ROUTER_ADDR));

            vm.prank(owner);
            IImpermaxV2SolidlyRouter01(ROUTER_ADDR).execute(LENDING_POOL_USDC_STBL, actionsData, permitsData);

            AccountState memory stateAfterBorrow = _getAccountState(owner);
            _showAccountState(stateAfterBorrow);
        }

        //------------------------------ repay
        {
            uint amountToRepay = 10_000e6;

            bytes memory actionsData = _createRepayActionData(amountToRepay);
            bytes memory permitsData = _createPermitsDataEmpty();

            vm.prank(owner);
            IERC20(TOKEN_A_USDC).approve(ROUTER_ADDR, amountToRepay);

            vm.prank(owner);
            IImpermaxV2SolidlyRouter01(ROUTER_ADDR).execute(LENDING_POOL_USDC_STBL, actionsData, permitsData);

            AccountState memory stateAfterRepay = _getAccountState(owner);
            _showAccountState(stateAfterRepay);
        }
    }

    //region ----------------------------------------- Internal logic

    function _showDecodedBorrowData(bytes memory actionData, bytes memory permitsData) public pure {
        {
            IImpermaxV2SolidlyRouter01.Permit[] memory permits =
                abi.decode(permitsData, (IImpermaxV2SolidlyRouter01.Permit[]));
            console.log("permits.length", permits.length); // 1
            console.log("permit[0].permitType", uint8(permits[0].permitType)); // 4 = PERMIT_BORROW

            IImpermaxV2SolidlyRouter01.Permit1Data memory decoded =
                abi.decode(permits[0].permitData, (IImpermaxV2SolidlyRouter01.Permit1Data));
            console.log("permit[0].token", decoded.token); // 0xc2285Af4F918c9bFD364Cd7a5c403fBa0f201a43 imxB
            console.log("permit[0].amount", decoded.amount); // 100000
            console.log("permit[0].deadline", decoded.deadline); // 1761568756 (= 1760966940 + 601816)
            console.logBytes(permits[0].signature);
        }

        {
            IImpermaxV2SolidlyRouter01.Action[] memory actions =
                abi.decode(actionData, (IImpermaxV2SolidlyRouter01.Action[]));
            console.log("actions.length", actions.length); // 1
            console.log("action[0].actionType", uint8(actions[0].actionType)); // 0 = BORROW

            IImpermaxV2SolidlyRouter01.BorrowData memory decoded =
                abi.decode(actions[0].actionData, (IImpermaxV2SolidlyRouter01.BorrowData));
            console.log("action[0].index", decoded.index);
            console.log("action[0].amount", decoded.amount);
            console.log("action[0].to", decoded.to);
        }
    }

    function _showDecodedSupplyData(bytes memory actionData, bytes memory permitsData) public pure {
        {
            IImpermaxV2SolidlyRouter01.Permit[] memory permits =
                abi.decode(permitsData, (IImpermaxV2SolidlyRouter01.Permit[]));
            console.log("permits.length", permits.length); // 1
            console.log("permit[0].permitType", uint8(permits[0].permitType)); // 4 = PERMIT_BORROW

            IImpermaxV2SolidlyRouter01.Permit1Data memory decoded0 =
                abi.decode(permits[0].permitData, (IImpermaxV2SolidlyRouter01.Permit1Data));
            console.log("permit[0].token", decoded0.token); // 0xc2285Af4F918c9bFD364Cd7a5c403fBa0f201a43 imxB
            console.log("permit[0].amount", decoded0.amount); // 100000
            console.log("permit[0].deadline", decoded0.deadline); // 1761568756 (= 1760966940 + 601816)
            console.logBytes(permits[0].signature);

            IImpermaxV2SolidlyRouter01.Permit1Data memory decoded1 =
                abi.decode(permits[1].permitData, (IImpermaxV2SolidlyRouter01.Permit1Data));
            console.log("permit[1].token", decoded1.token); // 0xc2285Af4F918c9bFD364Cd7a5c403fBa0f201a43 imxB
            console.log("permit[1].amount", decoded1.amount); // 100000
            console.log("permit[1].deadline", decoded1.deadline); // 1761568756 (= 1760966940 + 601816)
            console.logBytes(permits[1].signature);
        }

        {
            IImpermaxV2SolidlyRouter01.Action[] memory actions =
                abi.decode(actionData, (IImpermaxV2SolidlyRouter01.Action[]));
            console.log("actions.length", actions.length); // 1
            console.log("action[0].actionType", uint8(actions[0].actionType)); // 0 = BORROW

            IImpermaxV2SolidlyRouter01.MintUniV2Data memory decoded =
                abi.decode(actions[0].actionData, (IImpermaxV2SolidlyRouter01.MintUniV2Data));
            console.log("action[0].lpAmountUser", decoded.lpAmountUser);
            console.log("action[0].amount0Desired", decoded.amount0Desired);
            console.log("action[0].amount1Desired", decoded.amount1Desired);
            console.log("action[0].amount0Min", decoded.amount0Min);
            console.log("action[0].amount1Min", decoded.amount1Min);
        }
    }

    function _getAccountState(address user) internal returns (AccountState memory dest) {
        (IImpermaxV2SolidlyRouter01.LendingPool memory pool) =
            IImpermaxV2SolidlyRouter01(ROUTER_ADDR).getLendingPool(LENDING_POOL_USDC_STBL);
        IImpermaxCollateral collateral = IImpermaxCollateral(pool.collateral);
        (dest.liquidity, dest.shortfall) = collateral.accountLiquidity(user);

        dest.collateralAmount = collateral.balanceOf(user);
        dest.twapPrice112x112 = collateral.getTwapPrice112x112();
        dest.collateralExchangeRate = collateral.exchangeRate();

        IImpermaxBorrowableV2(pool.borrowables[0]).accrueInterest();
        dest.borrowBalance = IImpermaxBorrowableV2(pool.borrowables[0]).borrowBalance(user);
        dest.borrowExchangeRate = IImpermaxBorrowableV2(pool.borrowables[0]).exchangeRate();

        (dest.price0, dest.price1) = collateral.getPrices();

        // debtValueInCollateral = (debt0 * price0 + debt1 * price1) / 1e18
        // LTV = debtValueInCollateral / collateralBalance
        dest.debtValueInCollateral = (dest.borrowBalance * dest.price0) / 1e18;
        dest.ltv = (dest.debtValueInCollateral * 1e18) / dest.collateralAmount;

        dest.balanceUSDC = IERC20(TOKEN_A_USDC).balanceOf(user);

        return dest;
    }

    function _showAccountState(AccountState memory state) internal pure {
        console.log("liquidity", state.liquidity);
        console.log("shortfall", state.shortfall);
        console.log("collateralAmount", state.collateralAmount);
        console.log("twapPrice112x112", state.twapPrice112x112);
        console.log("collateral exchangeRate", state.collateralExchangeRate);
        console.log("borrowBalance", state.borrowBalance);
        console.log("borrow exchangeRate", state.borrowExchangeRate);
        console.log("price0", state.price0);
        console.log("price1", state.price1);
        console.log("debtValueInCollateral", state.debtValueInCollateral);
        console.log("ltv (1e18)", state.ltv);
        console.log("balanceUSDC", state.balanceUSDC);
        console.log("");
    }

    function _getMaxAmountToBorrow(address user) internal returns (uint amountToBorrow) {
        AccountState memory state = _getAccountState(user);
        return state.liquidity * 1e18 * 56 / 100 / state.price0; // todo how to calculate 56? 60.8 is max LTV
    }

    function _getTokenBorrow0(address lendingPool) internal view returns (address) {
        (IImpermaxV2SolidlyRouter01.LendingPool memory pool) =
            IImpermaxV2SolidlyRouter01(ROUTER_ADDR).getLendingPool(lendingPool);
        return pool.borrowables[0];
    }
    //endregion ----------------------------------------- Internal logic

    //region ----------------------------------------- Action data utils

    function _createBorrowActionData() internal pure returns (bytes memory actionData) {
        return _createBorrowActionData(PERMIT_AMOUNT, OWNER_ADDR);
    }

    function _createBorrowActionData(uint permitAmount, address to_) internal pure returns (bytes memory actionData) {
        IImpermaxV2SolidlyRouter01.BorrowData memory borrowData =
            IImpermaxV2SolidlyRouter01.BorrowData({index: 0, amount: permitAmount, to: to_});

        IImpermaxV2SolidlyRouter01.Action memory action = IImpermaxV2SolidlyRouter01.Action({
            actionType: IImpermaxV2SolidlyRouter01.Type.BORROW,
            actionData: abi.encode(borrowData),
            nextAction: bytes("") // No next action
        });

        IImpermaxV2SolidlyRouter01.Action[] memory actions = new IImpermaxV2SolidlyRouter01.Action[](1);
        actions[0] = action;

        return abi.encode(actions);
    }

    function _createSupplyActionData() internal pure returns (bytes memory actionData) {
        return _createSupplyActionData(
            PERMIT_SUPPLY_AMOUNT_USDC, PERMIT_SUPPLY_AMOUNT_STBL, PERMIT_SUPPLY_AMOUNT0_MIN, PERMIT_SUPPLY_AMOUNT1_MIN
        );
    }

    function _createSupplyActionData(
        uint amount0Desired,
        uint amount1Desired,
        uint amount0Min,
        uint amount1Min
    ) internal pure returns (bytes memory actionData) {
        IImpermaxV2SolidlyRouter01.MintUniV2Data memory supplyData =
            IImpermaxV2SolidlyRouter01.MintUniV2Data({
                lpAmountUser: 0,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min
            });

        IImpermaxV2SolidlyRouter01.Action memory action = IImpermaxV2SolidlyRouter01.Action({
            actionType: IImpermaxV2SolidlyRouter01.Type.MINT_UNIV2,
            actionData: abi.encode(supplyData),
            nextAction: bytes("") // No next action
        });

        IImpermaxV2SolidlyRouter01.Action[] memory actions = new IImpermaxV2SolidlyRouter01.Action[](1);
        actions[0] = action;

        return abi.encode(actions);
    }

    //endregion ----------------------------------------- Action data utils

    //region ----------------------------------------- Permit utils
    /// @notice Helper to get the correct Domain Separator
    /// NOTE: In production, the token's name must be retrieved via token.name()
    /// We use a placeholder for name and version as the exact EIP-712 setup
    /// of the token's Domain Separator is required for an exact match.
    function _getDomainSeparator(
        address token,
        string memory version_
    ) internal view returns (bytes32 domainSeparator) {
        // This is the EIP-712 Domain Separator hashing schema
        bytes32 EIP712_DOMAIN_TYPEHASH =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

        // We assume the token's name and version are constants (e.g., "IMX_TOKEN_NAME" and "1")
        // NOTE: Replace "IMX_TOKEN_NAME" with the actual token name for live testing.
        domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(IERC20Metadata(token).name())),
                keccak256(bytes(version_)),
                block.chainid,
                token
            )
        );
    }

    /// @notice Calculates the final digest (message hash) to be signed
    function _getBorrowPermitDigest(
        address token,
        address owner,
        uint value,
        uint nonce,
        uint deadline
    ) internal view returns (bytes32 digest) {
        // 1. Get Domain Separator
        bytes32 domainSeparator = _getDomainSeparator(token, "1"); // todo: USDC has version "2"

        // 2. Hash the BorrowPermit Message
        // Format: BorrowPermit(address owner, address spender, uint256 value, uint256 nonce, uint256 deadline)
        bytes32 permitHash = keccak256(
            abi.encode(
                BORROW_PERMIT_TYPEHASH,
                owner,
                ROUTER_ADDR, // Spender
                value,
                nonce,
                deadline
            )
        );

        // 3. Combine with EIP-712 prefix
        digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, permitHash));
    }

    /// @notice Creates the permitsData byte array required by the Impermax Router
    /// @param signerPrivateKey The private key ID used for vm.sign. Use 1 to simulate OWNER_ADDR + SIGNATURE_OF_OWNER
    /// @return permitsData The abi-encoded array of Permit structs
    function _createBorrowPermitsData(uint signerPrivateKey) internal view returns (bytes memory permitsData) {
        return _createBorrowPermitsData(signerPrivateKey, PERMIT_AMOUNT, DEADLINE);
    }

    function _createBorrowPermitsData(
        uint signerPrivateKey,
        uint permitAmount,
        uint deadline
    ) internal view returns (bytes memory permitsData) {
        Vm vm = Vm(address(VM_ADDRESS));

        address owner;
        if (signerPrivateKey == SIGNER_PRIVATE_KEY_888) {
            owner = OWNER_ADDR;
        } else {
            owner = vm.addr(signerPrivateKey);
        }

        // 1. Get Nonce from the token contract
        uint nonce = IERC20Permit(TOKEN_ADDR).nonces(owner);

        // 2. Calculate the Digest
        bytes32 digest = _getBorrowPermitDigest(TOKEN_ADDR, owner, permitAmount, nonce, deadline);

        // 3. Sign the Digest using Forge cheat
        bytes memory signature;
        if (signerPrivateKey == SIGNER_PRIVATE_KEY_888) {
            signature = SIGNATURE_BORROW;
        } else {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
            signature = abi.encodePacked(r, s, v);
        }

        // 4. Encode the Permit Data (for the permitData field)
        bytes memory permitData = abi.encode(TOKEN_ADDR, permitAmount, deadline);

        // 5. Assemble the Permit Structure
        IImpermaxV2SolidlyRouter01.Permit memory permit = IImpermaxV2SolidlyRouter01.Permit({
            permitType: IImpermaxV2SolidlyRouter01.PermitType.PERMIT_BORROW,
            permitData: permitData,
            signature: signature
        });

        // 6. ABI-encode the array for the Router
        IImpermaxV2SolidlyRouter01.Permit[] memory permits = new IImpermaxV2SolidlyRouter01.Permit[](1);
        permits[0] = permit;

        return abi.encode(permits);
    }

    function _createPermitsDataEmpty() internal pure returns (bytes memory permitsData) {
        IImpermaxV2SolidlyRouter01.Permit[] memory permits = new IImpermaxV2SolidlyRouter01.Permit[](0);
        return abi.encode(permits);
    }

    /// @notice Calculates the final digest (message hash) for a classic ERC20 Permit
    function _getSupplyPermitDigest(
        address token,
        address owner,
        uint value,
        uint nonce,
        uint deadline,
        string memory version_
    ) internal view returns (bytes32 digest) {
        // 1. Get Domain Separator (Assumed to be the same logic as _getDomainSeparator)
        bytes32 domainSeparator = _getDomainSeparator(token, version_);

        // 2. Hash the Permit Message (EIP-2612)
        // Format: Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)
        bytes32 permitHash = keccak256(
            abi.encode(
                SUPPLY_PERMIT_TYPEHASH,
                owner,
                ROUTER_ADDR, // Spender remains the Router
                value,
                nonce,
                deadline
            )
        );

        // 3. Combine with EIP-712 prefix
        digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, permitHash));
    }

    function _createSupplyPermitsData(uint signerPrivateKey) internal view returns (bytes memory permitsData) {
        return
            _createSupplyPermitsData(signerPrivateKey, PERMIT_SUPPLY_AMOUNT_USDC, PERMIT_SUPPLY_AMOUNT_STBL, DEADLINE);
    }

    function _createSupplyPermitsData(
        uint signerPrivateKey,
        uint amountUsd,
        uint amountStbl,
        uint deadline
    ) internal view returns (bytes memory permitsData) {
        CreateSupplyPermitsDataLocal memory local;
        Vm vm = Vm(address(VM_ADDRESS));

        address owner;
        if (signerPrivateKey == SIGNER_PRIVATE_KEY_888) {
            owner = OWNER_ADDR;
        } else {
            owner = vm.addr(signerPrivateKey);
        }

        // Initialize array for two permits
        IImpermaxV2SolidlyRouter01.Permit[] memory permits = new IImpermaxV2SolidlyRouter01.Permit[](2);

        // --- Permit 0: TOKEN_0 ---
        {
            local.token = TOKEN_A_USDC;
            local.nonce = IERC20Permit(local.token).nonces(owner);

            // Calculate Digest
            local.digest = _getSupplyPermitDigest(local.token, owner, amountUsd, local.nonce, deadline, "2");

            // Sign the Digest
            if (signerPrivateKey == SIGNER_PRIVATE_KEY_888) {
                local.signature = SIGNATURE_SUPPLY_USDC;
            } else {
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, local.digest);
                local.signature = abi.encodePacked(r, s, v);
            }

            // Assemble Permit 0
            permits[0] = IImpermaxV2SolidlyRouter01.Permit({
                permitType: IImpermaxV2SolidlyRouter01.PermitType.PERMIT1, // Type 0
                permitData: abi.encode(local.token, amountUsd, deadline),
                signature: local.signature
            });
        }

        // --- Permit 1: TOKEN_1 ---
        {
            local.token = TOKEN_B_STBL;
            local.nonce = IERC20Permit(local.token).nonces(owner);

            // Calculate Digest
            local.digest = _getSupplyPermitDigest(local.token, owner, amountStbl, local.nonce, deadline, "1");

            // Sign the Digest
            if (signerPrivateKey == SIGNER_PRIVATE_KEY_888) {
                local.signature = SIGNATURE_SUPPLY_STBL;
            } else {
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, local.digest);
                local.signature = abi.encodePacked(r, s, v);
            }

            // Assemble Permit 1
            permits[1] = IImpermaxV2SolidlyRouter01.Permit({
                permitType: IImpermaxV2SolidlyRouter01.PermitType.PERMIT1, // Type 0
                permitData: abi.encode(local.token, amountStbl, deadline),
                signature: local.signature
            });
        }

        // ABI-encode the array for the Router
        return abi.encode(permits);
    }

    function _createRepayActionData(uint repayAmount) internal pure returns (bytes memory actionData) {
        IImpermaxV2SolidlyRouter01.RepayUserData memory repayData =
            IImpermaxV2SolidlyRouter01.RepayUserData({index: 0, amountMax: repayAmount});

        IImpermaxV2SolidlyRouter01.Action memory action = IImpermaxV2SolidlyRouter01.Action({
            actionType: IImpermaxV2SolidlyRouter01.Type.REPAY_USER,
            actionData: abi.encode(repayData),
            nextAction: bytes("") // No next action
        });

        IImpermaxV2SolidlyRouter01.Action[] memory actions = new IImpermaxV2SolidlyRouter01.Action[](1);
        actions[0] = action;

        return abi.encode(actions);
    }
    //endregion ---------------------------------------- Permit utils
}
