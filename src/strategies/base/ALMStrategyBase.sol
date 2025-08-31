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
import {IHardWorker} from "../../interfaces/IHardWorker.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IControllable} from "../../interfaces/IControllable.sol";

/// @title Stability ALM
/// Changelog:
///   1.1.1: Not need re-balance when cant move range
///   1.1.0: Fill-Up algo deposits to base range only
/// @author Alien Deployer (https://github.com/a17)
abstract contract ALMStrategyBase is LPStrategyBase, IALM {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Version of ALMStrategyBase implementation
    string public constant VERSION_ALM_STRATEGY_BASE = "1.1.1";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.ALMStrategyBase")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant ALM_STRATEGY_BASE_STORAGE_LOCATION =
        0xa7b5cf2e827fe3bcf3fe6a0f3315b77285780eac3248f46a43fc1c44c1d47900;

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
        $.nft = almParams.nft;

        $.algoId = almParams.algoId;
        $.params = almParams.params;
        emit ALMParams(almParams.algoId, almParams.params);

        $.priceChangeProtection = true;
        $.twapInterval = 600;
        $.priceThreshold = 10_000;
        emit PriceChangeProtectionParams(true, 600, 10_000);
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
        //slither-disable-next-line unused-return
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
        // todo remove rebalancer address
        address rebalancer = _platform.rebalancer();
        if (
            msg.sender != rebalancer && !_platform.isOperator(msg.sender)
                && !hardworker.dedicatedServerMsgSender(msg.sender)
        ) {
            revert IControllable.IncorrectMsgSender();
        }
        _rebalance(burnOldPositions, mintNewPositions);
    }

    /// @inheritdoc IALM
    function setupPriceChangeProtection(bool enabled, uint32 twapInterval, uint priceThreshold) external onlyOperator {
        ALMStrategyBaseStorage storage $ = _getALMStrategyBaseStorage();
        $.priceChangeProtection = enabled;
        $.twapInterval = twapInterval;
        $.priceThreshold = priceThreshold;
        emit PriceChangeProtectionParams(enabled, twapInterval, priceThreshold);
    }

    /// @inheritdoc IALM
    function setupALMParams(uint algoId, int24[] memory params) external onlyOperator {
        ALMStrategyBaseStorage storage $ = _getALMStrategyBaseStorage();
        $.algoId = algoId;
        $.params = params;
        emit ALMParams(algoId, params);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        //slither-disable-next-line unused-return
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
        //slither-disable-next-line unused-return
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
