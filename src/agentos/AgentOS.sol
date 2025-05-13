// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721EnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IAgentOS} from "../interfaces/IAgentOS.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title AgentOS
/// @notice A system for managing AI agents as NFTs with different capabilities and access levels
/// @dev This contract implements the IAgentOS interface and extends ERC721Enumerable for NFT functionality
/// @dev The contract is upgradeable and uses OpenZeppelin's upgradeable contracts
/// @dev Each agent is represented as an NFT with specific job types (PREDICTOR, TRADER, ANALYZER)
/// @dev Agents can be configured with different disclosure levels (PUBLIC, PRIVATE)
/// @dev The contract manages assets that agents can interact with
/// @author 0xhokugava (https://github.com/0xhokugava)
contract AgentOS is Controllable, ERC721EnumerableUpgradeable, IAgentOS {
    using SafeERC20 for IERC20Metadata;
    using EnumerableSet for EnumerableSet.AddressSet;

    //region ----- Constants -----
    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.AgentOS")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant AGENTOS_STORAGE_LOCATION =
        0x6de3d759e6014104bacf26611b58d959030d8adce765eeaadb352b006a5a7600;
    //endregion ----- Constants -----

    /// @custom:storage-location erc7201:stability.AgentOSStorage
    struct AgentOSStorage {
        IERC20Metadata paymentToken;
        string _baseTokenURI;
        EnumerableSet.AddressSet assets;
        mapping(uint => AgentParams) agentParams;
        mapping(Job => uint) mintCosts;
        mapping(Job => uint) jobFees;
    }

    function init(address platform_, address paymentToken_) public initializer {
        AgentOSStorage storage $ = _getStorage();
        $.paymentToken = IERC20Metadata(paymentToken_);
        __Controllable_init(platform_);
        __ERC721_init("Stability Agent", "SAGENT");
    }

    /// @inheritdoc IAgentOS
    function mint(Job job, Disclosure disclosure, AgentStatus agentStatus, string memory name) public returns (uint) {
        AgentOSStorage storage $ = _getStorage();
        $.paymentToken.safeTransferFrom(_msgSender(), address(this), $.mintCosts[job]);
        uint tokenId = _getNextTokenId();
        _mint(_msgSender(), tokenId);
        $.agentParams[tokenId] = AgentParams({
            job: job,
            disclosure: disclosure,
            agentStatus: AgentStatus.AWAITING,
            name: name,
            lastWorkedAt: 0
        });

        emit AgentCreated(tokenId, job, disclosure, agentStatus, name);
        return tokenId;
    }

    /// @inheritdoc IAgentOS
    function work(uint tokenId, Job job, string memory data) public {
        AgentOSStorage storage $ = _getStorage();
        if (ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        if (
            ownerOf(tokenId) != _msgSender() && getApproved(tokenId) != _msgSender()
                && !isApprovedForAll(ownerOf(tokenId), _msgSender())
        ) revert NotOwnerOrApproved();
        AgentStatus agentStatus = $.agentParams[tokenId].agentStatus;
        if (agentStatus == AgentStatus.AWAITING || agentStatus == AgentStatus.MAINTENANCE) revert AgentNotActive();
        uint jobFee = $.jobFees[job];
        if (jobFee == 0) revert IncorrectZeroArgument();
        $.paymentToken.safeTransferFrom(_msgSender(), address(this), jobFee);

        // TODO: Add logic to work function
        $.agentParams[tokenId].lastWorkedAt = block.timestamp;
        emit AgentWorked(tokenId, job, data);
    }

    function setJobFee(Job job, uint jobFee) public onlyOperator {
        AgentOSStorage storage $ = _getStorage();
        $.jobFees[job] = jobFee;
        emit AgentJobFeeSetted(job, jobFee);
    }

    /// @inheritdoc IAgentOS
    function setAgentStatus(uint tokenId, AgentStatus agentStatus) public onlyOperator {
        AgentOSStorage storage $ = _getStorage();
        $.agentParams[tokenId].agentStatus = agentStatus;
        emit AgentStatusUpdated(tokenId, agentStatus);
    }

    /// @inheritdoc IAgentOS
    function setMintCost(Job job, uint cost) public onlyOperator {
        AgentOSStorage storage $ = _getStorage();
        $.mintCosts[job] = cost;
        emit MintCostUpdated(job, cost);
    }

    /// @inheritdoc IAgentOS
    function setBaseURI(string memory baseURI_) public onlyOperator {
        AgentOSStorage storage $ = _getStorage();
        $._baseTokenURI = baseURI_;
        emit BaseURIUpdated(baseURI_);
    }

    function _baseURI() internal view override returns (string memory) {
        AgentOSStorage storage $ = _getStorage();
        return $._baseTokenURI;
    }

    /// @inheritdoc IAgentOS
    function addAsset(address tokenAddress) public onlyOperator {
        AgentOSStorage storage $ = _getStorage();
        if (!$.assets.add(tokenAddress)) revert AssetAlreadyActive();
        $.assets.add(tokenAddress);
        emit AssetAdded(tokenAddress);
    }

    /// @inheritdoc IAgentOS
    function removeAsset(address tokenAddress) public onlyOperator {
        AgentOSStorage storage $ = _getStorage();
        if (!$.assets.remove(tokenAddress)) revert AssetNotActive();
        $.assets.remove(tokenAddress);
        emit AssetRemoved(tokenAddress);
    }

    /// @inheritdoc IAgentOS
    function getAllAssets() external view returns (address[] memory) {
        AgentOSStorage storage $ = _getStorage();
        return $.assets.values();
    }

    /// @inheritdoc IAgentOS
    function getAgentParams(uint tokenId) public view returns (AgentParams memory) {
        AgentOSStorage storage $ = _getStorage();
        if (ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        return $.agentParams[tokenId];
    }

    function _getNextTokenId() private view returns (uint) {
        return totalSupply() + 1;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Controllable, ERC721EnumerableUpgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IAgentOS).interfaceId || interfaceId == type(IControllable).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //region ----- Internal logic -----
    function _getStorage() private pure returns (AgentOSStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := AGENTOS_STORAGE_LOCATION
        }
    }
    //endregion ----- Internal logic -----
}
