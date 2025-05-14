// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {MockSetup} from "../base/MockSetup.sol";
import {AgentOS} from "../../src/agentos/AgentOS.sol";
import {IAgentOS} from "../../src/interfaces/IAgentOS.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";

contract AgentOSTest is Test, MockSetup {
    AgentOS public agentOS;
    address public operator;
    address public user;
    uint public constant INITIAL_BALANCE = 100_000 ether;

    constructor() {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"));
        vm.rollFork(26315414);
    }

    function setUp() public {
        user = makeAddr("user");
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new AgentOS()));
        agentOS = AgentOS(address(proxy));
        agentOS.init(address(platform), SonicConstantsLib.TOKEN_STBL);
        platform.addOperator(operator);

        deal(SonicConstantsLib.TOKEN_STBL, user, INITIAL_BALANCE);
        deal(SonicConstantsLib.TOKEN_STBL, operator, INITIAL_BALANCE);

        vm.startPrank(operator);
        agentOS.setMintCost(IAgentOS.Job.PREDICTOR, 1 ether);
        agentOS.setMintCost(IAgentOS.Job.TRADER, 2 ether);
        agentOS.setMintCost(IAgentOS.Job.ANALYZER, 3 ether);
        agentOS.setJobFee(IAgentOS.Job.PREDICTOR, 0.1 ether);
        agentOS.setJobFee(IAgentOS.Job.TRADER, 0.2 ether);
        agentOS.setJobFee(IAgentOS.Job.ANALYZER, 0.3 ether);
        vm.stopPrank();
    }

    function test_Initialization() public view {
        assertEq(agentOS.name(), "Stability Agent");
        assertEq(agentOS.symbol(), "SAGENT");
    }

    function test_MintAgent() public {
        vm.startPrank(user);
        IERC20Metadata(SonicConstantsLib.TOKEN_STBL).approve(address(agentOS), 1 ether);
        uint tokenId =
            agentOS.mint(IAgentOS.Job.PREDICTOR, IAgentOS.Disclosure.PUBLIC, IAgentOS.AgentStatus.AWAITING, "TestAgent");

        IAgentOS.AgentParams memory params = agentOS.getAgentParams(tokenId);
        assertEq(uint(params.job), uint(IAgentOS.Job.PREDICTOR));
        assertEq(uint(params.disclosure), uint(IAgentOS.Disclosure.PUBLIC));
        assertEq(uint(params.agentStatus), uint(IAgentOS.AgentStatus.AWAITING));
        assertEq(params.name, "TestAgent");
        assertEq(params.lastWorkedAt, 0);
        assertEq(agentOS.ownerOf(tokenId), user);

        vm.stopPrank();
    }

    function test_WorkAgent() public {
        vm.startPrank(user);
        IERC20Metadata(SonicConstantsLib.TOKEN_STBL).approve(address(agentOS), 1 ether);
        uint tokenId =
            agentOS.mint(IAgentOS.Job.PREDICTOR, IAgentOS.Disclosure.PUBLIC, IAgentOS.AgentStatus.AWAITING, "TestAgent");
        vm.stopPrank();
        vm.prank(operator);
        agentOS.setAgentStatus(tokenId, IAgentOS.AgentStatus.ACTIVE);
        vm.startPrank(user);
        IERC20Metadata(SonicConstantsLib.TOKEN_STBL).approve(address(agentOS), 0.1 ether);
        agentOS.work(tokenId, IAgentOS.Job.PREDICTOR, "test data");
        IAgentOS.AgentParams memory params = agentOS.getAgentParams(tokenId);
        assertTrue(params.lastWorkedAt > 0);

        vm.stopPrank();
    }

    function test_SetAgentStatus() public {
        vm.startPrank(user);
        IERC20Metadata(SonicConstantsLib.TOKEN_STBL).approve(address(agentOS), 1 ether);
        uint tokenId =
            agentOS.mint(IAgentOS.Job.PREDICTOR, IAgentOS.Disclosure.PUBLIC, IAgentOS.AgentStatus.AWAITING, "TestAgent");

        vm.stopPrank();
        vm.prank(operator);
        agentOS.setAgentStatus(tokenId, IAgentOS.AgentStatus.ACTIVE);
        IAgentOS.AgentParams memory params = agentOS.getAgentParams(tokenId);
        assertEq(uint(params.agentStatus), uint(IAgentOS.AgentStatus.ACTIVE));
    }

    function test_AddRemoveAsset() public {
        address newAsset = SonicConstantsLib.TOKEN_wS;
        vm.prank(operator);
        agentOS.addAsset(newAsset);
        address[] memory assets = agentOS.getAllAssets();
        assertEq(assets[0], newAsset);
        vm.prank(operator);
        agentOS.removeAsset(newAsset);
        assets = agentOS.getAllAssets();
        assertEq(assets.length, 0);
    }

    function testAddAsset_RevertIf_AssetAlreadyActive() public {
        address newAsset = SonicConstantsLib.TOKEN_wS;
        vm.prank(operator);
        agentOS.addAsset(newAsset);
        vm.expectRevert();
        agentOS.addAsset(newAsset);
        vm.stopPrank();
    }

    function testRemoveAsset_RevertIf_AssetNotActive() public {
        address newAsset = SonicConstantsLib.TOKEN_wS;
        vm.prank(operator);
        vm.expectRevert();
        agentOS.removeAsset(newAsset);
        vm.stopPrank();
    }

    function test_SetBaseURI() public {
        string memory newBaseURI = "https://example.com/";
        vm.prank(operator);
        agentOS.setBaseURI(newBaseURI);
    }

    function testWork_RevertIf_WorkWithInactiveAgent() public {
        vm.startPrank(user);
        IERC20Metadata(SonicConstantsLib.TOKEN_STBL).approve(address(agentOS), 1 ether);
        uint tokenId =
            agentOS.mint(IAgentOS.Job.PREDICTOR, IAgentOS.Disclosure.PUBLIC, IAgentOS.AgentStatus.AWAITING, "TestAgent");
        IERC20Metadata(SonicConstantsLib.TOKEN_STBL).approve(address(agentOS), 0.1 ether);
        vm.expectRevert();
        agentOS.work(tokenId, IAgentOS.Job.PREDICTOR, "test data");
        vm.stopPrank();
    }

    function testWork_RevertIf_TokenDoesNotExist() public {
        vm.startPrank(user);
        IERC20Metadata(SonicConstantsLib.TOKEN_STBL).approve(address(agentOS), 1 ether);
        vm.expectRevert();
        agentOS.work(type(uint).max, IAgentOS.Job.PREDICTOR, "test data");
        vm.stopPrank();
    }

    function testWork_RevertIf_NotOwnerOrApproved() public {
        vm.startPrank(user);
        IERC20Metadata(SonicConstantsLib.TOKEN_STBL).approve(address(agentOS), 1 ether);
        uint tokenId =
            agentOS.mint(IAgentOS.Job.PREDICTOR, IAgentOS.Disclosure.PUBLIC, IAgentOS.AgentStatus.AWAITING, "TestAgent");
        vm.stopPrank();
        vm.prank(operator);
        agentOS.setAgentStatus(tokenId, IAgentOS.AgentStatus.ACTIVE);
        vm.startPrank(user);
        vm.expectRevert();
        agentOS.work(tokenId, IAgentOS.Job.PREDICTOR, "test data");
        vm.stopPrank();
    }

    function testWork_RevertIf_WorkWithInsufficientPayment() public {
        vm.startPrank(user);
        IERC20Metadata(SonicConstantsLib.TOKEN_STBL).approve(address(agentOS), 1 ether);
        uint tokenId =
            agentOS.mint(IAgentOS.Job.PREDICTOR, IAgentOS.Disclosure.PUBLIC, IAgentOS.AgentStatus.AWAITING, "TestAgent");
        vm.stopPrank();
        vm.prank(operator);
        agentOS.setAgentStatus(tokenId, IAgentOS.AgentStatus.ACTIVE);
        vm.startPrank(user);
        vm.expectRevert();
        agentOS.work(tokenId, IAgentOS.Job.PREDICTOR, "test data");
        vm.stopPrank();
    }

    function testGetAgentParams_RevertIf_TokenDoesNotExist() public {
        vm.startPrank(operator);
        vm.expectRevert();
        agentOS.getAgentParams(type(uint).max);
        vm.stopPrank();
    }

    function testErc165() public view {
        assertEq(agentOS.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(agentOS.supportsInterface(type(IControllable).interfaceId), true);
        assertEq(agentOS.supportsInterface(type(IAgentOS).interfaceId), true);
    }
}
