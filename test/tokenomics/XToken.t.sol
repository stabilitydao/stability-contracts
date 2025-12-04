// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {MockSetup} from "../base/MockSetup.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {IXToken} from "../../src/interfaces/IXToken.sol";
import {IXStaking} from "../../src/interfaces/IXStaking.sol";
import {IDAO} from "../../src/interfaces/IDAO.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {XToken} from "../../src/tokenomics/XToken.sol";
import {RevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";
import {FeeTreasury} from "../../src/tokenomics/FeeTreasury.sol";
import {DAO} from "../../src/tokenomics/DAO.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import {console} from "forge-std/console.sol";

contract XTokenTest is Test, MockSetup {
    using SafeERC20 for IERC20;

    address public stbl;
    IXToken public xToken;
    IXStaking public xStaking;

    //region --------------------- Tests
    function setUp() public {
        stbl = address(tokenA);
        Proxy xStakingProxy = new Proxy();
        xStakingProxy.initProxy(address(new XStaking()));
        Proxy xTokenProxy = new Proxy();
        xTokenProxy.initProxy(address(new XToken()));
        Proxy revenueRouterProxy = new Proxy();
        revenueRouterProxy.initProxy(address(new RevenueRouter()));
        Proxy feeTreasuryProxy = new Proxy();
        feeTreasuryProxy.initProxy(address(new FeeTreasury()));
        FeeTreasury(address(feeTreasuryProxy)).initialize(address(platform), platform.multisig());
        XStaking(address(xStakingProxy)).initialize(address(platform), address(xTokenProxy));
        XToken(address(xTokenProxy))
            .initialize(address(platform), stbl, address(xStakingProxy), address(revenueRouterProxy), "xStability", "xSTBL");
        RevenueRouter(address(revenueRouterProxy))
            .initialize(address(platform), address(xTokenProxy), address(feeTreasuryProxy));
        xToken = IXToken(address(xTokenProxy));
        xStaking = IXStaking(address(xStakingProxy));
        //console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.XSTBL")) - 1)) & ~bytes32(uint256(0xff)));
    }

    function test_transfer() public {
        tokenA.mint(100e18);
        IERC20(stbl).approve(address(xToken), 100e18);
        xToken.enter(100e18);

        vm.expectRevert(abi.encodeWithSelector(IXToken.NOT_WHITELISTED.selector, address(this), address(1)));
        /// forge-lint: disable-next-line
        IERC20(address(xToken)).transfer(address(1), 1e18);

        address[] memory exemptee = new address[](1);
        exemptee[0] = address(this);
        bool[] memory exempt = new bool[](2);
        vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectArrayLength.selector));
        xToken.setExemptionFrom(exemptee, exempt);
        vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectArrayLength.selector));
        xToken.setExemptionTo(exemptee, exempt);
        vm.prank(address(101));
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotGovernanceAndNotMultisig.selector));
        xToken.setExemptionFrom(exemptee, exempt);
        vm.prank(address(101));
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotGovernanceAndNotMultisig.selector));
        xToken.setExemptionTo(exemptee, exempt);
        exempt = new bool[](1);
        exempt[0] = true;
        xToken.setExemptionFrom(exemptee, exempt);

        /// forge-lint: disable-next-line
        IERC20(address(xToken)).transfer(address(1), 1e18);

        exempt[0] = false;
        xToken.setExemptionFrom(exemptee, exempt);
        vm.expectRevert(abi.encodeWithSelector(IXToken.NOT_WHITELISTED.selector, address(this), address(1)));
        /// forge-lint: disable-next-line
        IERC20(address(xToken)).transfer(address(1), 1e18);

        exemptee[0] = address(1);
        exempt[0] = true;
        xToken.setExemptionTo(exemptee, exempt);
        /// forge-lint: disable-next-line
        IERC20(address(xToken)).transfer(address(1), 1e18);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(IXToken.NOT_WHITELISTED.selector, address(1), address(2)));
        /// forge-lint: disable-next-line
        IERC20(address(xToken)).transfer(address(2), 1e18);
    }

    function test_enter_exit() public {
        tokenA.mint(100e18);
        IERC20(stbl).approve(address(xToken), 100e18);

        // enter
        xToken.enter(100e18);
        assertEq(IERC20(address(xToken)).balanceOf(address(this)), 100e18);
        assertEq(IERC20(stbl).balanceOf(address(xToken)), 100e18);

        // instant exit
        xToken.exit(50e18);
        assertEq(IERC20(address(xToken)).balanceOf(address(this)), 50e18);
        assertEq(IERC20(stbl).balanceOf(address(this)), 25e18);
        assertEq(IERC20(stbl).balanceOf(address(xToken)), 75e18);

        // create vest
        uint time = block.timestamp;
        xToken.createVest(30e18);
        (uint amount, uint start, uint maxEnd) = xToken.vestInfo(address(this), 0);
        assertEq(amount, 30e18);
        assertEq(start, time);
        assertEq(maxEnd, time + xToken.MAX_VEST());
        assertEq(xToken.usersTotalVests(address(this)), 1);
        assertEq(IERC20(address(xToken)).balanceOf(address(this)), 20e18);

        // cancel vesting
        vm.warp(time + 13 days);
        xToken.exitVest(0);
        (amount,,) = xToken.vestInfo(address(this), 0);
        assertEq(amount, 0);
        assertEq(IERC20(address(xToken)).balanceOf(address(this)), 50e18);
        assertEq(xToken.pendingRebase(), 25e18);

        // exit vesting in progress
        time = block.timestamp;
        xToken.createVest(30e18);
        assertEq(xToken.usersTotalVests(address(this)), 2);
        vm.warp(time + 179 days);
        xToken.exitVest(1);
        (amount,,) = xToken.vestInfo(address(this), 1);
        assertEq(amount, 0);
        assertGt(IERC20(stbl).balanceOf(address(this)), 25e18 + 29e18);
        assertLt(IERC20(stbl).balanceOf(address(this)), 25e18 + 30e18);

        // exit completed vesting
        time = block.timestamp;
        xToken.createVest(20e18);
        vm.warp(time + 200 days);
        uint balanceWas = IERC20(stbl).balanceOf(address(this));
        xToken.exitVest(2);
        assertEq(IERC20(stbl).balanceOf(address(this)), balanceWas + 20e18);
    }

    function test_reverts() public {
        vm.expectRevert();
        xToken.rebase();

        vm.expectRevert();
        xToken.enter(0);

        vm.expectRevert();
        xToken.exit(0);

        vm.expectRevert();
        xToken.createVest(0);

        vm.expectRevert();
        xToken.exitVest(10);
    }

    function testSlashingPenalty() public {
        // --------------------- StabilityDAO is not initialized
        assertEq(xToken.SLASHING_PENALTY(), 50_00, "50% by default");

        // --------------------- Set up StabilityDAO
        IDAO daoToken = _createDAOInstance();
        platform.setupStabilityDAO(address(daoToken));

        _setSlashingPenalty(daoToken, 80_00);
        assertEq(xToken.SLASHING_PENALTY(), 80_00, "80%");

        _setSlashingPenalty(daoToken, 30_00);
        assertEq(xToken.SLASHING_PENALTY(), 30_00, "30%");

        _setSlashingPenalty(daoToken, 0);
        assertEq(xToken.SLASHING_PENALTY(), 50_00, "DEFAULT_SLASHING_PENALTY");
    }

    function testSetBridge() public {
        address multisig = platform.multisig();

        assertEq(xToken.isBridge(address(1)), false, "not bridge by default");

        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        vm.prank(address(2));
        xToken.setBridge(address(1), true);

        vm.prank(multisig);
        xToken.setBridge(address(1), true);

        assertEq(xToken.isBridge(address(1)), true, "expected bridge");

        vm.prank(multisig);
        xToken.setBridge(address(1), false);

        assertEq(xToken.isBridge(address(1)), false, "bridge is cleared");
    }

    function testBridgeActions() public {
        address multisig = platform.multisig();
        address bridge = makeAddr("bridge");
        address user = makeAddr("user");

        vm.prank(multisig);
        xToken.setBridge(bridge, true);

        // ---------------------- prepare xToken for the user
        tokenA.mint(100e18);
        IERC20(address(tokenA)).safeTransfer(user, 100e18);

        vm.prank(user);
        IERC20(stbl).approve(address(xToken), 100e18);

        vm.prank(user);
        xToken.enter(100e18);

        // ---------------------- send xToken to the bridge
        {
            vm.expectRevert(IControllable.IncorrectZeroArgument.selector);
            vm.prank(bridge);
            xToken.sendToBridge(address(0), 1e18);

            vm.expectRevert(IControllable.IncorrectZeroArgument.selector);
            vm.prank(bridge);
            xToken.sendToBridge(user, 0);

            vm.expectRevert(IControllable.IncorrectMsgSender.selector);
            vm.prank(user);
            xToken.sendToBridge(bridge, 1e18);

            assertEq(IERC20(address(xToken)).balanceOf(user), 100e18, "user xToken balance before sendToBridge");
            assertEq(IERC20(address(tokenA)).balanceOf(user), 0, "user main-token balance before sendToBridge");

            vm.prank(bridge);
            xToken.sendToBridge(user, 40e18);
        }

        assertEq(IERC20(address(xToken)).balanceOf(user), 60e18, "user xToken balance after sendToBridge");
        assertEq(IERC20(address(tokenA)).balanceOf(address(xToken)), 60e18, "locked main-token balance after sendToBridge");
        assertEq(IERC20(address(tokenA)).balanceOf(user), 0, "user main-token balance after sendToBridge");
        assertEq(IERC20(address(tokenA)).balanceOf(bridge), 40e18, "bridge main-token balance after sendToBridge");

        // ---------------------- receive xToken from the bridge
        {
            vm.expectRevert(IControllable.IncorrectZeroArgument.selector);
            vm.prank(bridge);
            xToken.takeFromBridge(address(0), 1e18);

            vm.expectRevert(IControllable.IncorrectZeroArgument.selector);
            vm.prank(bridge);
            xToken.takeFromBridge(user, 0);

            vm.expectRevert(IControllable.IncorrectMsgSender.selector);
            vm.prank(user);
            xToken.takeFromBridge(bridge, 1e18);

            vm.prank(bridge);
            tokenA.approve(address(xToken), 40e18);

            vm.prank(bridge);
            xToken.takeFromBridge(user, 40e18);
        }

        assertEq(IERC20(address(xToken)).balanceOf(user), 100e18, "user xToken balance after takeFromBridge");
        assertEq(IERC20(address(tokenA)).balanceOf(address(xToken)), 100e18, "locked main-token balance after takeFromBridge");
        assertEq(IERC20(address(tokenA)).balanceOf(user), 0, "user main-token balance after takeFromBridge");
        assertEq(IERC20(address(tokenA)).balanceOf(bridge), 0, "bridge main-token balance after takeFromBridge");
    }

    //endregion --------------------- Tests

    //region --------------------- Helpers
    function _setSlashingPenalty(IDAO daoToken, uint penalty_) internal {
        address multisig = platform.multisig();

        IDAO.DaoParams memory config = daoToken.config();
        config.exitPenalty = penalty_;

        vm.prank(multisig);
        daoToken.updateConfig(config);
    }

    function _createDAOInstance() internal returns (IDAO) {
        IDAO.DaoParams memory p = IDAO.DaoParams({
            minimalPower: 4000e18,
            exitPenalty: 50_00,
            quorum: 20_00,
            proposalThreshold: 10_00,
            powerAllocationDelay: 86400
        });

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new DAO()));
        IDAO token = IDAO(address(proxy));
        token.initialize(address(platform), address(xToken), address(xStaking), p, "Stability DAO", "STBL_DAO");
        return token;
    }
    //endregion --------------------- Helpers
}
