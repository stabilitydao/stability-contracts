// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./base/ERC4626StrategyBase.sol";
import "./libs/StrategyIdLib.sol";
import "../integrations/silo/ISiloIncentivesController.sol";
import "../integrations/silo/ISilo.sol";
import "../integrations/silo/ISiloConfig.sol";

/// @title Earns APR by lending assets on Silo V2
/// @author 0xhokugava (https://github.com/0xhokugava)
contract SiloStrategy is ERC4626StrategyBase {
    using SafeERC20 for IERC20;
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 3 || nums.length != 0 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }
        __ERC4626StrategyBase_init(StrategyIdLib.SILO, addresses[0], addresses[1], addresses[2]);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.SILO;
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x00d395), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        return _genDesc($base._underlying);
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        return (CommonLib.u2s(_getMarketId($base._underlying)), true);
    }

    /// @inheritdoc IStrategy
    function supportedVaultTypes() external pure override returns (string[] memory types) {
        types = new string[](1);
        types[0] = VaultTypeLib.COMPOUNDING;
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_)
        public
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        IFactory.StrategyAvailableInitParams memory params =
            IFactory(IPlatform(platform_).factory()).strategyAvailableInitParams(keccak256(bytes(strategyLogicId())));
        uint len = params.initAddresses.length;
        variants = new string[](len);
        addresses = new address[](len);
        nums = new uint[](0);
        ticks = new int24[](0);
        for (uint i; i < len; ++i) {
            variants[i] = _genDesc(params.initAddresses[i]);
            addresses[i] = params.initAddresses[i];
        }
    }

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool) {
        return true;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc ERC4626StrategyBase
    //slither-disable-next-line unused-return
    function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        address u = $base._underlying;
        ERC4626StrategyBaseStorage storage $ = _getERC4626StrategyBaseStorage();
        if ($.lastSharePrice == 0) {
            $.lastSharePrice = _getSharePrice(u);
        }
        ISilo siloVault = ISilo(u);
        value = siloVault.deposit(amounts[0], address(this), ISilo.CollateralType.Collateral);
    }

    /// @inheritdoc ERC4626StrategyBase
    //slither-disable-next-line unused-return
    function _withdrawAssets(
        address[] memory,
        uint value,
        address receiver
    ) internal virtual override returns (uint[] memory amountsOut) {
        amountsOut = new uint[](1);
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        ISilo silo = ISilo($base._underlying);
        amountsOut[0] = silo.redeem(value, receiver, address(this));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _genDesc(address silo) internal view returns (string memory) {
        return string.concat(
            "Earn ",
            " and supply APR by lending ",
            IERC20Metadata(ISilo(silo).asset()).symbol(),
            " to Silo V2 ",
            CommonLib.u2s(_getMarketId(silo))
        );
    }

    function _getMarketId(address _silo) internal view returns (uint marketId) {
        marketId = ISiloConfig(ISilo(_silo).siloConfig()).SILO_ID();
    }
}
