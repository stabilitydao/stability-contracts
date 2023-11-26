// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./Controllable.sol";
import "../libs/ConstantsLib.sol";
import "../libs/VaultStatusLib.sol";
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
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
abstract contract VaultBase is Controllable, ERC20Upgradeable, ReentrancyGuardUpgradeable, IVault {
    using SafeERC20 for IERC20;

    //region ----- Constants -----

    /// @dev Version of VaultBase implementation
    string public constant VERSION_VAULT_BASE = '1.0.0';

    /// @dev Delay between deposits/transfers and withdrawals
    uint internal constant _WITHDRAW_REQUEST_BLOCKS = 5;

    /// @dev Initial shares of the vault minted at the first deposit and sent to the dead address.
    uint internal constant _INITIAL_SHARES = 1e15;

    /// @dev Delay for calling strategy.doHardWork() on user deposits
    uint internal constant _MIN_HARDWORK_DELAY = 3600;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.VaultBase")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant VAULTBASE_STORAGE_LOCATION = 0xd602ae9af1fed726d4890dcf3c81a074ed87a6343646550e5de293c5a9330a00;

    //endregion -- Constants -----

    //region ----- Storage -----

    /// @custom:storage-location erc7201:stability.VaultBase
    struct VaultBaseStorage {
        /// @dev Prevents manipulations with deposit and withdraw in short time.
        ///      For simplification we are setup new withdraw request on each deposit/transfer.
        mapping(address msgSender => uint blockNumber) withdrawRequests;
        /// @inheritdoc IVault
        IStrategy strategy;
        /// @inheritdoc IVault
        uint maxSupply;
        /// @inheritdoc IVault
        uint tokenId;
        /// @inheritdoc IVault
        bool doHardWorkOnDeposit;
        /// @dev Immutable vault type ID
        string _type;
    }


    //endregion -- Storage -----

    //region ----- Init -----

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
        $.doHardWorkOnDeposit = true;
    }

    //endregion -- Init -----

    //region ----- Callbacks -----

    /// @dev Need to receive ETH for HardWork and re-balance gas compensation
    receive() external payable {}

    //endregion -- Callbacks -----

    //region ----- Restricted actions -----

    /// @inheritdoc IVault
    function setMaxSupply(uint maxShares) public virtual onlyGovernanceOrMultisig {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        $.maxSupply = maxShares;
        emit MaxSupply(maxShares);
    }

    /// @inheritdoc IVault
    function setDoHardWorkOnDeposit(bool value) external onlyGovernanceOrMultisig {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        $.doHardWorkOnDeposit = value;
        emit DoHardWorkOnDepositChanged($.doHardWorkOnDeposit, value);
    }

    /// @inheritdoc IVault
    function doHardWork() external {
        IPlatform _platform = IPlatform(platform());
        if(msg.sender != _platform.hardWorker() && !_platform.isOperator(msg.sender)){
            revert IncorrectMsgSender();
        }
        uint startGas = gasleft();
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        $.strategy.doHardWork();
        uint gasUsed = startGas - gasleft();
        uint gasCost = gasUsed * tx.gasprice;
        bool compensated;
        if (gasCost > 0) {
            bool canCompensate = payable(address(this)).balance >= gasCost;
            if (canCompensate) {
                //slither-disable-next-line unused-return
                (bool success, ) = msg.sender.call{value: gasCost}("");
                if(!success) {
                    revert IControllable.ETHTransferFailed();
                }
                compensated = true;
            } else {
                //slither-disable-next-line unused-return
                (uint _tvl,) = tvl();
                if (_tvl < IPlatform(platform()).minTVL()) {
                    revert NotEnoughBalanceToPay();
                }
            }
        }

        emit HardWorkGas(gasUsed, gasCost, compensated);
    }

    //endregion -- Restricted actions ----

    //region ----- User actions -----

    /// @inheritdoc IVault
    function depositAssets(address[] memory assets_, uint[] memory amountsMax, uint minSharesOut, address receiver) external virtual nonReentrant {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        if(IFactory(IPlatform(platform()).factory()).vaultStatus(address(this)) != VaultStatusLib.ACTIVE){
            revert IFactory.NotActiveVault();
        } 

        if ($.doHardWorkOnDeposit && block.timestamp > $.strategy.lastHardWork() + _MIN_HARDWORK_DELAY) {
            $.strategy.doHardWork();
        }

        //slither-disable-next-line uninitialized-local
        DepositAssetsData memory data;
        data._totalSupply = totalSupply();
        data.totalValue = $.strategy.total();
        if(data._totalSupply != 0 && data.totalValue == 0){
            revert FuseTrigger();
        }
        
        data.len = amountsMax.length;
        if(data.len != assets_.length){
            revert IControllable.IncorrectArrayLength();
        }

        data.assets = $.strategy.assets();
        data.underlying = $.strategy.underlying();


        if (data.len == 1 && data.underlying != address(0) && data.underlying == assets_[0]) {
            data.value = amountsMax[0];
            IERC20(data.underlying).safeTransferFrom(msg.sender, address($.strategy), data.value);
            (data.amountsConsumed) = $.strategy.depositUnderlying(data.value);
        } else {
            (data.amountsConsumed, data.value) = $.strategy.previewDepositAssets(assets_, amountsMax);
            for (uint i; i < data.len; ++i) {
                IERC20(data.assets[i]).safeTransferFrom(msg.sender, address($.strategy), data.amountsConsumed[i]);
            }
            data.value = $.strategy.depositAssets(data.amountsConsumed);
        }
        
        if(data.value == 0){
            revert IControllable.IncorrectZeroArgument();
        }  

        data.mintAmount = _mintShares($, data._totalSupply, data.value, data.totalValue, data.amountsConsumed, minSharesOut, data.assets, receiver);

        $.withdrawRequests[receiver] = block.number;

        emit DepositAssets(receiver, assets_, data.amountsConsumed, data.mintAmount);
    }

    /// @inheritdoc IVault
    function withdrawAssets(address[] memory assets_, uint amountShares, uint[] memory minAssetAmountsOut) external virtual nonReentrant {
        if(amountShares == 0){
            revert IControllable.IncorrectZeroArgument();
        }
        if(amountShares > balanceOf(msg.sender)){
            revert NotEnoughBalanceToPay();
        }
        if(assets_.length != minAssetAmountsOut.length){
            revert IControllable.IncorrectArrayLength();
        }

        VaultBaseStorage storage $ = _getVaultBaseStorage();
        _beforeWithdraw($);

        IStrategy _strategy = $.strategy;
        uint _totalSupply = totalSupply();
        uint totalValue = _strategy.total();

        uint[] memory amountsOut;
        address underlying = _strategy.underlying();
        bool isUnderlyingWithdrawal = assets_.length == 1 && underlying != address(0) && underlying == assets_[0];

        // fuse is not triggered
        if (totalValue > 0) {
            uint value = amountShares * totalValue / _totalSupply;
            if (isUnderlyingWithdrawal) {
                amountsOut = new uint[](1);
                amountsOut[0] = value;
                $.strategy.withdrawUnderlying(amountsOut[0], msg.sender);
            } else {
                amountsOut = $.strategy.withdrawAssets(assets_, value, msg.sender);
            }
        } else {
            if (isUnderlyingWithdrawal) {
                amountsOut = new uint[](1);
                amountsOut[0] = amountShares * IERC20(underlying).balanceOf(address(_strategy)) / _totalSupply;
                $.strategy.withdrawUnderlying(amountsOut[0], msg.sender);
            } else {
                amountsOut = $.strategy.transferAssets(amountShares, _totalSupply, msg.sender);
            }
        }

        uint len = amountsOut.length;
        for (uint i; i < len; ++i) {
            if(amountsOut[i] < minAssetAmountsOut[i]){
                revert ExceedSlippageExactAsset(assets_[i], amountsOut[i], minAssetAmountsOut[i]);
            }
        }

        _burn(msg.sender, amountShares);

        emit WithdrawAssets(msg.sender, assets_, amountShares, amountsOut);
    }

    //endregion -- User actions ----

    //region ----- View functions -----

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override (Controllable, IERC165) returns (bool) {
        return interfaceId == type(IVault).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IVault
    function VAULT_TYPE() external view returns (string memory) {
        return _getVaultBaseStorage()._type;
    }

    /// @inheritdoc IVault
    function price() external view returns (uint price_, bool trusted_) {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        (address[] memory _assets, uint[] memory _amounts) = $.strategy.assetsAmounts();
        IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());
        uint _tvl;
        (_tvl,, trusted_) = priceReader.getAssetsPrice(_assets, _amounts);
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
        (tvl_,, trusted_) = priceReader.getAssetsPrice(_assets, _amounts);
    }

    /// @inheritdoc IVault
    function previewDepositAssets(address[] memory assets_, uint[] memory amountsMax) external view returns (uint[] memory amountsConsumed, uint sharesOut, uint valueOut) {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        (amountsConsumed, valueOut) = $.strategy.previewDepositAssets(assets_, amountsMax);
        //slither-disable-next-line unused-return
        (sharesOut,) = _calcMintShares(totalSupply(), valueOut, $.strategy.total(), amountsConsumed, $.strategy.assets());
    }

    /// @inheritdoc IVault
    function getApr() external view returns (uint totalApr, uint strategyApr, address[] memory assetsWithApr, uint[] memory assetsAprs) {
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        strategyApr = $.strategy.lastApr();
        totalApr = strategyApr;
        address[] memory strategyAssets = $.strategy.assets();
        uint[] memory proportions = $.strategy.getAssetsProportions();
        address underlying = $.strategy.underlying();
        uint assetsLengthTmp = strategyAssets.length;
        if (underlying != address(0)) {
            ++assetsLengthTmp;
        }
        address[] memory queryAprAssets = new address[](assetsLengthTmp);
        for (uint i; i < strategyAssets.length; ++i) {
            queryAprAssets[i] = strategyAssets[i];
        }
        if (underlying != address(0)) {
            queryAprAssets[assetsLengthTmp - 1] = underlying;
        }
        uint[] memory queryAprs = IAprOracle(IPlatform(platform()).aprOracle()).getAprs(queryAprAssets);
        assetsLengthTmp = 0;
        for (uint i; i < queryAprs.length; ++i) {
            if (queryAprs[i] > 0) {
                ++assetsLengthTmp;
            }
        }
        assetsWithApr = new address[](assetsLengthTmp);
        assetsAprs = new uint[](assetsLengthTmp);

        uint k;
        for (uint i; i < queryAprs.length; ++i) {
            if (queryAprs[i] > 0) {
                assetsWithApr[k] = queryAprAssets[i];
                assetsAprs[k] = queryAprs[i];
                if (i < strategyAssets.length) {
                    totalApr += assetsAprs[k] * proportions[i] / 1e18;
                } else {
                    totalApr += assetsAprs[k];
                }
                ++k;
            }
        }

    }

    /// @inheritdoc IVault
    function previewWithdraw(uint sharesToBurn) external view returns(uint[] memory amountsOut){
        return _getVaultBaseStorage().strategy.previewWithdraw(sharesToBurn, totalSupply());
    }

    /// @inheritdoc IVault
    function getUniqueInitParamLength() public view virtual returns(uint uniqueInitAddresses, uint uniqueInitNums);

    /// @inheritdoc IVault
    function strategy() external view returns (IStrategy) {
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


    //endregion -- View functions -----

    //region ----- Internal logic -----

    function _getVaultBaseStorage() internal pure returns (VaultBaseStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := VAULTBASE_STORAGE_LOCATION
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
        (mintAmount, initialShares) = _calcMintShares(totalSupply_, value_,  totalValue_, amountsConsumed, assets);
        uint _maxSupply = $.maxSupply;
        if(_maxSupply != 0 && mintAmount + totalSupply_ > _maxSupply){
            revert ExceedMaxSupply(_maxSupply);
        }
        if(mintAmount < minSharesOut){
            revert ExceedSlippage(mintAmount, minSharesOut);
        }
        if (initialShares > 0) {
            _mint(ConstantsLib.DEAD_ADDRESS, initialShares);
        }
        if(receiver == address(0)) {
            receiver = msg.sender;
        }
        _mint(receiver, mintAmount);
    }

    /// @dev Calculating amount of new shares for given deposited value and totals
    function _calcMintShares(uint totalSupply_, uint value_, uint totalValue_, uint[] memory amountsConsumed, address[] memory assets) internal view returns (uint mintAmount, uint initialShares) {
        if (totalSupply_ > 0) {
            mintAmount = value_ * totalSupply_ / totalValue_;
            initialShares = 0; // hide warning
        } else {
            // calc mintAmount for USD amount of value
            // its setting sharePrice to 1e18
            IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());
            //slither-disable-next-line unused-return
            (mintAmount,,) = priceReader.getAssetsPrice(assets, amountsConsumed);

            // initialShares for saving share price after full withdraw
            initialShares = _INITIAL_SHARES;
            if(mintAmount < initialShares * 1000){
                revert NotEnoughAmountToInitSupply(mintAmount, initialShares * 1000);
            }
            mintAmount -= initialShares;
        }
    }

    function _beforeWithdraw(VaultBaseStorage storage $) internal {
        if($.withdrawRequests[msg.sender] + _WITHDRAW_REQUEST_BLOCKS >= block.number){
            revert WaitAFewBlocks();
        }
        $.withdrawRequests[msg.sender] = block.number;
    }

    function _update(
        address from,
        address to,
        uint value
    ) internal virtual override {
        super._update(from, to, value);
        VaultBaseStorage storage $ = _getVaultBaseStorage();
        $.withdrawRequests[from] = block.number;
        $.withdrawRequests[to] = block.number;
    }

    // function _afterTokenTransfer(
    //     address from,
    //     address to,
    //     uint /*amount*/
    // ) internal override {
    //     _withdrawRequests[from] = block.number;
    //     _withdrawRequests[to] = block.number;
    // }

    //endregion -- Internal logic -----
}
