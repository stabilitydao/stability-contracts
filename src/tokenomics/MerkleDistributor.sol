// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IMintedERC20} from "../interfaces/IMintedERC20.sol";
import {IMerkleDistributor} from "../interfaces/IMerkleDistributor.sol";

/// @title Distributor of rewards by merkle tree
/// @author Alien Deployer (https://github.com/a17)
contract MerkleDistributor is Controllable, IMerkleDistributor {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.MerkleDistributor")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant MERKLE_DISTRIBUTOR_STORAGE_LOCATION =
        0x3e9d88d86d20762bcc7bea2229f38a1e184cc95fd3b3a0c7dfbbe6de9a301700;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct Campaign {
        address token;
        uint totalAmount;
        bytes32 merkleRoot;
        mapping(address user => bool isClaimed) claimed;
    }

    /// @custom:storage-location erc7201:stability.MerkleDistributor
    struct MerkleDistributorStorage {
        mapping(bytes32 campaignIdHash => Campaign campaign) campaigns;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMerkleDistributor
    function initialize(address platform_) external initializer {
        __Controllable_init(platform_);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMerkleDistributor
    function setupCampaign(
        string memory campaignId,
        address token,
        uint totalAmount,
        bytes32 merkleRoot,
        bool mint
    ) external onlyGovernanceOrMultisig {
        bytes32 campaignIdHash = _campaignHash(campaignId);
        if (mint) {
            IMintedERC20(token).mint(address(this), totalAmount);
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);
        }
        MerkleDistributorStorage storage $ = _getMerkleDistributorStorage();
        Campaign storage _campaign = $.campaigns[campaignIdHash];
        _campaign.token = token;
        _campaign.totalAmount = totalAmount;
        _campaign.merkleRoot = merkleRoot;
        emit NewCampaign(campaignId, token, totalAmount, merkleRoot, mint);
    }

    /// @inheritdoc IMerkleDistributor
    function claimForUserWhoCantClaim(
        address user,
        string[] memory campaignIds,
        uint[] memory amounts,
        bytes32[][] memory proofs,
        address receiver
    ) external onlyOperator {
        _claim(user, campaignIds, amounts, proofs, receiver);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMerkleDistributor
    function claim(
        string[] memory campaignIds,
        uint[] memory amounts,
        bytes32[][] memory proofs,
        address receiver
    ) external {
        _claim(msg.sender, campaignIds, amounts, proofs, receiver);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMerkleDistributor
    function campaign(string memory campaignId)
        external
        view
        returns (address token, uint totalAmount, bytes32 merkleRoot)
    {
        MerkleDistributorStorage storage $ = _getMerkleDistributorStorage();
        Campaign storage _campaign = $.campaigns[_campaignHash(campaignId)];
        return (_campaign.token, _campaign.totalAmount, _campaign.merkleRoot);
    }

    /// @inheritdoc IMerkleDistributor
    function claimed(address user, string[] memory campaignIds) external view returns (bool[] memory isClaimed) {
        uint len = campaignIds.length;
        isClaimed = new bool[](len);
        MerkleDistributorStorage storage $ = _getMerkleDistributorStorage();
        for (uint i; i < len; ++i) {
            Campaign storage _campaign = $.campaigns[_campaignHash(campaignIds[i])];
            isClaimed[i] = _campaign.claimed[user];
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _campaignHash(string memory campaignId) internal pure returns (bytes32) {
        return keccak256(bytes(campaignId));
    }

    function _claim(
        address user,
        string[] memory campaignIds,
        uint[] memory amounts,
        bytes32[][] memory proofs,
        address receiver
    ) internal {
        uint len = campaignIds.length;
        if (len == 0 || len != proofs.length || len != amounts.length) {
            revert IControllable.IncorrectArrayLength();
        }

        MerkleDistributorStorage storage $ = _getMerkleDistributorStorage();

        for (uint i; i < len; ++i) {
            bytes32 campaignIdHash = _campaignHash(campaignIds[i]);
            Campaign storage _campaign = $.campaigns[campaignIdHash];

            if (_campaign.token == address(0)) {
                revert IControllable.IncorrectZeroArgument();
            }

            if (!_verify(proofs[i], user, amounts[i], _campaign.merkleRoot)) {
                revert InvalidProof();
            }

            if (_campaign.claimed[user]) {
                revert AlreadyClaimed();
            }

            _campaign.claimed[user] = true;

            IERC20(_campaign.token).safeTransfer(receiver, amounts[i]);
            emit RewardClaimed(campaignIds[i], user, amounts[i], receiver);
        }
    }

    function _verify(
        bytes32[] memory proof,
        address addr,
        uint amount,
        bytes32 merkleRoot_
    ) internal pure returns (bool) {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr, amount))));
        return MerkleProof.verify(proof, merkleRoot_, leaf);
    }

    function _getMerkleDistributorStorage() internal pure returns (MerkleDistributorStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := MERKLE_DISTRIBUTOR_STORAGE_LOCATION
        }
    }
}
