// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IXToken} from "../../src/interfaces/IXToken.sol";
import {IXStaking} from "../../src/interfaces/IXStaking.sol";
import {IDAO} from "../../src/interfaces/IDAO.sol";
import {XToken} from "../../src/tokenomics/XToken.sol";
import {DAO} from "../../src/tokenomics/DAO.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";

/// @notice Test upgrade of xToken and DAO
contract XTokenUpgrade424SonicTest is Test {
    uint public constant FORK_BLOCK = 57497805; // Dec-09-2025 05:04:40 AM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
    }

    function testUpgradeNotDataChanged() public {
        IXToken xToken = IXToken(SonicConstantsLib.TOKEN_XSTBL);
        IDAO daoToken = IDAO(IPlatform(PLATFORM).stabilityDAO());
        IXStaking xStaking = IXStaking(SonicConstantsLib.XSTBL_XSTAKING);

        uint baseAmount = 100e18;

        // -------------- get STBL on balance
        deal(SonicConstantsLib.TOKEN_STBL, address(this), baseAmount);

        // -------------- enter to xToken
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(xToken), type(uint).max);
        xToken.enter(baseAmount);

        uint xTokenBalance = IERC20(address(xToken)).balanceOf(address(this));
        assertEq(xTokenBalance, baseAmount, "xToken balance after enter");

        // -------------- get config of DAO
        IDAO.DaoParams memory daoParamsBefore = daoToken.config();

        _upgradePlatform();

        vm.prank(SonicConstantsLib.MULTISIG);
        xToken.setName("xStabilityV2");

        vm.prank(SonicConstantsLib.MULTISIG);
        xToken.setSymbol("xSTBLv2");

        vm.prank(SonicConstantsLib.MULTISIG);
        daoToken.setName("StabilityDAOv2");

        vm.prank(SonicConstantsLib.MULTISIG);
        daoToken.setSymbol("STBLDAOv2");

        (uint exitedAmount,) = _tryToExit(xToken, address(this), baseAmount);
        assertEq(exitedAmount, baseAmount * (1e4 - daoParamsBefore.exitPenalty) / 1e4, "exited amount after upgrade");

        assertEq(xToken.xStaking(), SonicConstantsLib.XSTBL_XSTAKING, "xStaking address mismatch");
        assertEq(xToken.token(), SonicConstantsLib.TOKEN_STBL, "main token address mismatch");

        assertEq(xStaking.xToken(), SonicConstantsLib.TOKEN_XSTBL, "xToken address mismatch");

        // -------------- check config of DAO after upgrade
        IDAO.DaoParams memory daoParamsAfter = daoToken.config();

        assertEq(daoParamsBefore.exitPenalty, daoParamsAfter.exitPenalty, "exitPenalty");
        assertEq(daoParamsBefore.minimalPower, daoParamsAfter.minimalPower, "minimalPower");
        assertEq(daoParamsBefore.proposalThreshold, daoParamsAfter.proposalThreshold, "proposalThreshold");
        assertEq(daoParamsBefore.quorum, daoParamsAfter.quorum, "quorum");
        assertEq(daoParamsBefore.powerAllocationDelay, daoParamsAfter.powerAllocationDelay, "powerAllocationDelay");
    }

    //region -------------------------------- Internal logic
    function _tryToExit(
        IXToken xToken_,
        address user,
        uint amount
    ) internal returns (uint exitedAmount, uint pendingRebaseDelta) {
        uint snapshot = vm.snapshotState();

        uint pendingRebaseBefore = IXToken(SonicConstantsLib.TOKEN_XSTBL).pendingRebase();
        uint balanceBefore = IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(user);
        xToken_.exit(amount);
        uint balanceAfter = IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(user);
        uint pendingRebaseAfter = IXToken(SonicConstantsLib.TOKEN_XSTBL).pendingRebase();

        exitedAmount = balanceAfter - balanceBefore;
        pendingRebaseDelta = pendingRebaseAfter - pendingRebaseBefore;

        vm.revertToState(snapshot);
    }

    //endregion -------------------------------- Internal logic

    //region -------------------------------- Helpers
    function _upgradePlatform() internal {
        rewind(1 days);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](3);
        address[] memory implementations = new address[](3);

        proxies[0] = SonicConstantsLib.TOKEN_XSTBL;
        proxies[1] = platform.stabilityDAO();
        proxies[2] = SonicConstantsLib.XSTBL_XSTAKING;

        implementations[0] = address(new XToken());
        implementations[1] = address(new DAO());
        implementations[2] = address(new XStaking());

        //        vm.startPrank(SonicConstantsLib.MULTISIG);
        //        platform.cancelUpgrade();

        vm.startPrank(SonicConstantsLib.MULTISIG);
        platform.announcePlatformUpgrade("2025.12.00-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }
    //endregion -------------------------------- Helpers
}
