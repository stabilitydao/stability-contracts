// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721EnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
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
        address[] activePredictionAssets;
        string _baseTokenURI;
        mapping(uint => AgentParams) agentParams;
        mapping(Job => uint) mintCosts;
        mapping(address => Asset) assets;
    }

    function init(address platform_, address paymentToken_) public initializer {
        AgentOSStorage storage $ = _getStorage();
        $.paymentToken = IERC20Metadata(paymentToken_);
        __Controllable_init(platform_);
        __ERC721_init("Stability Agent", "SAGENT");
    }

    /// @inheritdoc IAgentOS
    function mint(Job job, Disclosure disclosure, string memory name) public returns (uint) {
        AgentOSStorage storage $ = _getStorage();
        if ($.paymentToken.balanceOf(_msgSender()) < $.mintCosts[job]) revert InsufficientPayment();
        if ($.paymentToken.allowance(_msgSender(), address(this)) < $.mintCosts[job]) revert InsufficientPayment();
        $.paymentToken.transferFrom(_msgSender(), address(this), $.mintCosts[job]);

        uint tokenId = _getNextTokenId();
        _mint(_msgSender(), tokenId);

        $.agentParams[tokenId] =
            AgentParams({job: job, disclosure: disclosure, name: name, isActive: true, lastWorkedAt: 0});

        emit AgentCreated(tokenId, job, disclosure, name);
        return tokenId;
    }

    /// @inheritdoc IAgentOS
    function work(uint tokenId, string memory data) public {
        AgentOSStorage storage $ = _getStorage();
        if (ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        if (
            ownerOf(tokenId) != _msgSender() && getApproved(tokenId) != _msgSender()
                && !isApprovedForAll(ownerOf(tokenId), _msgSender())
        ) revert NotOwnerOrApproved();
        if (!$.agentParams[tokenId].isActive) revert AgentNotActive();
        // TODO: Add logic to work function
        $.agentParams[tokenId].lastWorkedAt = block.timestamp;
        emit AgentWorked(tokenId, data);
    }

    /// @inheritdoc IAgentOS
    function updateMintCost(Job job, uint cost) public onlyOperator {
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
    function addAsset(address tokenAddress, string memory symbol) public onlyOperator {
        AgentOSStorage storage $ = _getStorage();
        if (tokenAddress == address(0)) revert InvalidTokenAddress();
        if (bytes(symbol).length == 0) revert InvalidSymbol();
        if ($.assets[tokenAddress].isActive) revert AssetAlreadyActive();

        $.assets[tokenAddress] =
            Asset({tokenAddress: tokenAddress, symbol: symbol, isActive: true, lastUpdated: block.timestamp});

        $.activePredictionAssets.push(tokenAddress);
        emit AssetAdded(tokenAddress, symbol);
    }

    /// @inheritdoc IAgentOS
    function removeAsset(address tokenAddress) public onlyOperator {
        AgentOSStorage storage $ = _getStorage();
        if (!$.assets[tokenAddress].isActive) revert AssetNotActive();

        $.assets[tokenAddress].isActive = false;
        $.assets[tokenAddress].lastUpdated = block.timestamp;
        for (uint i = 0; i < $.activePredictionAssets.length; i++) {
            if ($.activePredictionAssets[i] == tokenAddress) {
                $.activePredictionAssets[i] = $.activePredictionAssets[$.activePredictionAssets.length - 1];
                $.activePredictionAssets.pop();
                break;
            }
        }

        emit AssetRemoved(tokenAddress);
    }

    /// @inheritdoc IAgentOS
    function updateAssetStatus(address tokenAddress, bool isActive) public onlyOperator {
        AgentOSStorage storage $ = _getStorage();
        if ($.assets[tokenAddress].tokenAddress == address(0)) {
            revert AssetNotFound();
        }
        if ($.assets[tokenAddress].isActive == isActive) {
            revert StatusAlreadySet();
        }

        $.assets[tokenAddress].isActive = isActive;
        $.assets[tokenAddress].lastUpdated = block.timestamp;

        if (isActive) {
            $.activePredictionAssets.push(tokenAddress);
        } else {
            for (uint i = 0; i < $.activePredictionAssets.length; i++) {
                if ($.activePredictionAssets[i] == tokenAddress) {
                    $.activePredictionAssets[i] = $.activePredictionAssets[$.activePredictionAssets.length - 1];
                    $.activePredictionAssets.pop();
                    break;
                }
            }
        }

        emit AssetStatusUpdated(tokenAddress, isActive);
    }

    /// @inheritdoc IAgentOS
    function getActiveAssets() public view returns (address[] memory) {
        AgentOSStorage storage $ = _getStorage();
        return $.activePredictionAssets;
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
