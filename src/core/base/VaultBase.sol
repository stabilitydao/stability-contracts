// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./Controllable.sol";
import "../libs/ConstantsLib.sol";
import "../libs/VaultStatusLib.sol";
import "../libs/VaultBaseLib.sol";
import "../../interfaces/IVault.sol";
import "../../interfaces/IStrategy.sol";
import "../../interfaces/IPriceReader.sol";
import "../../interfaces/IPlatform.sol";
import "../../interfaces/IAprOracle.sol";
import "../../interfaces/IPlatform.sol";
import "../../interfaces/IFactory.sol";

/// @notice Base vault implementation.
///         User can deposit and withdraw a changing set of assets managed by the strategy.
///         Start price of vault share is $1.
/// @dev Used by all vault implementations (CVault, RVault, etc)
/// Changelog:
///   2.0.0: use strategy.previewDepositAssetsWrite; hardWorkMintFeeCallback use platform.getCustomVaultFee
///   1.3.0: hardWorkMintFeeCallback
///   1.2.0: isHardWorkOnDepositAllowed
///   1.1.0: setName, setSymbol, gas optimization
///   1.0.1: add receiver and owner args to withdrawAssets method
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
abstract contract VaultBase is Controllable, ERC20Upgradeable, ReentrancyGuardUpgradeable, IVault {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Version of VaultBase implementation
    string public constant VERSION_VAULT_BASE = "2.0.0";

    /// @dev Delay between deposits/transfers and withdrawals
    uint internal constant _WITHDRAW_REQUEST_BLOCKS = 5;

    /// @dev Initial shares of the vault minted at the first deposit and sent to the dead address.
    uint internal constant _INITIAL_SHARES = 1e15;

    /// @dev Delay for calling strategy.doHardWork() on user deposits
    uint internal constant _MIN_HARDWORK_DELAY = 3600;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.VaultBase")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant _VAULTBASE_STORAGE_LOCATION =
        0xd602ae9af1fed726d4890dcf3c81a074ed87a6343646550e5de293c5a9330a00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Data structure containing local variables for function depositAssets() to avoid stack too deep.
    struct DepositAssetsVars {
        uint _totalSupply;
        uint totalValue;
        uint len;
        address[] assets;
        IStrategy strategy;
        address underlying;
        uint[] amountsConsumed;
        uint value;
        uint mintAmount;
    }

    /// @notice Data structure containing local variables for function getApr() to avoid stack too deep.
    struct GetAprVars {
        address[] strategyAssets;
        uint[] proportions;
        address underlying;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    //slither-disable-next-line naming-convention
    function __VaultBase_init(
        address platform_,
        string memory type_,
        address strategy_,
        string memory name_,
        string memory symbol_,
        uint tokenId_
    ) internal onlyInitializing {
        __Controllable_init(platform_);
        __ERC20_init(name_, symbol_);
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        $._type = type_;
        $.strategy = IStrategy(strategy_);
        $.tokenId = tokenId_;
        __ReentrancyGuard_init();
        $.doHardWorkOnDeposit = IStrategy(strategy_).isHardWorkOnDepositAllowed();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CALLBACKS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Need to receive ETH for HardWork and re-balance gas compensation
    receive() external payable {}

    /// @inheritdoc IVault
    function hardWorkMintFeeCallback(address[] memory revenueAssets, uint[] memory revenueAmounts) external virtual {
        (address[] memory feeReceivers, uint[] memory feeShares) = VaultBaseLib.hardWorkMintFeeCallback(
            IPlatform(platform()), revenueAssets, revenueAmounts, _getVaultBaseStorage()
        );
        uint len = feeReceivers.length;
        for (uint i; i < len; ++i) {
            if (feeShares[i] != 0) {
                _mint(feeReceivers[i], feeShares[i]);
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IVault
    //slither-disable-next-line reentrancy-events
    function doHardWork() external {
        IPlatform _platform = IPlatform(platform());
        // nosemgrep
        if (msg.sender != _platform.hardWorker() && !_platform.isOperator(msg.sender)) {
            revert IncorrectMsgSender();
        }
        uint startGas = gasleft();
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        $.strategy.doHardWork();
        uint gasUsed = startGas - gasleft();
        uint gasCost = gasUsed * tx.gasprice;
        //slither-disable-next-line uninitialized-local
        bool compensated;
        if (gasCost > 0) {
            bool canCompensate = payable(address(this)).balance >= gasCost;
            //slither-disable-next-line unused-return
            if (canCompensate) {
                //slither-disable-next-line low-level-calls
                (bool success,) = msg.sender.call{value: gasCost}("");
                if (!success) {
                    revert IControllable.ETHTransferFailed();
                }
                compensated = true;
            } else {
                //slither-disable-next-line unused-return
                (uint _tvl,) = tvl();
                if (_tvl < IPlatform(platform()).minTvlForFreeHardWork()) {
                    revert NotEnoughBalanceToPay();
                }
            }
        }

        emit HardWorkGas(gasUsed, gasCost, compensated);
    }

    /// @inheritdoc IVault
    function setDoHardWorkOnDeposit(bool value) external onlyGovernanceOrMultisig {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        $.doHardWorkOnDeposit = value;
        emit DoHardWorkOnDepositChanged($.doHardWorkOnDeposit, value);
    }

    /// @inheritdoc IVault
    function setMaxSupply(uint maxShares) public virtual onlyGovernanceOrMultisig {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        $.maxSupply = maxShares;
        emit MaxSupply(maxShares);
    }

    /// @inheritdoc IVault
    function setName(string calldata newName) external onlyOperator {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        $.changedName = newName;
        emit VaultName(newName);
    }

    /// @inheritdoc IVault
    function setSymbol(string calldata newSymbol) external onlyOperator {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        $.changedSymbol = newSymbol;
        emit VaultSymbol(newSymbol);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IVault
    function depositAssets(
        address[] memory assets_,
        uint[] memory amountsMax,
        uint minSharesOut,
        address receiver
    ) external virtual nonReentrant {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        if (IFactory(IPlatform(platform()).factory()).vaultStatus(address(this)) != VaultStatusLib.ACTIVE) {
            revert IFactory.NotActiveVault();
        }

        //slither-disable-next-line uninitialized-local
        DepositAssetsVars memory v;
        v.strategy = $.strategy;

        // slither-disable-start timestamp
        // nosemgrep
        if (
            $.doHardWorkOnDeposit && block.timestamp > v.strategy.lastHardWork() + _MIN_HARDWORK_DELAY
                && v.strategy.isReadyForHardWork()
        ) {
            // slither-disable-end timestamp
            v.strategy.doHardWork();
        }

        v._totalSupply = totalSupply();
        v.totalValue = v.strategy.total();
        // nosemgrep
        if (v._totalSupply != 0 && v.totalValue == 0) {
            revert FuseTrigger();
        }

        v.len = amountsMax.length;
        if (v.len != assets_.length) {
            revert IControllable.IncorrectArrayLength();
        }

        v.assets = v.strategy.assets();
        v.underlying = v.strategy.underlying();

        // nosemgrep
        if (v.len == 1 && v.underlying != address(0) && v.underlying == assets_[0]) {
            v.value = amountsMax[0];
            IERC20(v.underlying).safeTransferFrom(msg.sender, address(v.strategy), v.value);
            (v.amountsConsumed) = v.strategy.depositUnderlying(v.value);
        } else {
            (v.amountsConsumed, v.value) = v.strategy.previewDepositAssetsWrite(assets_, amountsMax);
            // nosemgrep
            for (uint i; i < v.len; ++i) {
                IERC20(v.assets[i]).safeTransferFrom(msg.sender, address(v.strategy), v.amountsConsumed[i]);
            }
            v.value = v.strategy.depositAssets(v.amountsConsumed);
        }

        if (v.value == 0) {
            revert StrategyZeroDeposit();
        }

        v.mintAmount =
            _mintShares($, v._totalSupply, v.value, v.totalValue, v.amountsConsumed, minSharesOut, v.assets, receiver);

        $.withdrawRequests[receiver] = block.number;

        emit DepositAssets(receiver, assets_, v.amountsConsumed, v.mintAmount);
    }

    /// @inheritdoc IVault
    function withdrawAssets(
        address[] memory assets_,
        uint amountShares,
        uint[] memory minAssetAmountsOut
    ) external virtual nonReentrant returns (uint[] memory) {
        return _withdrawAssets(assets_, amountShares, minAssetAmountsOut, msg.sender, msg.sender);
    }

    /// @inheritdoc IVault
    function withdrawAssets(
        address[] memory assets_,
        uint amountShares,
        uint[] memory minAssetAmountsOut,
        address receiver,
        address owner
    ) external virtual nonReentrant returns (uint[] memory) {
        return _withdrawAssets(assets_, amountShares, minAssetAmountsOut, receiver, owner);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function name() public view override returns (string memory) {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        string memory changedName = $.changedName;
        if (bytes(changedName).length > 0) {
            return changedName;
        }
        return super.name();
    }

    function symbol() public view override returns (string memory) {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        string memory changedSymbol = $.changedSymbol;
        if (bytes(changedSymbol).length > 0) {
            return changedSymbol;
        }
        return super.symbol();
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(Controllable, IERC165) returns (bool) {
        return interfaceId == type(IVault).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IVault
    function vaultType() external view returns (string memory) {
        return _getVaultBaseStorage()._type;
    }

    /// @inheritdoc IVault
    function price() external view returns (uint price_, bool trusted_) {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        (address[] memory _assets, uint[] memory _amounts) = $.strategy.assetsAmounts();
        IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());
        uint _tvl;
        //slither-disable-next-line unused-return
        (_tvl,,, trusted_) = priceReader.getAssetsPrice(_assets, _amounts);
        uint __totalSupply = totalSupply();
        if (__totalSupply > 0) {
            price_ = _tvl * 1e18 / __totalSupply;
        }
    }

    /// @inheritdoc IVault
    function tvl() public view returns (uint tvl_, bool trusted_) {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        (address[] memory _assets, uint[] memory _amounts) = $.strategy.assetsAmounts();
        IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());
        //slither-disable-next-line unused-return
        (tvl_,,, trusted_) = priceReader.getAssetsPrice(_assets, _amounts);
    }

    /// @inheritdoc IVault
    function previewDepositAssets(
        address[] memory assets_,
        uint[] memory amountsMax
    ) external view returns (uint[] memory amountsConsumed, uint sharesOut, uint valueOut) {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        IStrategy _strategy = $.strategy;
        (amountsConsumed, valueOut) = _strategy.previewDepositAssets(assets_, amountsMax);
        //slither-disable-next-line unused-return
        (sharesOut,) = _calcMintShares(totalSupply(), valueOut, _strategy.total(), amountsConsumed, _strategy.assets());
    }

    /// @inheritdoc IVault
    function getApr()
        external
        view
        returns (uint totalApr, uint strategyApr, address[] memory assetsWithApr, uint[] memory assetsAprs)
    {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        //slither-disable-next-line uninitialized-local
        GetAprVars memory v;
        IStrategy _strategy = $.strategy;
        strategyApr = _strategy.lastApr();
        totalApr = strategyApr;
        v.strategyAssets = _strategy.assets();
        v.proportions = _strategy.getAssetsProportions();
        v.underlying = _strategy.underlying();
        uint assetsLengthTmp = v.strategyAssets.length;
        if (v.underlying != address(0)) {
            ++assetsLengthTmp;
        }
        uint strategyAssetsLength = v.strategyAssets.length;
        address[] memory queryAprAssets = new address[](assetsLengthTmp);
        // nosemgrep
        for (uint i; i < strategyAssetsLength; ++i) {
            queryAprAssets[i] = v.strategyAssets[i];
        }
        if (v.underlying != address(0)) {
            queryAprAssets[assetsLengthTmp - 1] = v.underlying;
        }
        uint[] memory queryAprs = IAprOracle(IPlatform(platform()).aprOracle()).getAprs(queryAprAssets);
        assetsLengthTmp = 0;
        uint queryAprsLength = queryAprs.length;
        // nosemgrep
        for (uint i; i < queryAprsLength; ++i) {
            if (queryAprs[i] > 0) {
                ++assetsLengthTmp;
            }
        }
        assetsWithApr = new address[](assetsLengthTmp);
        assetsAprs = new uint[](assetsLengthTmp);
        //slither-disable-next-line uninitialized-local
        uint k;
        // nosemgrep
        for (uint i; i < queryAprsLength; ++i) {
            if (queryAprs[i] > 0) {
                assetsWithApr[k] = queryAprAssets[i];
                assetsAprs[k] = queryAprs[i];
                if (i < strategyAssetsLength) {
                    totalApr += assetsAprs[k] * v.proportions[i] / 1e18;
                } else {
                    totalApr += assetsAprs[k];
                }
                ++k;
            }
        }
    }

    /// @inheritdoc IVault
    function getUniqueInitParamLength() public view virtual returns (uint uniqueInitAddresses, uint uniqueInitNums);

    /// @inheritdoc IVault
    function strategy() public view returns (IStrategy) {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        return $.strategy;
    }

    /// @inheritdoc IVault
    function maxSupply() external view returns (uint) {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        return $.maxSupply;
    }

    /// @inheritdoc IVault
    function tokenId() external view returns (uint) {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        return $.tokenId;
    }

    /// @inheritdoc IVault
    function doHardWorkOnDeposit() external view returns (bool) {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        return $.doHardWorkOnDeposit;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getVaultBaseStorage() internal pure returns (VaultBaseStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _VAULTBASE_STORAGE_LOCATION
        }
    }

    /// @dev Minting shares of the vault to the user's address when he deposits funds into the vault.
    ///
    /// During the first deposit, initial shares are also minted and sent to the dead address.
    /// Initial shares save proportion of value to total supply and share price when all users withdraw all their funds from vault.
    /// It prevent flash loan attacks on users' funds.
    /// Also their presence allows the strategy to work without user funds, providing APR for the logic and the farm, if available.
    /// @param totalSupply_ Total supply of shares before deposit
    /// @param value_ Liquidity value or underlying token amount received after deposit
    /// @param amountsConsumed Amounts of strategy assets consumed during the execution of the deposit.
    ///        Consumed amounts used by calculation of minted amount during the first deposit for setting the first share price to 1 USD.
    /// @param minSharesOut Slippage tolerance. Minimal shares amount which must be received by user after deposit
    /// @return mintAmount Amount of minted shares for the user
    function _mintShares(
        VaultBaseStorage storage $,
        uint totalSupply_,
        uint value_,
        uint totalValue_,
        uint[] memory amountsConsumed,
        uint minSharesOut,
        address[] memory assets,
        address receiver
    ) internal returns (uint mintAmount) {
        uint initialShares;
        (mintAmount, initialShares) = _calcMintShares(totalSupply_, value_, totalValue_, amountsConsumed, assets);
        uint _maxSupply = $.maxSupply;
        // nosemgrep
        if (_maxSupply != 0 && mintAmount + totalSupply_ > _maxSupply) {
            revert ExceedMaxSupply(_maxSupply);
        }
        if (mintAmount < minSharesOut) {
            revert ExceedSlippage(mintAmount, minSharesOut);
        }
        if (initialShares > 0) {
            _mint(ConstantsLib.DEAD_ADDRESS, initialShares);
        }
        if (receiver == address(0)) {
            receiver = msg.sender;
        }
        _mint(receiver, mintAmount);
    }

    /// @dev Calculating amount of new shares for given deposited value and totals
    function _calcMintShares(
        uint totalSupply_,
        uint value_,
        uint totalValue_,
        uint[] memory amountsConsumed,
        address[] memory assets
    ) internal view returns (uint mintAmount, uint initialShares) {
        if (totalSupply_ > 0) {
            mintAmount = value_ * totalSupply_ / totalValue_;
            initialShares = 0; // hide warning
        } else {
            // calc mintAmount for USD amount of value
            // its setting sharePrice to 1e18
            IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());
            //slither-disable-next-line unused-return
            (mintAmount,,,) = priceReader.getAssetsPrice(assets, amountsConsumed);

            // initialShares for saving share price after full withdraw
            initialShares = _INITIAL_SHARES;
            if (mintAmount < initialShares * 1000) {
                revert NotEnoughAmountToInitSupply(mintAmount, initialShares * 1000);
            }
            mintAmount -= initialShares;
        }
    }

    function _withdrawAssets(
        address[] memory assets_,
        uint amountShares,
        uint[] memory minAssetAmountsOut,
        address receiver,
        address owner
    ) internal virtual returns (uint[] memory) {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, amountShares);
        }

        if (amountShares == 0) {
            revert IControllable.IncorrectZeroArgument();
        }
        if (amountShares > balanceOf(owner)) {
            revert NotEnoughBalanceToPay();
        }
        if (assets_.length != minAssetAmountsOut.length) {
            revert IControllable.IncorrectArrayLength();
        }

        VaultBaseStorage storage $ = _getVaultBaseStorage();
        _beforeWithdraw($, owner);

        IStrategy _strategy = $.strategy;
        uint localTotalSupply = totalSupply();
        uint totalValue = _strategy.total();

        uint[] memory amountsOut;

        {
            address underlying = _strategy.underlying();
            // nosemgrep
            bool isUnderlyingWithdrawal = assets_.length == 1 && underlying != address(0) && underlying == assets_[0];

            // fuse is not triggered
            if (totalValue > 0) {
                uint value = amountShares * totalValue / localTotalSupply;
                if (isUnderlyingWithdrawal) {
                    amountsOut = new uint[](1);
                    amountsOut[0] = value;
                    _strategy.withdrawUnderlying(amountsOut[0], receiver);
                } else {
                    amountsOut = _strategy.withdrawAssets(assets_, value, receiver);
                }
            } else {
                if (isUnderlyingWithdrawal) {
                    amountsOut = new uint[](1);
                    amountsOut[0] = amountShares * IERC20(underlying).balanceOf(address(_strategy)) / localTotalSupply;
                    _strategy.withdrawUnderlying(amountsOut[0], receiver);
                } else {
                    amountsOut = _strategy.transferAssets(amountShares, localTotalSupply, receiver);
                }
            }

            uint len = amountsOut.length;
            // nosemgrep
            for (uint i; i < len; ++i) {
                if (amountsOut[i] < minAssetAmountsOut[i]) {
                    revert ExceedSlippageExactAsset(assets_[i], amountsOut[i], minAssetAmountsOut[i]);
                }
            }
        }

        _burn(owner, amountShares);

        emit WithdrawAssets(msg.sender, owner, assets_, amountShares, amountsOut);

        return amountsOut;
    }

    function _beforeWithdraw(VaultBaseStorage storage $, address owner) internal {
        if ($.withdrawRequests[owner] + _WITHDRAW_REQUEST_BLOCKS >= block.number) {
            revert WaitAFewBlocks();
        }
        $.withdrawRequests[owner] = block.number;
    }

    function _update(address from, address to, uint value) internal virtual override {
        super._update(from, to, value);
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        $.withdrawRequests[from] = block.number;
        $.withdrawRequests[to] = block.number;
    }
}
