import {VaultPriceOracle} from "../../src/core/VaultPriceOracle.sol";
import {Test, console, Vm} from "forge-std/Test.sol";
import {MockSetup} from "../base/MockSetup.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {Platform, IPlatform} from "../../src/core/Platform.sol";

contract VaultPriceOracleTest is Test, MockSetup {
    VaultPriceOracle public oracle;
    address[] public validators;
    address public vault;
    uint constant MIN_QUORUM = 3;
    uint constant MAX_PRICE_AGE = 1 hours;

    function setUp() public {
        validators = new address[](5);
        validators[0] = makeAddr("validator1");
        validators[1] = makeAddr("validator2");
        validators[2] = makeAddr("validator3");
        validators[3] = makeAddr("validator4");
        validators[4] = makeAddr("validator5");

        vault = makeAddr("vault");

        // Deploy implementation
        VaultPriceOracle implementation = new VaultPriceOracle();

        // Deploy proxy and initialize
        Proxy proxy = new Proxy();
        proxy.initProxy(address(implementation));
        oracle = VaultPriceOracle(address(proxy));
        oracle.initialize(address(platform), MIN_QUORUM, validators, MAX_PRICE_AGE);
    }

    function testInitialize() public {
        assertEq(oracle.minQuorum(), MIN_QUORUM, "Min quorum not set correctly");
        assertEq(oracle.maxPriceAge(), MAX_PRICE_AGE, "Max price age not set correctly");

        for (uint i = 0; i < validators.length; i++) {
            assertTrue(oracle.authorizedValidator(validators[i]), "Validator not authorized");
            assertEq(oracle.validatorList(i), validators[i], "Validator list incorrect");
        }

        // Test reinitialization revert
        address[] memory emptyValidators = new address[](0);
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        oracle.initialize(address(platform), MIN_QUORUM, emptyValidators, MAX_PRICE_AGE);

        // Test zero platform address revert
        VaultPriceOracle newOracle = new VaultPriceOracle();
        Proxy newProxy = new Proxy();
        newProxy.initProxy(address(newOracle));
        vm.expectRevert(IControllable.IncorrectZeroArgument.selector);
        VaultPriceOracle(address(newProxy)).initialize(address(0), MIN_QUORUM, validators, MAX_PRICE_AGE);
    }

    function testVaultPriceOracleSlot() public {
        bytes32 namespaceHash = keccak256(abi.encodePacked("erc7201:stability.VaultPriceOracle"));
        bytes32 expectedSlot = 0xa68171b251d015e5a139782486873a18b874637da10a73c080418fb52ac37300;
        bytes32 calculatedSlot = keccak256(abi.encode(uint(namespaceHash) - 1)) & ~bytes32(uint(0xff));
        assertEq(calculatedSlot, expectedSlot, "Storage slot calculation is incorrect");
    }

    function testAddAndRemoveValidator() public {
        address newValidator = makeAddr("newValidator");

        // Only governance or multisig can add
        vm.prank(makeAddr("notAuthorized"));
        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        oracle.addValidator(newValidator);

        // Add new validator
        oracle.addValidator(newValidator);
        assertTrue(oracle.authorizedValidator(newValidator), "New validator not authorized");
        assertEq(oracle.validatorList(5), newValidator, "New validator not in list");

        // Cannot add duplicate
        vm.expectRevert("Validator already authorized");
        oracle.addValidator(newValidator);

        // Only governance or multisig can remove
        vm.prank(makeAddr("notAuthorized"));
        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        oracle.removeValidator(newValidator);

        // Remove validator
        oracle.removeValidator(newValidator);
        assertFalse(oracle.authorizedValidator(newValidator), "Validator still authorized");
        assertEq(oracle.validatorListLength(), 5, "Validator list not updated");

        // Cannot remove non-existent
        vm.expectRevert("Validator not authorized");
        oracle.removeValidator(newValidator);

        // Test index out of bounds (expect revert from array out of bounds)
        vm.expectRevert();
        oracle.validatorList(5);
    }

    function testSubmitPriceAndAggregation() public {
        uint roundId = 1;
        uint[] memory prices = new uint[](5);
        prices[0] = 100;
        prices[1] = 110;
        prices[2] = 105;
        prices[3] = 120;
        prices[4] = 95;

        // Non-validator cannot submit
        vm.prank(makeAddr("notValidator"));
        vm.expectRevert("Not authorized validator");
        oracle.submitPrice(vault, 100, roundId);

        // Submit with wrong roundId
        vm.prank(validators[0]);
        vm.expectRevert("Invalid roundId");
        oracle.submitPrice(vault, 100, roundId + 1);

        // Submit prices from first 2 validators (below quorum)
        vm.prank(validators[0]);
        oracle.submitPrice(vault, prices[0], roundId);
        vm.prank(validators[1]);
        oracle.submitPrice(vault, prices[1], roundId);

        // No aggregation yet
        vm.expectRevert("No data available");
        oracle.getLatestPrice(vault);

        // Submit 3rd to reach quorum
        vm.recordLogs();
        vm.prank(validators[2]);
        oracle.submitPrice(vault, prices[2], roundId);

        // Aggregation happened: median of [100,110,105] sorted [100,105,110] -> 105
        (uint price, uint timestamp, uint rId) = oracle.getLatestPrice(vault);
        assertEq(price, 105, "Incorrect median price");
        assertEq(timestamp, block.timestamp, "Incorrect timestamp");
        assertEq(rId, 2, "Incorrect roundId");

        // Check PriceSubmitted and PriceUpdated events
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool priceSubmitted = false;
        bool priceUpdated = false;
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("PriceSubmitted(address,address,uint256,uint256)")) {
                assertEq(address(uint160(uint(entries[i].topics[1]))), vault);
                assertEq(address(uint160(uint(entries[i].topics[2]))), validators[2]);
                (uint submittedPrice, uint submittedRound) = abi.decode(entries[i].data, (uint, uint));
                assertEq(submittedPrice, prices[2]);
                assertEq(submittedRound, roundId);
                priceSubmitted = true;
            }
            if (entries[i].topics[0] == keccak256("PriceUpdated(address,uint256,uint256,uint256)")) {
                assertEq(address(uint160(uint(entries[i].topics[1]))), vault);
                (uint updatedPrice, uint updatedRound, uint updatedTimestamp) =
                    abi.decode(entries[i].data, (uint, uint, uint));
                assertEq(updatedPrice, 105);
                assertEq(updatedRound, roundId);
                assertEq(updatedTimestamp, block.timestamp);
                priceUpdated = true;
            }
        }
        assertTrue(priceSubmitted, "PriceSubmitted event not emitted");
        assertTrue(priceUpdated, "PriceUpdated event not emitted");

        // Test multiple submissions (no protection in contract)
        vm.prank(validators[0]);
        oracle.submitPrice(vault, 999, roundId + 1); // Overwrites previous submission
        (uint overwrittenPrice, uint overwrittenTimestamp) = oracle.observations(vault, roundId + 1, validators[0]);
        assertEq(overwrittenPrice, 999, "Price not overwritten");
        assertEq(overwrittenTimestamp, block.timestamp, "Timestamp not updated");
    }

    // New test to debug median calculation
    function testMedianCalculation() public {
        uint roundId = 1;
        // Submit prices: [100, 110, 105]
        vm.prank(validators[0]);
        oracle.submitPrice(vault, 100, roundId);
        vm.prank(validators[1]);
        oracle.submitPrice(vault, 110, roundId);
        vm.prank(validators[2]);
        oracle.submitPrice(vault, 105, roundId);

        // Check aggregated price
        (uint price,, uint newRoundId) = oracle.getLatestPrice(vault);
        console.log("Median price:", price);
        assertEq(price, 105, "Incorrect median for [100,110,105]");

        // Even number: [95,105,110]
        vm.prank(validators[0]);
        oracle.submitPrice(vault, 95, newRoundId);
        vm.prank(validators[1]);
        oracle.submitPrice(vault, 100, newRoundId);
        vm.prank(validators[1]);
        oracle.submitPrice(vault, 105, newRoundId);
        vm.prank(validators[3]);
        oracle.submitPrice(vault, 110, newRoundId);

        (price,,) = oracle.getLatestPrice(vault);
        console.log("Median price for even:", price);
        assertEq(price, 105, "Incorrect median for [95,105,110]");
    }

    function testGetLatestPrice() public {
        // No data yet
        vm.expectRevert("No data available");
        oracle.getLatestPrice(vault);

        // Submit and aggregate
        testSubmitPriceAndAggregation();

        (uint price, uint timestamp, uint rId) = oracle.getLatestPrice(vault);
        assertEq(price, 105, "Incorrect price");
        assertEq(rId, 2, "Incorrect roundId");

        // Warp time to make price stale
        vm.warp(block.timestamp + MAX_PRICE_AGE + 1);
        vm.expectRevert("Price too old");
        oracle.getLatestPrice(vault);
    }

    function testVaultPrices() public {
        // No data yet
        (uint price, uint timestamp, uint rId) = oracle.vaultPrices(vault);
        assertEq(price, 0, "Price should be 0");
        assertEq(timestamp, 0, "Timestamp should be 0");
        assertEq(rId, 0, "RoundId should be 0");

        // Submit and aggregate
        testSubmitPriceAndAggregation();

        (price, timestamp, rId) = oracle.vaultPrices(vault);
        assertEq(price, 105, "Incorrect price");
        assertEq(timestamp, block.timestamp, "Incorrect timestamp");
        assertEq(rId, 2, "Incorrect roundId");
    }

    function testObservations() public {
        uint roundId = 1;
        uint price = 100;
        vm.prank(validators[0]);
        oracle.submitPrice(vault, price, roundId);

        (uint observedPrice, uint observedTimestamp) = oracle.observations(vault, roundId, validators[0]);
        assertEq(observedPrice, price, "Incorrect observed price");
        assertEq(observedTimestamp, block.timestamp, "Incorrect observation timestamp");
    }

    function testAuthorizedValidator() public {
        assertTrue(oracle.authorizedValidator(validators[0]), "Validator not authorized");
        assertFalse(oracle.authorizedValidator(makeAddr("notValidator")), "Non-validator authorized");
    }

    function testValidatorList() public {
        assertEq(oracle.validatorList(0), validators[0], "Validator list incorrect");
        vm.expectRevert("Index out of bounds");
        oracle.validatorList(5);
    }

    function testMinQuorum() public {
        assertEq(oracle.minQuorum(), MIN_QUORUM, "Min quorum incorrect");
    }

    function testMaxPriceAge() public {
        assertEq(oracle.maxPriceAge(), MAX_PRICE_AGE, "Max price age incorrect");
    }

    function testRequireValidator() public {
        // Non-validator
        vm.prank(makeAddr("notValidator"));
        vm.expectRevert("Not authorized validator");
        oracle.submitPrice(vault, 100, 1);

        // Validator
        vm.prank(validators[0]);
        oracle.submitPrice(vault, 100, 1); // Should not revert
    }
}
