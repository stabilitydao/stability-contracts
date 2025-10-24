// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IXSTBL {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct VestPosition {
        /// @dev amount of xSTBL
        uint amount;
        /// @dev start unix timestamp
        uint start;
        /// @dev start + MAX_VEST (end timestamp)
        uint maxEnd;
        /// @dev vest identifier (starting from 0)
        uint vestID;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error NO_VEST();
    error NOT_WHITELISTED(address from, address to);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event Enter(address indexed user, uint amount);
    event InstantExit(address indexed user, uint exitAmount);
    event NewVest(address indexed user, uint indexed vestId, uint amount);
    event CancelVesting(address indexed user, uint indexed vestId, uint amount);
    event ExitVesting(address indexed user, uint indexed vestId, uint totalAmount, uint exitedAmount);
    event ExemptionFrom(address indexed candidate, bool status, bool success);
    event ExemptionTo(address indexed candidate, bool status, bool success);
    event Rebase(address indexed caller, uint amount);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Mints xSTBL for each STBL
    function enter(uint amount_) external;

    /// @dev Exit instantly with a penalty
    /// @param amount_ Amount of xSTBL to exit
    function exit(uint amount_) external returns (uint exitedAmount);

    /// @dev Vesting xSTBL --> STBL functionality
    function createVest(uint amount_) external;

    /// @dev Handles all situations regarding exiting vests
    function exitVest(uint vestID_) external;

    /// @notice Set exemption status for from address
    function setExemptionFrom(address[] calldata exemptee, bool[] calldata exempt) external;

    /// @notice Set exemption status for to address
    function setExemptionTo(address[] calldata exemptee, bool[] calldata exempt) external;

    /// @notice Function called by the RevenueRouter to send the rebases once a week
    function rebase() external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Denominator
    function BASIS() external view returns (uint);

    /// @notice Max slashing amount. {BASIS} is used as denominator, so 100 = 1%
    function SLASHING_PENALTY() external view returns (uint);

    /// @notice The minimum vesting length
    function MIN_VEST() external view returns (uint);

    /// @notice The maximum vesting length
    function MAX_VEST() external view returns (uint);

    /// @notice STBL address
    function STBL() external view returns (address);

    /// @notice xSTBL staking contract
    function xStaking() external view returns (address);

    /// @notice Revenue distributor contract
    function revenueRouter() external view returns (address);

    /// @notice returns info on a user's vests
    function vestInfo(address user, uint vestId) external view returns (uint amount, uint start, uint maxEnd);

    /// @notice Returns the total number of individual vests the user has
    function usersTotalVests(address who) external view returns (uint numOfVests);

    /// @notice Amount of pvp rebase penalties accumulated pending to be distributed
    function pendingRebase() external view returns (uint);

    /// @notice The last period rebases were distributed
    function lastDistributedPeriod() external view returns (uint);
}
