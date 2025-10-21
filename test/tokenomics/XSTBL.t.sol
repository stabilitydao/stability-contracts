// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {MockSetup} from "../base/MockSetup.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {IXSTBL} from "../../src/interfaces/IXSTBL.sol";
import {IXStaking} from "../../src/interfaces/IXStaking.sol";
import {IStabilityDAO} from "../../src/interfaces/IStabilityDAO.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {XSTBL} from "../../src/tokenomics/XSTBL.sol";
import {RevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";
import {FeeTreasury} from "../../src/tokenomics/FeeTreasury.sol";
import {StabilityDAO} from "../../src/tokenomics/StabilityDAO.sol";
// import {console} from "forge-std/console.sol";

contract XSTBLTest is Test, MockSetup {
    address public stbl;
    IXSTBL public xStbl;
    IXStaking public xStaking;

    function setUp() public {
        stbl = address(tokenA);
        Proxy xStakingProxy = new Proxy();
        xStakingProxy.initProxy(address(new XStaking()));
        Proxy xSTBLProxy = new Proxy();
        xSTBLProxy.initProxy(address(new XSTBL()));
        Proxy revenueRouterProxy = new Proxy();
        revenueRouterProxy.initProxy(address(new RevenueRouter()));
        Proxy feeTreasuryProxy = new Proxy();
        feeTreasuryProxy.initProxy(address(new FeeTreasury()));
        FeeTreasury(address(feeTreasuryProxy)).initialize(address(platform), platform.multisig());
        XStaking(address(xStakingProxy)).initialize(address(platform), address(xSTBLProxy));
        XSTBL(address(xSTBLProxy)).initialize(
            address(platform), stbl, address(xStakingProxy), address(revenueRouterProxy)
        );
        RevenueRouter(address(revenueRouterProxy)).initialize(
            address(platform), address(xSTBLProxy), address(feeTreasuryProxy)
        );
        xStbl = IXSTBL(address(xSTBLProxy));
        xStaking = IXStaking(address(xStakingProxy));
        //console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.XSTBL")) - 1)) & ~bytes32(uint256(0xff)));
    }

    function test_transfer() public {
        tokenA.mint(100e18);
        IERC20(stbl).approve(address(xStbl), 100e18);
        xStbl.enter(100e18);

        vm.expectRevert(abi.encodeWithSelector(IXSTBL.NOT_WHITELISTED.selector, address(this), address(1)));
        /// forge-lint: disable-next-line
        IERC20(address(xStbl)).transfer(address(1), 1e18);

        address[] memory exemptee = new address[](1);
        exemptee[0] = address(this);
        bool[] memory exempt = new bool[](2);
        vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectArrayLength.selector));
        xStbl.setExemptionFrom(exemptee, exempt);
        vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectArrayLength.selector));
        xStbl.setExemptionTo(exemptee, exempt);
        vm.prank(address(101));
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotGovernanceAndNotMultisig.selector));
        xStbl.setExemptionFrom(exemptee, exempt);
        vm.prank(address(101));
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotGovernanceAndNotMultisig.selector));
        xStbl.setExemptionTo(exemptee, exempt);
        exempt = new bool[](1);
        exempt[0] = true;
        xStbl.setExemptionFrom(exemptee, exempt);

        /// forge-lint: disable-next-line
        IERC20(address(xStbl)).transfer(address(1), 1e18);

        exempt[0] = false;
        xStbl.setExemptionFrom(exemptee, exempt);
        vm.expectRevert(abi.encodeWithSelector(IXSTBL.NOT_WHITELISTED.selector, address(this), address(1)));
        /// forge-lint: disable-next-line
        IERC20(address(xStbl)).transfer(address(1), 1e18);

        exemptee[0] = address(1);
        exempt[0] = true;
        xStbl.setExemptionTo(exemptee, exempt);
        /// forge-lint: disable-next-line
        IERC20(address(xStbl)).transfer(address(1), 1e18);

        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(IXSTBL.NOT_WHITELISTED.selector, address(1), address(2)));
        /// forge-lint: disable-next-line
        IERC20(address(xStbl)).transfer(address(2), 1e18);
    }

    function test_enter_exit() public {
        tokenA.mint(100e18);
        IERC20(stbl).approve(address(xStbl), 100e18);

        // enter
        xStbl.enter(100e18);
        assertEq(IERC20(address(xStbl)).balanceOf(address(this)), 100e18);
        assertEq(IERC20(stbl).balanceOf(address(xStbl)), 100e18);

        // instant exit
        xStbl.exit(50e18);
        assertEq(IERC20(address(xStbl)).balanceOf(address(this)), 50e18);
        assertEq(IERC20(stbl).balanceOf(address(this)), 25e18);
        assertEq(IERC20(stbl).balanceOf(address(xStbl)), 75e18);

        // create vest
        uint time = block.timestamp;
        xStbl.createVest(30e18);
        (uint amount, uint start, uint maxEnd) = xStbl.vestInfo(address(this), 0);
        assertEq(amount, 30e18);
        assertEq(start, time);
        assertEq(maxEnd, time + xStbl.MAX_VEST());
        assertEq(xStbl.usersTotalVests(address(this)), 1);
        assertEq(IERC20(address(xStbl)).balanceOf(address(this)), 20e18);

        // cancel vesting
        vm.warp(time + 13 days);
        xStbl.exitVest(0);
        (amount,,) = xStbl.vestInfo(address(this), 0);
        assertEq(amount, 0);
        assertEq(IERC20(address(xStbl)).balanceOf(address(this)), 50e18);
        assertEq(xStbl.pendingRebase(), 25e18);

        // exit vesting in progress
        time = block.timestamp;
        xStbl.createVest(30e18);
        assertEq(xStbl.usersTotalVests(address(this)), 2);
        vm.warp(time + 179 days);
        xStbl.exitVest(1);
        (amount,,) = xStbl.vestInfo(address(this), 1);
        assertEq(amount, 0);
        assertGt(IERC20(stbl).balanceOf(address(this)), 25e18 + 29e18);
        assertLt(IERC20(stbl).balanceOf(address(this)), 25e18 + 30e18);

        // exit completed vesting
        time = block.timestamp;
        xStbl.createVest(20e18);
        vm.warp(time + 200 days);
        uint balanceWas = IERC20(stbl).balanceOf(address(this));
        xStbl.exitVest(2);
        assertEq(IERC20(stbl).balanceOf(address(this)), balanceWas + 20e18);
    }

    function test_reverts() public {
        vm.expectRevert();
        xStbl.rebase();

        vm.expectRevert();
        xStbl.enter(0);

        vm.expectRevert();
        xStbl.exit(0);

        vm.expectRevert();
        xStbl.createVest(0);

        vm.expectRevert();
        xStbl.exitVest(10);
    }

    function testSlashingPenalty() public {
        address multisig = platform.multisig();

        // --------------------- StabilityDAO is not initialized
        assertEq(xStbl.SLASHING_PENALTY(), 50_00, "50% by default");

        // --------------------- Set up StabilityDAO
        IStabilityDAO daoToken = _createStabilityDAOInstance();

        _setSlashingPenalty(daoToken, 80_00);
        assertEq(xStbl.SLASHING_PENALTY(), 80_00, "80%");

        _setSlashingPenalty(daoToken, 30_00);
        assertEq(xStbl.SLASHING_PENALTY(), 30_00, "30%");

        _setSlashingPenalty(daoToken, 0);
        assertEq(xStbl.SLASHING_PENALTY(), 50_00, "DEFAULT_SLASHING_PENALTY");
    }

    // region --------------------- Helpers
    function _setSlashingPenalty(IStabilityDAO daoToken, uint penalty_) internal {
        address multisig = platform.multisig();

        IStabilityDAO.DaoParams memory config = daoToken.config();
        config.exitPenalty = penalty_;

        vm.prank(multisig);
        daoToken.updateConfig(config);
    }

    function _createStabilityDAOInstance() internal returns (IStabilityDAO) {
        IStabilityDAO.DaoParams memory p = IStabilityDAO.DaoParams({
            minimalPower: 4000e18,
            exitPenalty: 50_00,
            quorum: 20_00,
            proposalThreshold: 10_00,
            powerAllocationDelay: 86400
        });

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new StabilityDAO()));
        IStabilityDAO token = IStabilityDAO(address(proxy));
        token.initialize(address(platform), address(xStbl), address(xStaking), p);
        return token;
    }
    // endregion --------------------- Helpers
}
