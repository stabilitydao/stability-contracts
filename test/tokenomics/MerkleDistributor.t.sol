// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {MockSetup} from "../base/MockSetup.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {MerkleDistributor} from "../../src/tokenomics/MerkleDistributor.sol";
import {Token} from "../../src/tokenomics/Token.sol";
import {IMerkleDistributor} from "../../src/interfaces/IMerkleDistributor.sol";

contract MerkleDistributorTest is Test, MockSetup {
    IMerkleDistributor public merkleDistributor;
    Token public token;

    function setUp() public {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new MerkleDistributor()));
        merkleDistributor = IMerkleDistributor(address(proxy));
        merkleDistributor.initialize(address(platform));
        token = new Token(address(merkleDistributor), "Gem token", "sGEM1");
        // console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.MerkleDistributor")) - 1)) & ~bytes32(uint256(0xff)));
    }

    function test_MerkleDistributor() public {
        bytes32 root = 0x644a8a8eecf5154d3a52966b43f7ce22899b2993682c44ee431af6d6a50363d4;
        string memory contestId = "y10";
        vm.expectRevert();
        vm.prank(address(1));
        merkleDistributor.setupCampaign(contestId, address(token), 900_000e18, root, true);

        merkleDistributor.setupCampaign(contestId, address(token), 900_000e18, root, true);

        assertEq(token.balanceOf(address(merkleDistributor)), 900_000e18);
        (address _token, uint totalAmount, bytes32 merkleRoot) = merkleDistributor.campaign(contestId);
        assertEq(_token, address(token));
        assertEq(totalAmount, 900_000e18);
        assertEq(merkleRoot, root);
        (_token,,) = merkleDistributor.campaign("qqq");
        assertEq(_token, address(0));

        address user1 = 0x0644141DD9C2c34802d28D334217bD2034206Bf7; // 561041.6903433417
        address user2 = 0x88888887C3ebD4a33E34a15Db4254C74C75E5D4A; // 18311.931634183446

        string[] memory campaignIds = new string[](1);
        campaignIds[0] = contestId;
        uint[] memory amounts = new uint[](1);
        amounts[0] = 561041690343341700000000;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](7);
        proofs[0][0] = 0xbc5b9405195c98e699456a0d1030b3bcd1495213400d8b9eedd90ca715902a58;
        proofs[0][1] = 0x74194f96dedde0a62af8aa32a44df3faf540465525519d21f9a187b754124773;
        proofs[0][2] = 0x98da77b74e6ae9d4ab64af827a40a4b9e9e37c96e3359079f20c59284795484c;
        proofs[0][3] = 0x11e5607ed6ed10b4efac28bae25d43288779303557b64ab4202ef358ffafeca8;
        proofs[0][4] = 0xac46be16e1dbd661e3c392bb75aa37158b58e4501d885a97de83b89c2c3239f5;
        proofs[0][5] = 0xa1f911961b0385266dc15ea644ea0784d5280d5d791aaef59f0b3d41e1158154;
        proofs[0][6] = 0x30c763cb397b3e017dad2ae191e4f3575a4ea1981562c45752f7428736dd88fd;
        vm.expectRevert(IMerkleDistributor.InvalidProof.selector);
        merkleDistributor.claim(campaignIds, amounts, proofs, address(this));

        vm.startPrank(user1);
        merkleDistributor.claim(campaignIds, amounts, proofs, address(this));

        vm.expectRevert(IMerkleDistributor.AlreadyClaimed.selector);
        merkleDistributor.claim(campaignIds, amounts, proofs, address(this));
        vm.stopPrank();

        bool[] memory isClaimed = merkleDistributor.claimed(user1, campaignIds);
        assertEq(isClaimed[0], true);

        amounts[0] = 18311931634183446000000;
        proofs[0][0] = 0x9c588383eb65d21fc728943f98d12c349c9c2454835900b82f6aedb3f6179d2d;
        proofs[0][1] = 0x877bc869f27327e0345dc87ed29f7a1f95354be8099d999f0e0cea427a5515be;
        proofs[0][2] = 0x5edd9538d302a89df43fc762d00de4a6fe78f34cb6c3dca2a86a4c1659c7b84d;
        proofs[0][3] = 0xb255de3e5d145abe796424c1ab16467a386628e1e95b24c382ebc9cbba9a0e86;
        proofs[0][4] = 0x3aa9c3396aa77ff0a55c2d2f9681f037f6a30706640c694ad5266f77f0b6bacc;
        proofs[0][5] = 0xa10c711d2ab1a41f1bc42d178081580cabb9df1bb4b5ed8e1397b2c08d4d95ee;
        proofs[0][6] = 0x30c763cb397b3e017dad2ae191e4f3575a4ea1981562c45752f7428736dd88fd;
        merkleDistributor.claimForUserWhoCantClaim(user2, campaignIds, amounts, proofs, address(10));

        // test not minted token
        contestId = "y200";
        tokenA.mint(900_000e18);
        tokenA.approve(address(merkleDistributor), 900_000e18);
        merkleDistributor.setupCampaign(contestId, address(tokenA), 900_000e18, root, false);
        campaignIds[0] = contestId;
        merkleDistributor.claimForUserWhoCantClaim(user2, campaignIds, amounts, proofs, address(10));
    }
}
