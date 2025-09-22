// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IControllable} from "../../src/core/base/Controllable.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IVaultPriceOracle} from "../../src/interfaces/IVaultPriceOracle.sol";
import {MockSetup} from "../base/MockSetup.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {Test, console, Vm} from "forge-std/Test.sol";
import {VaultPriceOracle} from "../../src/core/VaultPriceOracle.sol";

contract VaultPriceOracleTest is Test, MockSetup {
    VaultPriceOracle public oracle;
    address[] public validators;
    address[] public vaults;
    uint[] public thresholds;
    uint[] public staleness;
    address public vault;
    address public multisig;
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
        vaults = new address[](1);
        vaults[0] = vault;
        thresholds = new uint[](1);
        thresholds[0] = 1; // 1% price change threshold
        staleness = new uint[](1);
        staleness[0] = 1 days; // 1 day staleness
        multisig = makeAddr("multisig");

        // Deploy implementation
        VaultPriceOracle implementation = new VaultPriceOracle();

        // Deploy proxy
        Proxy proxy = new Proxy();
        proxy.initProxy(address(implementation));
        oracle = VaultPriceOracle(address(proxy));

        // Mock platform calls before initialize
        vm.mockCall(address(platform), abi.encodeWithSelector(IPlatform.multisig.selector), abi.encode(multisig));
        vm.mockCall(
            address(platform),
            abi.encodeWithSelector(IPlatform.governance.selector),
            abi.encode(address(this)) // Governance is test contract
        );

        // Initialize
        oracle.initialize(address(platform));

        oracle.setMaxPriceAge(MAX_PRICE_AGE);
        oracle.setMinQuorum(MIN_QUORUM);
        for (uint i = 0; i < validators.length; i++) {
            oracle.addValidator(validators[i]);
        }
        for (uint i = 0; i < vaults.length; i++) {
            oracle.addVault(vaults[i], thresholds[i], staleness[i]);
        }

        // Mock platform() for subsequent calls
        vm.mockCall(
            address(oracle), abi.encodeWithSelector(IControllable.platform.selector), abi.encode(address(platform))
        );
    }

    function testInitialize() public {
        assertEq(oracle.minQuorum(), MIN_QUORUM, "Min quorum not set correctly");
        assertEq(oracle.maxPriceAge(), MAX_PRICE_AGE, "Max price age not set correctly");

        // Check validators
        for (uint i = 0; i < validators.length; i++) {
            assertTrue(oracle.authorizedValidator(validators[i]), "Validator not authorized");
            assertEq(oracle.validatorByIndex(i), validators[i], "Validator list incorrect");
        }

        // Check vaults
        assertEq(oracle.vaultByIndex(0), vaults[0], "Vault list incorrect");
        assertEq(oracle.vaultsLength(), 1, "Vault list length incorrect");

        // Test reinitialization revert
        address[] memory emptyValidators = new address[](0);
        address[] memory emptyVaults = new address[](0);
        uint[] memory emptyThresholds = new uint[](0);
        uint[] memory emptyStaleness = new uint[](0);
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        oracle.initialize(address(platform));

        oracle.setMaxPriceAge(MAX_PRICE_AGE);
        oracle.setMinQuorum(MIN_QUORUM);
        for (uint i = 0; i < emptyValidators.length; i++) {
            oracle.addValidator(emptyValidators[i]);
        }
        for (uint i = 0; i < emptyVaults.length; i++) {
            oracle.addVault(emptyVaults[i], emptyThresholds[i], emptyStaleness[i]);
        }

        // Test zero platform address revert
        VaultPriceOracle newOracle = new VaultPriceOracle();
        Proxy newProxy = new Proxy();
        newProxy.initProxy(address(newOracle));
        vm.expectRevert(IControllable.IncorrectZeroArgument.selector);
        VaultPriceOracle(address(newProxy)).initialize(address(0));
    }

    function testAddAndRemoveValidator() public {
        address newValidator = makeAddr("newValidator");

        // Only governance or multisig can add
        vm.prank(makeAddr("notAuthorized"));
        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        oracle.addValidator(newValidator);

        // Add new validator
        vm.recordLogs();
        vm.prank(address(this));
        oracle.addValidator(newValidator);
        assertTrue(oracle.authorizedValidator(newValidator), "New validator not authorized");
        assertEq(oracle.validatorByIndex(5), newValidator, "New validator not in list");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool validatorAdded = false;
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("ValidatorAdded(address)")) {
                assertEq(address(uint160(uint(entries[i].topics[1]))), newValidator);
                validatorAdded = true;
            }
        }
        assertTrue(validatorAdded, "ValidatorAdded event not emitted");

        // Add as multisig
        vm.prank(multisig);
        address anotherValidator = makeAddr("anotherValidator");
        oracle.addValidator(anotherValidator);
        assertTrue(oracle.authorizedValidator(anotherValidator), "Multisig add failed");
        assertEq(oracle.validatorByIndex(6), anotherValidator, "Another validator not in list");

        // Cannot add duplicate
        vm.prank(address(this));
        vm.expectRevert(IVaultPriceOracle.ValidatorAlreadyAuthorized.selector);
        oracle.addValidator(newValidator);

        // Only governance or multisig can remove
        vm.prank(makeAddr("notAuthorized"));
        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        oracle.removeValidator(newValidator);

        // Remove validator
        vm.recordLogs();
        vm.prank(address(this));
        oracle.removeValidator(newValidator);
        assertFalse(oracle.authorizedValidator(newValidator), "Validator still authorized");
        bool found = false;
        for (uint i = 0; i < 6; i++) {
            // 5 initial + 1 added
            if (oracle.validatorByIndex(i) == newValidator) {
                found = true;
            }
        }
        assertFalse(found, "Removed validator still in list");
        entries = vm.getRecordedLogs();
        bool validatorRemoved = false;
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("ValidatorRemoved(address)")) {
                assertEq(address(uint160(uint(entries[i].topics[1]))), newValidator);
                validatorRemoved = true;
            }
        }
        assertTrue(validatorRemoved, "ValidatorRemoved event not emitted");

        // Cannot remove non-existent
        vm.prank(address(this));
        vm.expectRevert(IVaultPriceOracle.NotAuthorizedValidator.selector);
        oracle.removeValidator(newValidator);

        // Test index out of bounds
        vm.expectRevert(IVaultPriceOracle.IndexOutOfBounds.selector);
        oracle.validatorByIndex(7);

        // Remove all validators
        for (uint i = 0; i < 6; i++) {
            vm.prank(address(this));
            oracle.removeValidator(oracle.validatorByIndex(0)); // Always remove the first one
        }

        // check that no validators remain
        assertEq(oracle.validatorsLength(), 0, "Not all validators removed");
    }

    function testAddAndRemoveVault() public {
        address newVault = makeAddr("newVault");
        uint newPriceThreshold = 2; // 2% price change threshold
        uint newStaleness = 2 days; // 2 days staleness

        // Only governance or multisig can add
        vm.prank(makeAddr("notAuthorized"));
        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        oracle.addVault(newVault, newPriceThreshold, newStaleness);

        // Add new vault
        vm.recordLogs();
        vm.prank(address(this));
        oracle.addVault(newVault, newPriceThreshold, newStaleness);
        assertEq(oracle.vaultByIndex(1), newVault, "New vault not in list");
        assertEq(oracle.vaultsLength(), 2, "Vault list length incorrect");
        (uint priceThreshold, uint stalenessValue) = oracle.vaultData(newVault);
        assertEq(priceThreshold, newPriceThreshold, "Incorrect price threshold for new vault");
        assertEq(stalenessValue, newStaleness, "Incorrect staleness for new vault");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool vaultAdded = false;
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("VaultAdded(address)")) {
                assertEq(address(uint160(uint(entries[i].topics[1]))), newVault);
                vaultAdded = true;
            }
        }
        assertTrue(vaultAdded, "VaultAdded event not emitted");

        // Add as multisig
        vm.prank(multisig);
        address anotherVault = makeAddr("anotherVault");
        oracle.addVault(anotherVault, 3, 3 days);
        assertEq(oracle.vaultByIndex(2), anotherVault, "Another vault not in list");
        (priceThreshold, stalenessValue) = oracle.vaultData(anotherVault);
        assertEq(priceThreshold, 3, "Incorrect price threshold for another vault");
        assertEq(stalenessValue, 3 days, "Incorrect staleness for another vault");

        // Cannot add zero address
        vm.prank(address(this));
        vm.expectRevert(IVaultPriceOracle.InvalidVaultAddress.selector);
        oracle.addVault(address(0), newPriceThreshold, newStaleness);

        // Only governance or multisig can remove
        vm.prank(makeAddr("notAuthorized"));
        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        oracle.removeVault(newVault);

        // Remove vault
        vm.recordLogs();
        vm.prank(address(this));
        oracle.removeVault(newVault);
        bool found = false;
        for (uint i = 0; i < oracle.vaultsLength(); i++) {
            if (oracle.vaultByIndex(i) == newVault) {
                found = true;
            }
        }
        assertFalse(found, "Removed vault still in list");
        assertEq(oracle.vaultsLength(), 2, "Vault list length incorrect");
        (priceThreshold, stalenessValue) = oracle.vaultData(newVault);
        assertEq(priceThreshold, 0, "Vault data not cleared: priceThreshold");
        assertEq(stalenessValue, 0, "Vault data not cleared: staleness");
        entries = vm.getRecordedLogs();
        bool vaultRemoved = false;
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("VaultRemoved(address)")) {
                assertEq(address(uint160(uint(entries[i].topics[1]))), newVault);
                vaultRemoved = true;
            }
        }
        assertTrue(vaultRemoved, "VaultRemoved event not emitted");

        // Cannot remove zero address
        vm.prank(address(this));
        vm.expectRevert(IVaultPriceOracle.InvalidVaultAddress.selector);
        oracle.removeVault(address(0));

        // Cannot remove non-existent vault
        vm.prank(address(this));
        vm.expectRevert(IVaultPriceOracle.VaultNotFound.selector);
        oracle.removeVault(makeAddr("nonExistentVault"));

        // Remove all vaults
        for (uint i = 0; i < 2; i++) {
            vm.prank(address(this));
            oracle.removeVault(oracle.vaultByIndex(0)); // Always remove the first one
        }
        // check that no vaults remain
        assertEq(oracle.vaultsLength(), 0, "Not all vaults removed");
    }

    function testSetMinQuorum() public {
        // Only governance or multisig can set
        vm.prank(makeAddr("notAuthorized"));
        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        oracle.setMinQuorum(5);

        // Set new minQuorum
        vm.prank(address(this));
        oracle.setMinQuorum(5);
        assertEq(oracle.minQuorum(), 5, "Min quorum not updated");

        // Cannot set to zero
        vm.prank(address(this));
        vm.expectRevert(IVaultPriceOracle.MinQuorumMustBeGreaterThanZero.selector);
        oracle.setMinQuorum(0);

        // Set as multisig
        vm.prank(multisig);
        oracle.setMinQuorum(4);
        assertEq(oracle.minQuorum(), 4, "Min quorum not updated by multisig");
    }

    function testSetMaxPriceAge() public {
        // Only governance or multisig can set
        vm.prank(makeAddr("notAuthorized"));
        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        oracle.setMaxPriceAge(2 hours);

        // Set new maxPriceAge
        vm.prank(address(this));
        oracle.setMaxPriceAge(2 hours);
        assertEq(oracle.maxPriceAge(), 2 hours, "Max price age not updated");

        // Cannot set to zero
        vm.prank(address(this));
        vm.expectRevert(IVaultPriceOracle.MaxPriceAgeMustBeGreaterThanZero.selector);
        oracle.setMaxPriceAge(0);

        // Set as multisig
        vm.prank(multisig);
        oracle.setMaxPriceAge(3 hours);
        assertEq(oracle.maxPriceAge(), 3 hours, "Max price age not updated by multisig");
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
        vm.expectRevert(IVaultPriceOracle.NotAuthorizedValidator.selector);
        oracle.submitPrice(vault, 100, roundId);

        // Submit with wrong roundId
        vm.prank(validators[0]);
        vm.expectRevert(IVaultPriceOracle.InvalidRoundId.selector);
        oracle.submitPrice(vault, 100, roundId + 1);

        // Submit prices from first 2 validators (below quorum)
        vm.prank(validators[0]);
        oracle.submitPrice(vault, prices[0], roundId);
        vm.prank(validators[1]);
        oracle.submitPrice(vault, prices[1], roundId);

        // No aggregation yet
        vm.expectRevert(IVaultPriceOracle.NoDataAvailable.selector);
        oracle.getLatestPrice(vault);

        // Submit 3rd to reach quorum
        vm.recordLogs();
        vm.prank(validators[2]);
        oracle.submitPrice(vault, prices[2], roundId);

        // Aggregation happened: median of [100,110,105] sorted [100,105,110] -> 105, roundId = 2
        (uint price, uint timestamp, uint rId) = oracle.getLatestPrice(vault);
        console.log("Actual price:", price);
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

    function testManipulationPrice() public {
        uint roundId = 1;
        uint[] memory prices = new uint[](5);
        prices[0] = 1005;
        prices[1] = 1010;
        prices[2] = 5;

        // Submit prices from first 2 validators (below quorum)
        vm.prank(validators[0]);
        oracle.submitPrice(vault, prices[0], roundId);
        vm.prank(validators[1]);
        oracle.submitPrice(vault, prices[1], roundId);

        // Submit 3rd to reach quorum
        vm.recordLogs();
        vm.prank(validators[2]);
        oracle.submitPrice(vault, prices[2], roundId);

        // Aggregation happened: median of [1005,1010,5] sorted [5,1005,1010] -> 1005, roundId = 2
        (uint price,,) = oracle.getLatestPrice(vault);
        console.log("Actual price:", price);
        assertEq(price, 1005, "Incorrect median price");
    }

    function testGetLatestPrice() public {
        // No data yet
        vm.expectRevert(IVaultPriceOracle.NoDataAvailable.selector);
        oracle.getLatestPrice(vault);

        // Submit and aggregate
        testSubmitPriceAndAggregation();

        (uint price, uint timestamp, uint rId) = oracle.getLatestPrice(vault);
        console.log("Price in testGetLatestPrice:", price);
        assertEq(price, 105, "Incorrect price");
        assertEq(rId, 2, "Incorrect roundId");

        // Test timestamp manipulation (forward within 15 seconds)
        uint originalTimestamp = block.timestamp;
        vm.warp(originalTimestamp + 15); // Simulate miner setting timestamp slightly later
        (price, timestamp, rId) = oracle.getLatestPrice(vault);
        assertEq(price, 105, "Price should remain valid with minor timestamp manipulation");

        // Warp time to make price stale
        vm.warp(originalTimestamp + MAX_PRICE_AGE + 1);
        vm.expectRevert(IVaultPriceOracle.PriceTooOld.selector);
        oracle.getLatestPrice(vault);
    }

    function testVaultPrices() public {
        // No data yet
        (uint price, uint timestamp, uint rId) = oracle.vaultPrice(vault);
        assertEq(price, 0, "Price should be 0");
        assertEq(timestamp, 0, "Timestamp should be 0");
        assertEq(rId, 0, "RoundId should be 0");

        // Submit and aggregate
        testSubmitPriceAndAggregation();

        (price, timestamp, rId) = oracle.vaultPrice(vault);
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
        assertEq(oracle.validatorByIndex(0), validators[0], "Validator list incorrect");
        assertEq(oracle.validatorsLength(), 5, "Validator list length incorrect");
        address[] memory validatorList = oracle.validators();
        for (uint i = 0; i < validators.length; i++) {
            assertEq(validatorList[i], validators[i], "Validator list array incorrect");
        }
        vm.expectRevert(IVaultPriceOracle.IndexOutOfBounds.selector);
        oracle.validatorByIndex(5);
    }

    function testVaultList() public {
        assertEq(oracle.vaultByIndex(0), vaults[0], "Vault list incorrect");
        assertEq(oracle.vaultsLength(), 1, "Vault list length incorrect");
        address[] memory vaultList = oracle.vaults();
        for (uint i = 0; i < vaults.length; i++) {
            assertEq(vaultList[i], vaults[i], "Vault list array incorrect");
        }
        vm.expectRevert(IVaultPriceOracle.IndexOutOfBounds.selector);
        oracle.vaultByIndex(1);
    }

    function testMinQuorum() public view {
        assertEq(oracle.minQuorum(), MIN_QUORUM, "Min quorum incorrect");
    }

    function testMaxPriceAge() public view {
        assertEq(oracle.maxPriceAge(), MAX_PRICE_AGE, "Max price age incorrect");
    }

    function testStorageSlot() public pure {
        bytes32 namespaceHash = keccak256(abi.encodePacked("erc7201:stability.VaultPriceOracle"));
        bytes32 expectedSlot = 0xa68171b251d015e5a139782486873a18b874637da10a73c080418fb52ac37300;
        bytes32 calculatedSlot = keccak256(abi.encode(uint(namespaceHash) - 1)) & ~bytes32(uint(0xff));
        assertEq(calculatedSlot, expectedSlot, "Storage slot calculation is incorrect");
    }

    function testRequireValidator() public {
        // Non-validator
        vm.prank(makeAddr("notValidator"));
        vm.expectRevert(IVaultPriceOracle.NotAuthorizedValidator.selector);
        oracle.submitPrice(vault, 100, 1);

        // Validator
        vm.prank(validators[0]);
        oracle.submitPrice(vault, 100, 1); // Should not revert
    }

    function testDuplicateValidatorsInInitialize() public {
        address[] memory duplicateValidators = new address[](2);
        duplicateValidators[0] = validators[0];
        duplicateValidators[1] = validators[0];
        VaultPriceOracle newOracle = new VaultPriceOracle();
        Proxy newProxy = new Proxy();
        newProxy.initProxy(address(newOracle));

        vm.mockCall(address(platform), abi.encodeWithSelector(IPlatform.multisig.selector), abi.encode(multisig));
        vm.mockCall(address(platform), abi.encodeWithSelector(IPlatform.governance.selector), abi.encode(address(this)));

        VaultPriceOracle(address(newProxy)).initialize(address(platform));
        assertEq(oracle.validatorsLength(), 5, "Validator list length incorrect");
    }

    function testSubmitPriceWithHighQuorum() public {
        // Set high quorum
        vm.prank(address(this));
        oracle.setMinQuorum(10);

        uint roundId = 1;
        uint[] memory prices = new uint[](5);
        prices[0] = 100;
        prices[1] = 110;
        prices[2] = 105;
        prices[3] = 120;
        prices[4] = 95;

        // Submit prices (below quorum)
        for (uint i = 0; i < validators.length; i++) {
            vm.prank(validators[i]);
            oracle.submitPrice(vault, prices[i], roundId);
        }

        // No aggregation yet
        vm.expectRevert(IVaultPriceOracle.NoDataAvailable.selector);
        oracle.getLatestPrice(vault);

        // Add more validators to reach quorum
        for (uint i = 0; i < 5; i++) {
            address newValidator = makeAddr(string(abi.encodePacked("extraValidator", i)));
            vm.prank(address(this));
            oracle.addValidator(newValidator);
            vm.prank(newValidator);
            oracle.submitPrice(vault, prices[i], roundId);
        }

        // Aggregation should now occur
        (uint price, uint timestamp, uint rId) = oracle.getLatestPrice(vault);
        assertEq(price, 105, "Incorrect median price");
        assertEq(timestamp, block.timestamp, "Incorrect timestamp");
        assertEq(rId, 2, "Incorrect roundId");
    }
}
