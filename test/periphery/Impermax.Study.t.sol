// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {IImpermaxV2SolidlyRouter01} from "../../src/integrations/impermax/IImpermaxV2SolidlyRouter01.sol";
import {IImpermaxBorrowableV2} from "../../src/integrations/impermax/IImpermaxBorrowableV2.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Permit} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

/// @dev Borrow tx: https://sonicscan.org/tx/0x4486f0cc158d7ada27a5f72dc4a8cfbe0ab5b73329298e6be20b65ced28ec5a4
/// @dev Supply tx: https://sonicscan.org/tx/0x60a9a6447befa55d47eecf0dd5737768e824cd6a51231c79800d893dee2863b1
contract ImpermaxStudySonicTest is Test {
    uint internal constant FORK_BLOCK = 52025575; // Oct-27-2025 09:42:56 AM +UTC

    uint internal constant FORK_BORROW_TX_BLOCK = 51314094; // Oct-20-2025 01:29:00 PM UTC
    uint internal constant FORK_SUPPLY_TX_BLOCK = 51314070; // Oct-20-2025 01:28:30 PM UTC

    address internal constant LENDING_POOL_USDC_STBL = 0x7195d62a9e388ae21c7881ca29be8fadeb09379f;

    bytes internal constant BORROW_ACTION_DATA = hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000186a000000000000000000000000088888887c3ebd4a33e34a15db4254c74c75e5d4a0000000000000000000000000000000000000000000000000000000000000000";
    bytes internal constant BORROW_PERMITS_DATA = hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000060000000000000000000000000c2285af4f918c9bfd364cd7a5c403fba0f201a4300000000000000000000000000000000000000000000000000000000000186a00000000000000000000000000000000000000000000000000000000068ff67f400000000000000000000000000000000000000000000000000000000000000412d4498afde7893618241e30b773d1a883de0437dbf8988eab1fae343b8ba3703662e80e32503daf94b88c96e4b92cba9e20183940a0d3c668aa720c9a17fc6861b00000000000000000000000000000000000000000000000000000000000000";

    bytes internal constant SUPPLY_ACTION_DATA = hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000186a0000000000000000000000000000000000000000000000000092056aa1dd29836000000000000000000000000000000000000000000000000000000000000c35000000000000000000000000000000000000000000000000004902b550ee94c1b0000000000000000000000000000000000000000000000000000000000000000";
    bytes internal constant SUPPLY_PERMITS_DATA = hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000006000000000000000000000000029219dd400f2bf60e5a23d13be72b486d403889400000000000000000000000000000000000000000000000000000000000186a00000000000000000000000000000000000000000000000000000000068ff67f40000000000000000000000000000000000000000000000000000000000000041a843b54a3c3f8b760c534f1afa4de2799ed80ce51ee8bb16bd17f99f4dade13834879f4bcf6e833f826c3c5227ea19ede6a19cb3c1b3f7e277e72c73d8ca324e1b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000006000000000000000000000000078a76316f66224cbaca6e70acb24d5ee5b2bd2c7000000000000000000000000000000000000000000000000092056aa1dd298360000000000000000000000000000000000000000000000000000000068ff67f4000000000000000000000000000000000000000000000000000000000000004144526f83431c213b44290e7ebe8fe7be5afb255a1930cd304b2cd7efbe6775b03be2ca7b740c515ac4b087e381f03d5aabe6c841e3fbe4644b26e06ad9dd4e521b00000000000000000000000000000000000000000000000000000000000000";

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
    bytes32 internal constant BORROW_PERMIT_TYPEHASH = keccak256(abi.encodePacked("BorrowPermit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"));

    /// @dev SupplyPermit TypeHash from the original JS helper
    bytes32 internal constant SUPPLY_PERMIT_TYPEHASH = keccak256(abi.encodePacked("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"));

    bytes internal constant SIGNATURE_BORROW = hex"2d4498afde7893618241e30b773d1a883de0437dbf8988eab1fae343b8ba3703662e80e32503daf94b88c96e4b92cba9e20183940a0d3c668aa720c9a17fc6861b";

    bytes internal constant SIGNATURE_SUPPLY_USDC = hex"a843b54a3c3f8b760c534f1afa4de2799ed80ce51ee8bb16bd17f99f4dade13834879f4bcf6e833f826c3c5227ea19ede6a19cb3c1b3f7e277e72c73d8ca324e1b";
    bytes internal constant SIGNATURE_SUPPLY_STBL = hex"44526f83431c213b44290e7ebe8fe7be5afb255a1930cd304b2cd7efbe6775b03be2ca7b740c515ac4b087e381f03d5aabe6c841e3fbe4644b26e06ad9dd4e521b";

    uint internal constant TEST_PRIVATE_KEY = 1;

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

        _showDecodedSupplyData(
            SUPPLY_ACTION_DATA,
            SUPPLY_PERMITS_DATA
        );

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
        bytes memory permitsData = _createBorrowPermitsData(1);

        // ---------------------- ensure that we get same data as original tx
        assertEq(actionData, BORROW_ACTION_DATA, "borrow action data");
        assertEq(permitsData, BORROW_PERMITS_DATA, "borrow supply data");
    }

    function testGenerateDataForSupplyTx() public {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_SUPPLY_TX_BLOCK));

        // ---------------------- create actionData and permitsData
        bytes memory actionData = _createSupplyActionData();
        bytes memory permitsData = _createSupplyPermitsData(1);

        // ---------------------- ensure that we get same data as original tx
        assertEq(actionData, SUPPLY_ACTION_DATA, "supply action data");
        assertEq(permitsData, SUPPLY_PERMITS_DATA, "supply permits data");
    }

    function testBorrow() public {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        address owner = vm.addr(TEST_PRIVATE_KEY);

        //------------------------------- Calculate desired amounts
        IImpermaxV2SolidlyRouter01 router = IImpermaxV2SolidlyRouter01(ROUTER_ADDR);
        (uint256 amount0, uint256 amount1) = router._optimalLiquidityUniV2(
            LENDING_POOL_USDC_STBL,
            PERMIT_SUPPLY_AMOUNT_USDC,
            PERMIT_SUPPLY_AMOUNT_STBL,
            PERMIT_SUPPLY_AMOUNT0_MIN,
            PERMIT_SUPPLY_AMOUNT1_MIN
        );

        //------------------------------- Deal and approve
        deal(TOKEN_A_USDC, owner, amount0);
        deal(TOKEN_B_STBL, owner, amount1);

        vm.startPrank(owner);
        IERC20(TOKEN_A_USDC).approve(ROUTER_ADDR, amount0);

        vm.startPrank(owner);
        IERC20(TOKEN_B_STBL).approve(ROUTER_ADDR, amount1);

        //------------------------------- supply

    }

    //region ----------------------------------------- Internal logic

    function _showDecodedBorrowData(bytes memory actionData, bytes memory permitsData) public {
        {
            IImpermaxV2SolidlyRouter01.Permit[] memory permits = abi.decode(permitsData, (IImpermaxV2SolidlyRouter01.Permit[]));
            console.log("permits.length", permits.length); // 1
            console.log("permit[0].permitType", uint8(permits[0].permitType)); // 4 = PERMIT_BORROW

            IImpermaxV2SolidlyRouter01.Permit1Data memory decoded = abi.decode(permits[0].permitData, (IImpermaxV2SolidlyRouter01.Permit1Data));
            console.log("permit[0].token", decoded.token); // 0xc2285Af4F918c9bFD364Cd7a5c403fBa0f201a43 imxB
            console.log("permit[0].amount", decoded.amount); // 100000
            console.log("permit[0].deadline", decoded.deadline); // 1761568756 (= 1760966940 + 601816)
            console.logBytes(permits[0].signature);
        }

        {
            IImpermaxV2SolidlyRouter01.Action[] memory actions = abi.decode(actionData, (IImpermaxV2SolidlyRouter01.Action[]));
            console.log("actions.length", actions.length); // 1
            console.log("action[0].actionType", uint8(actions[0].actionType)); // 0 = BORROW

            IImpermaxV2SolidlyRouter01.BorrowData memory decoded = abi.decode(actions[0].actionData, (IImpermaxV2SolidlyRouter01.BorrowData));
            console.log("action[0].index", decoded.index);
            console.log("action[0].amount", decoded.amount);
            console.log("action[0].to", decoded.to);
        }

    }

    function _showDecodedSupplyData(bytes memory actionData, bytes memory permitsData) public {
        {
            IImpermaxV2SolidlyRouter01.Permit[] memory permits = abi.decode(permitsData, (IImpermaxV2SolidlyRouter01.Permit[]));
            console.log("permits.length", permits.length); // 1
            console.log("permit[0].permitType", uint8(permits[0].permitType)); // 4 = PERMIT_BORROW

            IImpermaxV2SolidlyRouter01.Permit1Data memory decoded0 = abi.decode(permits[0].permitData, (IImpermaxV2SolidlyRouter01.Permit1Data));
            console.log("permit[0].token", decoded0.token); // 0xc2285Af4F918c9bFD364Cd7a5c403fBa0f201a43 imxB
            console.log("permit[0].amount", decoded0.amount); // 100000
            console.log("permit[0].deadline", decoded0.deadline); // 1761568756 (= 1760966940 + 601816)
            console.logBytes(permits[0].signature);

            IImpermaxV2SolidlyRouter01.Permit1Data memory decoded1 = abi.decode(permits[1].permitData, (IImpermaxV2SolidlyRouter01.Permit1Data));
            console.log("permit[1].token", decoded1.token); // 0xc2285Af4F918c9bFD364Cd7a5c403fBa0f201a43 imxB
            console.log("permit[1].amount", decoded1.amount); // 100000
            console.log("permit[1].deadline", decoded1.deadline); // 1761568756 (= 1760966940 + 601816)
            console.logBytes(permits[1].signature);
        }

        {
            IImpermaxV2SolidlyRouter01.Action[] memory actions = abi.decode(actionData, (IImpermaxV2SolidlyRouter01.Action[]));
            console.log("actions.length", actions.length); // 1
            console.log("action[0].actionType", uint8(actions[0].actionType)); // 0 = BORROW

            IImpermaxV2SolidlyRouter01.MintUniV2Data memory decoded = abi.decode(actions[0].actionData, (IImpermaxV2SolidlyRouter01.MintUniV2Data));
            console.log("action[0].lpAmountUser", decoded.lpAmountUser);
            console.log("action[0].amount0Desired", decoded.amount0Desired);
            console.log("action[0].amount1Desired", decoded.amount1Desired);
            console.log("action[0].amount0Min", decoded.amount0Min);
            console.log("action[0].amount1Min", decoded.amount1Min);
        }

    }
    //endregion ----------------------------------------- Internal logic

    //region ----------------------------------------- Action data utils

    function _createBorrowActionData() internal pure returns (bytes memory actionData) {
        IImpermaxV2SolidlyRouter01.BorrowData memory borrowData = IImpermaxV2SolidlyRouter01.BorrowData({
            index: 0,
            amount: PERMIT_AMOUNT,
            to: OWNER_ADDR
        });

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
        IImpermaxV2SolidlyRouter01.MintUniV2Data memory supplyData = IImpermaxV2SolidlyRouter01.MintUniV2Data({
            lpAmountUser: 0,
            amount0Desired: PERMIT_SUPPLY_AMOUNT_USDC,
            amount1Desired: PERMIT_SUPPLY_AMOUNT_STBL,
            amount0Min: PERMIT_SUPPLY_AMOUNT0_MIN,
            amount1Min: PERMIT_SUPPLY_AMOUNT1_MIN
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
    function _getDomainSeparator(address token) internal view returns (bytes32 domainSeparator) {
        // This is the EIP-712 Domain Separator hashing schema
        bytes32 EIP712_DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

        // We assume the token's name and version are constants (e.g., "IMX_TOKEN_NAME" and "1")
        // NOTE: Replace "IMX_TOKEN_NAME" with the actual token name for live testing.
        domainSeparator = keccak256(abi.encode(
            EIP712_DOMAIN_TYPEHASH,
            keccak256(bytes("IMX_TOKEN_NAME")),
            keccak256(bytes("1")),
            block.chainid,
            token
        ));
    }

    /// @notice Calculates the final digest (message hash) to be signed
    function _getBorrowPermitDigest(
        address token,
        address owner,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32 digest) {
        // 1. Get Domain Separator
        bytes32 domainSeparator = _getDomainSeparator(token);

        // 2. Hash the BorrowPermit Message
        // Format: BorrowPermit(address owner, address spender, uint256 value, uint256 nonce, uint256 deadline)
        bytes32 permitHash = keccak256(abi.encode(
            BORROW_PERMIT_TYPEHASH,
            owner,
            ROUTER_ADDR, // Spender
            value,
            nonce,
            deadline
        ));

        // 3. Combine with EIP-712 prefix
        digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            permitHash
        ));
    }

    /// @notice Creates the permitsData byte array required by the Impermax Router
    /// @param signerPrivateKey The private key ID used for vm.sign. Use 1 to simulate OWNER_ADDR + SIGNATURE_OF_OWNER
    /// @return permitsData The abi-encoded array of Permit structs
    function _createBorrowPermitsData(uint256 signerPrivateKey) internal view returns (bytes memory permitsData) {
        Vm vm = Vm(address(0x7109709eCFAA0d3ae091f80bC988a967c2Ae4807)); // reserved magic address to access VM cheatcodes

        address owner;
        if (signerPrivateKey == 1) {
            owner = OWNER_ADDR;
        } else {
            owner = vm.addr(signerPrivateKey);
        }

        // 1. Get Nonce from the token contract
        uint256 nonce = IERC20Permit(TOKEN_ADDR).nonces(owner);

        // 2. Calculate the Digest
        bytes32 digest = _getBorrowPermitDigest(
            TOKEN_ADDR,
            owner,
            PERMIT_AMOUNT,
            nonce,
            DEADLINE
        );

        // 3. Sign the Digest using Forge cheat
        bytes memory signature;
        if (signerPrivateKey == 1) {
            signature = SIGNATURE_BORROW;
        } else {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
            signature = abi.encodePacked(r, s, v);
        }

        // 4. Encode the Permit Data (for the permitData field)
        bytes memory permitData = abi.encode(TOKEN_ADDR, PERMIT_AMOUNT, DEADLINE);

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

    /// @notice Calculates the final digest (message hash) for a classic ERC20 Permit
    function _getSupplyPermitDigest(
        address token,
        address owner,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32 digest) {
        // 1. Get Domain Separator (Assumed to be the same logic as _getDomainSeparator)
        bytes32 domainSeparator = _getDomainSeparator(token);

        // 2. Hash the Permit Message (EIP-2612)
        // Format: Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)
        bytes32 permitHash = keccak256(abi.encode(
            SUPPLY_PERMIT_TYPEHASH,
            owner,
            ROUTER_ADDR, // Spender remains the Router
            value,
            nonce,
            deadline
        ));

        // 3. Combine with EIP-712 prefix
        digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            permitHash
        ));
    }

    function _createSupplyPermitsData(uint256 signerPrivateKey) internal view returns (bytes memory permitsData) {
        Vm vm = Vm(address(0x7109709eCFAA0d3ae091f80bC988a967c2Ae4807));

        address owner;
        if (signerPrivateKey == 1) {
            owner = OWNER_ADDR;
        } else {
            owner = vm.addr(signerPrivateKey);
        }

        // Initialize array for two permits
        IImpermaxV2SolidlyRouter01.Permit[] memory permits = new IImpermaxV2SolidlyRouter01.Permit[](2);

        // --- Permit 0: TOKEN_0 ---
        {
            address token = TOKEN_A_USDC;
            uint256 value = PERMIT_SUPPLY_AMOUNT_USDC;
            uint256 nonce = IERC20Permit(token).nonces(owner);

            // Calculate Digest
            bytes32 digest = _getSupplyPermitDigest(token, owner, value, nonce, DEADLINE);

            // Sign the Digest
            bytes memory signature;
            if (signerPrivateKey == 1) {
                signature = SIGNATURE_SUPPLY_USDC;
            } else {
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
            }

            // Assemble Permit 0
            permits[0] = IImpermaxV2SolidlyRouter01.Permit({
                permitType: IImpermaxV2SolidlyRouter01.PermitType.PERMIT1, // Type 0
                permitData: abi.encode(token, value, DEADLINE),
                signature: signature
            });
        }

        // --- Permit 1: TOKEN_1 ---
        {
            address token = TOKEN_B_STBL;
            uint256 value = PERMIT_SUPPLY_AMOUNT_STBL;
            uint256 nonce = IERC20Permit(token).nonces(owner);

            // Calculate Digest
            bytes32 digest = _getSupplyPermitDigest(token, owner, value, nonce, DEADLINE);

            // Sign the Digest
            bytes memory signature;
            if (signerPrivateKey == 1) {
                signature = SIGNATURE_SUPPLY_STBL;
            } else {
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
            }

            // Assemble Permit 1
            permits[1] = IImpermaxV2SolidlyRouter01.Permit({
                permitType: IImpermaxV2SolidlyRouter01.PermitType.PERMIT1, // Type 0
                permitData: abi.encode(token, value, DEADLINE),
                signature: signature
            });
        }

        // ABI-encode the array for the Router
        return abi.encode(permits);
    }
    //endregion ---------------------------------------- Permit utils
}
