// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {IPriceReader, IPlatform} from "../../src/core/PriceReader.sol";
import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheConstantsLib.sol";
import {PriceAggregator} from "../../src/core/PriceAggregator.sol";
import {Platform} from "../../src/core/Platform.sol";
import {IPriceAggregator} from "../../src/interfaces/IPriceAggregator.sol";

interface IPlatformBeforeUpdate {
    function vaultPriceOracle() external view returns (address);
}

/// @notice Old interface, it was replaced by IPriceAggregator at this update
interface IVaultPriceOracle {
    struct Observation {
        uint price;
        uint timestamp;
    }

    struct AggregatedData {
        uint price;
        uint timestamp;
        uint roundId;
    }

    struct VaultData {
        uint priceThreshold;
        uint staleness;
    }

    function vaultPrice(address vault_) external view returns (uint price, uint timestamp, uint roundId);
    function observations(
        address vault_,
        uint roundId_,
        address validator_
    ) external view returns (uint price, uint timestamp);
    function authorizedValidator(address validator_) external view returns (bool);
    function validatorByIndex(uint index_) external view returns (address);
    function validators() external view returns (address[] memory);
    function validatorsLength() external view returns (uint);
    function vaultByIndex(uint index_) external view returns (address);
    function vaults() external view returns (address[] memory);
    function vaultsLength() external view returns (uint);
    function minQuorum() external view returns (uint);
    function maxPriceAge() external view returns (uint);
    function getLatestPrice(address vault_) external view returns (uint price, uint timestamp, uint roundId);
    function vaultData(address vault_) external view returns (uint priceThreshold, uint staleness);

    function submitPrice(address vault_, uint price_, uint roundId_) external;
    function addValidator(address validator_) external;
    function removeValidator(address validator_) external;
    function setMinQuorum(uint minQuorum_) external;
    function setMaxPriceAge(uint maxPriceAge_) external;
    function addVault(address vault_, uint priceThreshold_, uint staleness_) external;
    function removeVault(address vault_) external;
}

/// @notice #348
contract PriceAggregatorUpgrade414SonicTest is Test {
    uint public constant FORK_BLOCK_C_CHAIN = 70820228; // Oct-24-2025 06:53:05 UTC

    address public constant PLATFORM = AvalancheConstantsLib.PLATFORM;
    address public multisig;
    IPriceReader public priceReader;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("AVALANCHE_RPC_URL"), FORK_BLOCK_C_CHAIN));
    }

    function setUp() public {
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        multisig = IPlatform(PLATFORM).multisig();
    }

    function testUpgrade() public {
        IVaultPriceOracle vaultPriceOracle = IVaultPriceOracle(IPlatformBeforeUpdate(PLATFORM).vaultPriceOracle());

        // ----------------------- add data to old version of the price aggregator
        vm.prank(multisig);
        vaultPriceOracle.addValidator(multisig);

        vm.prank(multisig);
        vaultPriceOracle.addVault(address(1), 7000, 2 hours);

        vm.prank(multisig);
        vaultPriceOracle.submitPrice(address(1), 17e18, 1);

        // ----------------------- data before upgrade
        address[] memory validators = vaultPriceOracle.validators();
        address[] memory vaults = vaultPriceOracle.vaults();
        uint maxPriceAge = vaultPriceOracle.maxPriceAge();
        uint minQuorum = vaultPriceOracle.minQuorum();

        // ----------------------- do upgrade
        _upgradePlatform();

        IPriceAggregator priceAggregator = IPriceAggregator(IPlatform(PLATFORM).priceAggregator());
        assertEq(address(priceAggregator), address(vaultPriceOracle), "price aggregator address");

        // ----------------------- ensure that data after upgrade wasn't changed
        {
            address[] memory validatorsAfter = priceAggregator.validators();
            address[] memory vaultsAfter = priceAggregator.vaults();
            uint maxPriceAgeAfter = priceAggregator.maxPriceAge();
            uint minQuorumAfter = priceAggregator.minQuorum();

            assertEq(validators.length, validatorsAfter.length, "validators length after upgrade");
            for (uint i = 0; i < validators.length; i++) {
                assertEq(validators[i], validatorsAfter[i], "validator address after upgrade");
            }
            assertEq(vaults.length, vaultsAfter.length, "vaults length after upgrade");
            for (uint i = 0; i < vaults.length; i++) {
                assertEq(vaults[i], vaultsAfter[i], "vault address after upgrade");
            }
            assertEq(maxPriceAge, maxPriceAgeAfter, "maxPriceAge after upgrade");
            assertEq(minQuorum, minQuorumAfter, "minQuorum after upgrade");

            (uint priceThreshold, uint staleness) = priceAggregator.entityData(address(1));
            assertEq(priceThreshold, 7000, "vault priceThreshold after upgrade");
            assertEq(staleness, 2 hours, "vault staleness after upgrade");
        }

        // ----------------------- do actions after upgrade
        vm.prank(multisig);
        priceAggregator.addValidator(address(this));

        vm.prank(multisig);
        priceAggregator.addVault(AvalancheConstantsLib.EULER_VAULT_USDC_RE7, 1e18, 1 hours);

        vm.prank(multisig);
        priceAggregator.addAsset(AvalancheConstantsLib.TOKEN_USDC, 12e18, 17 hours);

        vm.prank(multisig);
        priceAggregator.setMaxPriceAge(5001);

        vm.prank(multisig);
        priceAggregator.setMinQuorum(177);

        // ----------------------- check changes
        {
            address[] memory validatorsAfter = vaultPriceOracle.validators();
            address[] memory vaultsAfter = vaultPriceOracle.vaults();
            address[] memory assetsAfter = priceAggregator.assets();
            uint maxPriceAgeAfter = vaultPriceOracle.maxPriceAge();
            uint minQuorumAfter = vaultPriceOracle.minQuorum();

            assertEq(validatorsAfter.length, validators.length + 1, "validators length after change");
            for (uint i = 0; i < validatorsAfter.length; i++) {
                if (i == validators.length) {
                    assertEq(validatorsAfter[i], address(this), "validator address after change 1");
                } else {
                    assertEq(validatorsAfter[i], validators[i], "validator address after change 2");
                }
            }
            assertEq(vaultsAfter.length, vaults.length + 1, "vaults length after change");
            for (uint i = 0; i < vaultsAfter.length; i++) {
                if (i == vaults.length) {
                    assertEq(vaultsAfter[i], AvalancheConstantsLib.EULER_VAULT_USDC_RE7, "vault address after change 1");
                } else {
                    assertEq(vaultsAfter[i], vaults[i], "vault address after change 2");
                }
            }
            assertEq(assetsAfter.length, 1, "assets length after change");
            assertEq(assetsAfter[0], AvalancheConstantsLib.TOKEN_USDC, "asset address after change");

            assertEq(maxPriceAgeAfter, 5001, "maxPriceAge after change");
            assertEq(minQuorumAfter, 177, "minQuorum after change");

            (uint price,,) = priceAggregator.price(address(1));
            assertEq(price, 17e18, "vault price after change");
        }
    }

    //region --------------------------------- Internal logic

    //endregion --------------------------------- Internal logic

    //region --------------------------------- Helpers
    function _upgradePlatform() internal {
        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](2);
        proxies[0] = address(IPlatformBeforeUpdate(address(platform)).vaultPriceOracle());
        proxies[1] = address(platform);

        address[] memory implementations = new address[](2);
        implementations[0] = address(new PriceAggregator());
        implementations[1] = address(new Platform());

        vm.startPrank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.05.0-alpha", proxies, implementations);
        skip(1 days);
        IPlatform(PLATFORM).upgrade();
        vm.stopPrank();
    }
    //endregion --------------------------------- Helpers
}
