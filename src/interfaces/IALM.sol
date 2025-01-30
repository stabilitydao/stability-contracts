// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IALM {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CUSTOM ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error IncorrectRebalanceArgs();
    error NotNeedRebalance();
    error CantDoRebalance();
    error NotALM();
    error PriceChangeProtection(uint price, uint priceBefore, uint priceThreshold, uint32 twapInterval);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event ALMParams(uint algoId, int24[] params);
    event PriceChangeProtectionParams(bool enabled, uint32 twapInterval, uint priceThreshold);
    event Rebalance(Position[] newPosition);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.ALMStrategyBase
    struct ALMStrategyBaseStorage {
        uint algoId;
        int24[] params;
        Position[] positions;
        address nft;
        bool priceChangeProtection;
        uint32 twapInterval;
        uint priceThreshold;
    }

    struct ALMStrategyBaseInitParams {
        uint algoId;
        int24[] params;
        address nft;
    }

    struct Position {
        uint tokenId;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
    }

    struct NewPosition {
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint minAmount0;
        uint minAmount1;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice ALM preset
    function preset()
        external
        view
        returns (uint algoId, string memory algoName, string memory presetName, int24[] memory params);

    /// @notice Show current ALM positions
    function positions() external view returns (Position[] memory);

    /// @notice Is a re-balance needed now
    function needRebalance() external view returns (bool);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Re-balance positions
    /// @param burnOldPositions Burn old position or keep. Burn all if length 0 passed than.
    /// @param mintNewPositions New positions params
    function rebalance(bool[] memory burnOldPositions, NewPosition[] memory mintNewPositions) external;

    /// @notice Setup price change protection params
    /// @param enabled Enable protection
    /// @param twapInterval TWAP interval in seconds
    /// @param priceThreshold Price threshold. Default is 10_000.
    function setupPriceChangeProtection(bool enabled, uint32 twapInterval, uint priceThreshold) external;

    /// @notice Change ALM re-balancing params
    /// @param algoId ID of ALM algorithm
    /// @param params Re-balancing params
    function setupALMParams(uint algoId, int24[] memory params) external;
}
