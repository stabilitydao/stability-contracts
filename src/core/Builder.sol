// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

//import {console} from "forge-std/Test.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {Controllable} from "./base/Controllable.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IBuilder} from "../interfaces/IBuilder.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Decentralized platform builder
/// @author Alien Deployer (https://github.com/a17)
contract Builder is Controllable, ERC721Upgradeable, ReentrancyGuardUpgradeable, IBuilder {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Version of Builder contract implementation
    string public constant VERSION = "1.0.0";

    /// @notice Contract uses 2 decimals to represent dollar amount
    uint48 public constant USD_DENOMINATOR = 1_00;

    /// @notice Minimum USD amount for the first investment by the user
    uint48 public constant MIN_AMOUNT_FOR_MINTING = 10_00;

    /// @notice Minimum USD amount for investment by existing user
    uint48 public constant MIN_AMOUNT_FOR_ADDING = 1_00;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.Builder")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant BUILDER_STORAGE_LOCATION =
        0xb43e9b39f8b177b6f23ef5d977f7f3bce46e298c7c0f146b78fa5d5641b83f00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.Builder
    struct BuilderStorage {
        uint newTokenId;
        mapping(address owner => uint tokenId) ownedToken;
        mapping(uint tokenId => TokenData) tokenData;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(address platform_) external initializer {
        __Controllable_init(platform_);
        __ReentrancyGuard_init();
        __ERC721_init("Stability Builder", "BUILDER");
        BuilderStorage storage $ = _getStorage();
        $.newTokenId = 1;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBuilder
    function invest(address asset, uint amount) external nonReentrant returns (uint48 amountUSD) {
        IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());
        (uint price, bool trusted) = priceReader.getPrice(asset);
        if (!trusted) {
            revert NotTrustedPriceFor(asset);
        }
        amountUSD = uint48(amount * price / 10 ** IERC20Metadata(asset).decimals() * USD_DENOMINATOR / 1e18);
        if (amountUSD == 0) {
            revert ZeroAmountToInvest();
        }

        BuilderStorage storage $ = _getStorage();
        uint tokenId = $.ownedToken[msg.sender];

        if (tokenId == 0) {
            if (amountUSD < MIN_AMOUNT_FOR_MINTING) {
                revert TooLittleAmountToInvest(amountUSD, MIN_AMOUNT_FOR_MINTING);
            }
            tokenId = $.newTokenId;
            $.newTokenId = tokenId + 1;
            $.ownedToken[msg.sender] = tokenId;
            _mint(msg.sender, tokenId);
        } else {
            if (amountUSD < MIN_AMOUNT_FOR_ADDING) {
                revert TooLittleAmountToInvest(amountUSD, MIN_AMOUNT_FOR_ADDING);
            }
        }

        TokenData storage tokenData = $.tokenData[tokenId];
        tokenData.invested += amountUSD;

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        emit Invested(msg.sender, tokenId, asset, amount, amountUSD);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc Controllable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable, Controllable)
        returns (bool)
    {
        return interfaceId == type(IControllable).interfaceId || super.supportsInterface(interfaceId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getStorage() private pure returns (BuilderStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := BUILDER_STORAGE_LOCATION
        }
    }
}
