// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../base/chains/PolygonSetup.sol";
import "../../src/core/libs/VaultTypeLib.sol";
import "../../src/interfaces/IVaultManager.sol";
import "../../src/interfaces/IHardWorker.sol";

contract PlatformPolygonTest is PolygonSetup {
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct BuildingVars {
        uint len;
        uint paramsLen;
        string[] desc;
        string[] vaultType;
        string[] strategyId;
        uint[10][] initIndexes;
        address[] allVaultInitAddresses;
        uint[] allVaultInitNums;
        address[] allStrategyInitAddresses;
        uint[] allStrategyInitNums;
        int24[] allStrategyInitTicks;
    }

    constructor() {
        _init();
        deal(platform.buildingPayPerVaultToken(), address(this), 5e24);
        IERC20(platform.buildingPayPerVaultToken()).approve(address(factory), 5e24);

        deal(platform.allowedBBTokens()[0], address(this), 5e24);
        IERC20(platform.allowedBBTokens()[0]).approve(address(factory), 5e24);

        deal(PolygonLib.TOKEN_USDC, address(this), 1e12);
        IERC20(PolygonLib.TOKEN_USDC).approve(address(factory), 1e12);
    }

    bool canReceive;

    receive() external payable {
        require(canReceive);
    }

    function testUserBalance() public {
        (
            address[] memory token,
            uint[] memory tokenPrice,
            uint[] memory tokenUserBalance,
            address[] memory vault,
            uint[] memory vaultSharePrice,
            uint[] memory vaultUserBalance,
            address[] memory nft,
            uint[] memory nftUserBalance,
        ) = platform.getBalance(address(this));
        uint len = token.length;
        for (uint i; i < len; ++i) {
            assertNotEq(token[i], address(0));
            assertGt(tokenPrice[i], 0);
            if (token[i] == PolygonLib.TOKEN_USDC) {
                assertEq(tokenUserBalance[i], 1e12);
            } else if (token[i] == platform.allowedBBTokens()[0]) {
                assertEq(tokenUserBalance[i], 5e24);
            } else {
                assertEq(tokenUserBalance[i], 0);
            }
        }
        len = vault.length;
        for (uint i; i < len; ++i) {
            assertNotEq(vault[i], address(0));
            assertGt(vaultSharePrice[i], 0);
            assertEq(vaultUserBalance[i], 0);
        }
        len = nft.length;
        for (uint i; i < len; ++i) {
            assertNotEq(nft[i], address(0));
            assertEq(nftUserBalance[i], 0);
        }
        assertEq(nft[0], platform.buildingPermitToken());
        assertEq(nft[1], platform.vaultManager());
        assertEq(nft[2], platform.strategyLogic());
    }

    function testAll() public {
        // console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.HardWorker")) - 1)) & ~bytes32(uint256(0xff)));

        platform.setAllowedBBTokenVaults(platform.allowedBBTokens()[0], 1e4);
        BuildingVars memory vars;
        {
            // this method used to avoid stack too deep
            (
                string[] memory desc,
                string[] memory vaultType,
                string[] memory strategyId,
                uint[10][] memory initIndexes,
                address[] memory allVaultInitAddresses,
                uint[] memory allVaultInitNums,
                address[] memory allStrategyInitAddresses,
                uint[] memory allStrategyInitNums,
                int24[] memory allStrategyInitTicks
            ) = factory.whatToBuild();
            vars.desc = desc;
            vars.vaultType = vaultType;
            vars.strategyId = strategyId;
            vars.initIndexes = initIndexes;
            vars.allVaultInitAddresses = allVaultInitAddresses;
            vars.allVaultInitNums = allVaultInitNums;
            vars.allStrategyInitAddresses = allStrategyInitAddresses;
            vars.allStrategyInitNums = allStrategyInitNums;
            vars.allStrategyInitTicks = allStrategyInitTicks;
        }

        uint len = vars.desc.length;
        assertGt(len, 0);
        assertEq(len, vars.vaultType.length);
        assertEq(len, vars.strategyId.length);
        assertEq(len, vars.initIndexes.length);

        console.log("whatToBuild:");
        for (uint i; i < len; ++i) {
            uint paramsLen = vars.initIndexes[i][1] - vars.initIndexes[i][0];
            address[] memory vaultInitAddresses = new address[](paramsLen);
            for (uint k; k < paramsLen; ++k) {
                vaultInitAddresses[k] = vars.allVaultInitAddresses[vars.initIndexes[i][0] + k];
            }
            paramsLen = vars.initIndexes[i][3] - vars.initIndexes[i][2];
            uint[] memory vaultInitNums = new uint[](paramsLen);
            for (uint k; k < paramsLen; ++k) {
                vaultInitNums[k] = vars.allVaultInitNums[vars.initIndexes[i][2] + k];
            }
            paramsLen = vars.initIndexes[i][5] - vars.initIndexes[i][4];
            address[] memory strategyInitAddresses = new address[](paramsLen);
            for (uint k; k < paramsLen; ++k) {
                strategyInitAddresses[k] = vars.allStrategyInitAddresses[vars.initIndexes[i][4] + k];
            }
            paramsLen = vars.initIndexes[i][7] - vars.initIndexes[i][6];
            uint[] memory strategyInitNums = new uint[](paramsLen);
            for (uint k; k < paramsLen; ++k) {
                strategyInitNums[k] = vars.allStrategyInitNums[vars.initIndexes[i][6] + k];
            }
            paramsLen = vars.initIndexes[i][9] - vars.initIndexes[i][8];
            int24[] memory strategyInitTicks = new int24[](paramsLen);
            for (uint k; k < paramsLen; ++k) {
                strategyInitTicks[k] = vars.allStrategyInitTicks[vars.initIndexes[i][8] + k];
            }

            string memory vaultInitSymbols = vaultInitAddresses.length > 0
                ? string.concat(" ", CommonLib.implodeSymbols(vaultInitAddresses, "-"))
                : "";

            if (CommonLib.eq(vars.vaultType[i], VaultTypeLib.REWARDING)) {
                (vaultInitAddresses, vaultInitNums) =
                    _getRewardingInitParams(vars.allVaultInitAddresses[vars.initIndexes[i][0]]);
            }

            if (CommonLib.eq(vars.vaultType[i], VaultTypeLib.REWARDING_MANAGED)) {
                (vaultInitAddresses, vaultInitNums) =
                    _getRewardingManagedInitParams(vars.allVaultInitAddresses[vars.initIndexes[i][0]]);
            }

            console.log(string.concat(" Vault: ", vars.vaultType[i], vaultInitSymbols, ". Strategy: ", vars.desc[i]));

            factory.deployVaultAndStrategy(
                vars.vaultType[i],
                vars.strategyId[i],
                vaultInitAddresses,
                vaultInitNums,
                strategyInitAddresses,
                strategyInitNums,
                strategyInitTicks
            );
            (,,,, uint[] memory vaultSharePrice, uint[] memory vaultUserBalance,,,) = platform.getBalance(address(this));
            assertEq(vaultSharePrice[0], 0);
            assertEq(vaultUserBalance[0], 0);
            bytes32 deploymentKey = factory.getDeploymentKey(
                vars.vaultType[i],
                vars.strategyId[i],
                vaultInitAddresses,
                vaultInitNums,
                strategyInitAddresses,
                strategyInitNums,
                strategyInitTicks
            );
            vm.expectRevert(abi.encodeWithSelector(IFactory.SuchVaultAlreadyDeployed.selector, deploymentKey));
            factory.deployVaultAndStrategy(
                vars.vaultType[i],
                vars.strategyId[i],
                vaultInitAddresses,
                vaultInitNums,
                strategyInitAddresses,
                strategyInitNums,
                strategyInitTicks
            );
        }

        (string[] memory descEmpty,,,,,,,,) = factory.whatToBuild();
        assertEq(descEmpty.length, 0);

        IVaultManager vaultManager = IVaultManager(platform.vaultManager());
        // deposit to all vaults
        {
            (
                address[] memory vaultAddress,
                string[] memory name,
                string[] memory symbol,
                string[] memory _vaultType,
                string[] memory _strategyId,
                ,
                ,
                ,
                ,
            ) = vaultManager.vaults();
            console.log("Built:");
            for (uint i; i < vaultAddress.length; ++i) {
                assertGt(bytes(symbol[i]).length, 0);
                assertGt(bytes(name[i]).length, 0);
                assertGt(bytes(_vaultType[i]).length, 0);
                assertGt(bytes(_strategyId[i]).length, 0);
                console.log(string.concat(" ", symbol[i]));

                _depositToVault(vaultAddress[i], 1e21);
            }
        }

        IHardWorker hw = IHardWorker(platform.hardWorker());
        bool canExec;
        bytes memory execPayload;
        (canExec, execPayload) = hw.checkerServer();
        assertEq(canExec, false);

        skip(1 days);

        (canExec, execPayload) = hw.checkerServer();
        assertEq(canExec, true);
        vm.expectRevert(abi.encodeWithSelector(IHardWorker.NotServerOrGelato.selector));
        vm.prank(address(666));
        (bool success,) = address(hw).call(execPayload);
        (success,) = address(hw).call(execPayload);
        assertEq(success, false);
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotGovernanceAndNotMultisig.selector));
        hw.setDedicatedServerMsgSender(address(this), true);
        assertEq(hw.maxHwPerCall(), 5);
        assertNotEq(hw.gelatoTaskId(), bytes32(0x00));
        assertEq(hw.excludedVaults(address(this)), false);
        vm.prank(platform.multisig());
        hw.setDedicatedServerMsgSender(address(this), true);
        assertEq(hw.dedicatedServerMsgSender(address(this)), true);

        // check HardWorker.changeVaultExcludeStatus
        {
            (address[] memory vaultAddress,,,,,,,,,) = vaultManager.vaults();
            address[] memory vaultAddressesForChangeExcludeStatus = new address[](1);
            vaultAddressesForChangeExcludeStatus[0] = vaultAddress[0];
            bool[] memory status = new bool[](1);

            vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectArrayLength.selector));
            hw.changeVaultExcludeStatus(vaultAddressesForChangeExcludeStatus, new bool[](3));

            vaultAddressesForChangeExcludeStatus[0] = address(4);
            vm.expectRevert(abi.encodeWithSelector(IHardWorker.NotExistWithObject.selector, address(4)));
            hw.changeVaultExcludeStatus(vaultAddressesForChangeExcludeStatus, status);
            vaultAddressesForChangeExcludeStatus[0] = vaultAddress[0];

            vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectArrayLength.selector));
            hw.changeVaultExcludeStatus(new address[](0), new bool[](0));

            vm.expectRevert(
                abi.encodeWithSelector(IHardWorker.AlreadyExclude.selector, vaultAddressesForChangeExcludeStatus[0])
            );
            hw.changeVaultExcludeStatus(vaultAddressesForChangeExcludeStatus, status);

            status[0] = true;
            hw.changeVaultExcludeStatus(vaultAddressesForChangeExcludeStatus, status);

            status[0] = false;
            hw.changeVaultExcludeStatus(vaultAddressesForChangeExcludeStatus, status);
        }

        // check vault manager method
        {
            (address[] memory vaultAddress,,,,,,,,,) = vaultManager.vaults();
            (address strategy, address[] memory strategyAssets,,,,) = vaultManager.vaultInfo(vaultAddress[0]);
            assertNotEq(strategy, address(0));
            assertGt(strategyAssets.length, 0);
        }

        vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectZeroArgument.selector));
        hw.setMaxHwPerCall(0);
        hw.setMaxHwPerCall(5);

        (success,) = address(hw).call(execPayload);
        assertEq(success, true);

        skip(1 days);

        (canExec, execPayload) = hw.checkerGelato();
        assertEq(canExec, true);
        vm.startPrank(hw.dedicatedGelatoMsgSender());

        vm.deal(address(hw), 0);
        vm.expectRevert(abi.encodeWithSelector(IHardWorker.NotEnoughETH.selector));
        (success,) = address(hw).call(execPayload);

        vm.deal(address(hw), 2e18);
        (success,) = address(hw).call(execPayload);
        assertEq(success, true);
        assertGt(hw.gelatoBalance(), 0);
        vm.stopPrank();

        for (uint i; i < len; ++i) {
            (canExec, execPayload) = hw.checkerServer();
            if (canExec) {
                (success,) = address(hw).call(execPayload);
                assertEq(success, true);
            } else {
                break;
            }
        }

        vm.startPrank(platform.multisig());
        hw.setDelays(1 hours, 2 hours);
        vm.expectRevert(abi.encodeWithSelector(IControllable.AlreadyExist.selector));
        hw.setDelays(1 hours, 2 hours);
        vm.stopPrank();

        (uint delayServer, uint delayGelato) = hw.getDelays();
        assertEq(delayServer, 1 hours);
        assertEq(delayGelato, 2 hours);

        address[] memory vaultsForHardWork = new address[](1);
        address vault_ = factory.deployedVault(factory.deployedVaultsLength() - 1);
        vaultsForHardWork[0] = vault_;

        vm.txGasPrice(15e10);
        deal(address(hw), type(uint).max);
        vm.expectRevert(abi.encodeWithSelector(IControllable.ETHTransferFailed.selector));
        hw.call(vaultsForHardWork);
        canReceive = true;
        hw.call(vaultsForHardWork);

        //Still yellow!
        vm.startPrank(address(hw.dedicatedGelatoMsgSender()));

        //lower
        deal(address(hw), 0);
        assertGt(hw.gelatoMinBalance(), address(hw).balance);
        hw.call(vaultsForHardWork);

        //equal
        deal(address(hw), hw.gelatoMinBalance());
        assertEq(address(hw).balance, hw.gelatoMinBalance());
        hw.call(vaultsForHardWork);

        //higher
        deal(address(hw), type(uint).max);
        assertGt(address(hw).balance, hw.gelatoMinBalance());
        hw.call(vaultsForHardWork);

        vm.stopPrank();

        skip(1 hours);
        skip(100);
        (canExec,) = hw.checkerGelato();
        assertEq(canExec, false);
        (canExec,) = hw.checkerServer();
        assertEq(canExec, true);
    }

    function testErc165() public {
        IFactory factory = IFactory(platform.factory());
        (string[] memory vaultType_, address[] memory implementation,,,,) = factory.vaultTypes();
        for (uint i; i < vaultType_.length; ++i) {
            assertEq(IVault(implementation[i]).supportsInterface(type(IERC165).interfaceId), true);
            assertEq(IVault(implementation[i]).supportsInterface(type(IControllable).interfaceId), true);
            assertEq(IVault(implementation[i]).supportsInterface(type(IVault).interfaceId), true);
            if (CommonLib.eq(vaultType_[i], VaultTypeLib.COMPOUNDING)) {
                assertEq(IVault(implementation[i]).supportsInterface(type(IRVault).interfaceId), false);
            }
            if (CommonLib.eq(vaultType_[i], VaultTypeLib.REWARDING)) {
                assertEq(IVault(implementation[i]).supportsInterface(type(IRVault).interfaceId), true);
            }
        }
    }

    function _depositToVault(address vault, uint assetAmountUsd) internal {
        IStrategy strategy = IVault(vault).strategy();
        address[] memory assets = strategy.assets();

        // get amounts for deposit
        uint[] memory depositAmounts = new uint[](assets.length);
        for (uint j; j < assets.length; ++j) {
            (uint price,) = IPriceReader(platform.priceReader()).getPrice(assets[j]);
            depositAmounts[j] = assetAmountUsd * 10 ** IERC20Metadata(assets[j]).decimals() / price;
            deal(assets[j], address(this), depositAmounts[j]);
            IERC20(assets[j]).approve(vault, depositAmounts[j]);
        }

        // deposit
        IVault(vault).depositAssets(assets, depositAmounts, 0, address(0));
    }

    function _getRewardingInitParams(address bbToken)
        internal
        view
        returns (address[] memory vaultInitAddresses, uint[] memory vaultInitNums)
    {
        vaultInitAddresses = new address[](1);
        vaultInitAddresses[0] = bbToken;
        address[] memory defaultBoostRewardsTokensFiltered = platform.defaultBoostRewardTokensFiltered(bbToken);
        vaultInitNums = new uint[](1 + defaultBoostRewardsTokensFiltered.length);
        vaultInitNums[0] = 3000e18;
    }

    function _getRewardingManagedInitParams(address bbToken)
        internal
        pure
        returns (address[] memory vaultInitAddresses, uint[] memory vaultInitNums)
    {
        vaultInitAddresses = new address[](3);
        vaultInitAddresses[0] = bbToken;
        vaultInitAddresses[1] = bbToken;
        vaultInitAddresses[2] = PolygonLib.TOKEN_USDC;
        vaultInitNums = new uint[](3 * 2);
        vaultInitNums[0] = 86_400 * 7;
        vaultInitNums[1] = 86_400 * 30;
        vaultInitNums[2] = 86_400 * 30;
        vaultInitNums[3] = 0;
        vaultInitNums[4] = 1000e6;
        vaultInitNums[5] = 50_000;
    }
}
