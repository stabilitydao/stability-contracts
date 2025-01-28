// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {StrategyBase} from "./StrategyBase.sol";
import {LPStrategyBase} from "./LPStrategyBase.sol";
import {VaultTypeLib} from "../../core/libs/VaultTypeLib.sol";
import {ALMLib} from "../libs/ALMLib.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {ILPStrategy} from "../../interfaces/ILPStrategy.sol";
import {IALM} from "../../interfaces/IALM.sol";
import {ICAmmAdapter} from "../../interfaces/ICAmmAdapter.sol";
import {IHardWorker} from "../../interfaces/IHardWorker.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IControllable} from "../../interfaces/IControllable.sol";

/// @title Stability ALM
/// @author Alien Deployer (https://github.com/a17)
abstract contract ALMStrategyBase is LPStrategyBase, IALM {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Version of ALMStrategyBase implementation
    string public constant VERSION_ALM_STRATEGY_BASE = "1.0.0";

    // todo
    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.ALMStrategyBase")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant ALM_STRATEGY_BASE_STORAGE_LOCATION =
        0xa6fdc931ca23c69f54119a0a2d6478619b5aa365084590a1fbc287668fbabe00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    //slither-disable-next-line naming-convention
    function __ALMStrategyBase_init(
        LPStrategyBaseInitParams memory lpParams,
        ALMStrategyBaseInitParams memory almParams
    ) internal onlyInitializing {
        __LPStrategyBase_init(lpParams);
        ALMStrategyBaseStorage storage $ = _getALMStrategyBaseStorage();
        $.algoId = almParams.algoId;
        $.params = almParams.params;
        $.nft = almParams.nft;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IALM).interfaceId || interfaceId == type(ILPStrategy).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IStrategy
    function supportedVaultTypes() external view virtual override returns (string[] memory types) {
        types = new string[](1);
        types[0] = VaultTypeLib.COMPOUNDING;
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() public view returns (uint[] memory proportions) {
        return ALMLib.getAssetsProportions(
            _getALMStrategyBaseStorage(), _getLPStrategyBaseStorage(), _getStrategyBaseStorage()
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           IALM                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IALM
    function positions() external view returns (Position[] memory) {
        ALMStrategyBaseStorage storage $ = _getALMStrategyBaseStorage();
        return $.positions;
    }

    /// @inheritdoc IALM
    function preset()
        external
        view
        returns (uint algoId, string memory algoName, string memory presetName, int24[] memory params)
    {
        return ALMLib.preset(_getALMStrategyBaseStorage());
    }

    /// @inheritdoc IALM
    function needRebalance() external view returns (bool) {
        return ALMLib.needRebalance(_getALMStrategyBaseStorage(), _getLPStrategyBaseStorage());
    }

    /// @inheritdoc IALM
    function rebalance(bool[] memory burnOldPositions, NewPosition[] memory mintNewPositions) external {
        IPlatform _platform = IPlatform(platform());
        IHardWorker hardworker = IHardWorker(_platform.hardWorker());
        address rebalancer = _platform.rebalancer();
        if (
            msg.sender != rebalancer && !_platform.isOperator(msg.sender)
                && !hardworker.dedicatedServerMsgSender(msg.sender)
        ) {
            revert IControllable.IncorrectMsgSender();
        }
        _rebalance(burnOldPositions, mintNewPositions);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        return
            ALMLib.assetsAmounts(_getALMStrategyBaseStorage(), _getLPStrategyBaseStorage(), _getStrategyBaseStorage());
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        view
        virtual
        override
        returns (uint[] memory amountsConsumed, uint value)
    {
        return ALMLib.previewDepositAssets(
            amountsMax, _getALMStrategyBaseStorage(), _getLPStrategyBaseStorage(), _getStrategyBaseStorage()
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*         Must be implemented by derived contracts           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _rebalance(bool[] memory burnOldPositions, NewPosition[] memory mintNewPositions) internal virtual;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getALMStrategyBaseStorage() internal pure returns (ALMStrategyBaseStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := ALM_STRATEGY_BASE_STORAGE_LOCATION
        }
    }
}
