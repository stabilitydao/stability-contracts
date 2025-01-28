// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IALM {

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
}
