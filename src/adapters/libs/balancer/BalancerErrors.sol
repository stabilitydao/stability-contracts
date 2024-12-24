// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

/**
 * @dev Reverts if `condition` is false, with a revert reason containing `errorCode`. Only codes up to 999 are
 * supported.
 */
function _require(bool condition, uint errorCode) pure {
    if (!condition) _revert(errorCode);
}

/**
 * @dev Reverts with a revert reason containing `errorCode`. Only codes up to 999 are supported.
 */
function _revert(uint errorCode) pure {
    // We're going to dynamically create a revert string based on the error code, with the following format:
    // 'BAL#{errorCode}'
    // where the code is left-padded with zeroes to three digits (so they range from 000 to 999).
    //
    // We don't have revert strings embedded in the contract to save bytecode size: it takes much less space to store a
    // number (8 to 16 bits) than the individual string characters.
    //
    // The dynamic string creation algorithm that follows could be implemented in Solidity, but assembly allows for a
    // much denser implementation, again saving bytecode size. Given this function unconditionally reverts, this is a
    // safe place to rely on it without worrying about how its usage might affect e.g. memory contents.
    assembly {
        // First, we need to compute the ASCII representation of the error code. We assume that it is in the 0-999
        // range, so we only need to convert three digits. To convert the digits to ASCII, we add 0x30, the value for
        // the '0' character.

        let units := add(mod(errorCode, 10), 0x30)

        errorCode := div(errorCode, 10)
        let tenths := add(mod(errorCode, 10), 0x30)

        errorCode := div(errorCode, 10)
        let hundreds := add(mod(errorCode, 10), 0x30)

        // With the individual characters, we can now construct the full string. The "BAL#" part is a known constant
        // (0x42414c23): we simply shift this by 24 (to provide space for the 3 bytes of the error code), and add the
        // characters to it, each shifted by a multiple of 8.
        // The revert reason is then shifted left by 200 bits (256 minus the length of the string, 7 characters * 8 bits
        // per character = 56) to locate it in the most significant part of the 256 slot (the beginning of a byte
        // array).

        let revertReason := shl(200, add(0x42414c23000000, add(add(units, shl(8, tenths)), shl(16, hundreds))))

        // We can now encode the reason in memory, which can be safely overwritten as we're about to revert. The encoded
        // message will have the following layout:
        // [ revert reason identifier ] [ string location offset ] [ string length ] [ string contents ]

        // The Solidity revert reason identifier is 0x08c739a0, the function selector of the Error(string) function. We
        // also write zeroes to the next 28 bytes of memory, but those are about to be overwritten.
        mstore(0x0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
        // Next is the offset to the location of the string, which will be placed immediately after (20 bytes away).
        mstore(0x04, 0x0000000000000000000000000000000000000000000000000000000000000020)
        // The string length is fixed: 7 characters.
        mstore(0x24, 7)
        // Finally, the string itself is stored.
        mstore(0x44, revertReason)

        // Even if the string is only 7 bytes long, we need to return a full 32 byte slot containing it. The length of
        // the encoded message is therefore 4 + 32 + 32 + 32 = 100.
        revert(0, 100)
    }
}

library Errors {
    // Math
    uint internal constant ADD_OVERFLOW = 0;
    uint internal constant SUB_OVERFLOW = 1;
    uint internal constant SUB_UNDERFLOW = 2;
    uint internal constant MUL_OVERFLOW = 3;
    uint internal constant ZERO_DIVISION = 4;
    uint internal constant DIV_INTERNAL = 5;
    uint internal constant X_OUT_OF_BOUNDS = 6;
    uint internal constant Y_OUT_OF_BOUNDS = 7;
    uint internal constant PRODUCT_OUT_OF_BOUNDS = 8;
    uint internal constant INVALID_EXPONENT = 9;

    // Input
    uint internal constant OUT_OF_BOUNDS = 100;
    uint internal constant UNSORTED_ARRAY = 101;
    uint internal constant UNSORTED_TOKENS = 102;
    uint internal constant INPUT_LENGTH_MISMATCH = 103;
    uint internal constant ZERO_TOKEN = 104;

    // Shared pools
    uint internal constant MIN_TOKENS = 200;
    uint internal constant MAX_TOKENS = 201;
    uint internal constant MAX_SWAP_FEE_PERCENTAGE = 202;
    uint internal constant MIN_SWAP_FEE_PERCENTAGE = 203;
    uint internal constant MINIMUM_BPT = 204;
    uint internal constant CALLER_NOT_VAULT = 205;
    uint internal constant UNINITIALIZED = 206;
    uint internal constant BPT_IN_MAX_AMOUNT = 207;
    uint internal constant BPT_OUT_MIN_AMOUNT = 208;
    uint internal constant EXPIRED_PERMIT = 209;
    uint internal constant NOT_TWO_TOKENS = 210;

    // Pools
    uint internal constant MIN_AMP = 300;
    uint internal constant MAX_AMP = 301;
    uint internal constant MIN_WEIGHT = 302;
    uint internal constant MAX_STABLE_TOKENS = 303;
    uint internal constant MAX_IN_RATIO = 304;
    uint internal constant MAX_OUT_RATIO = 305;
    uint internal constant MIN_BPT_IN_FOR_TOKEN_OUT = 306;
    uint internal constant MAX_OUT_BPT_FOR_TOKEN_IN = 307;
    uint internal constant NORMALIZED_WEIGHT_INVARIANT = 308;
    uint internal constant INVALID_TOKEN = 309;
    uint internal constant UNHANDLED_JOIN_KIND = 310;
    uint internal constant ZERO_INVARIANT = 311;
    uint internal constant ORACLE_INVALID_SECONDS_QUERY = 312;
    uint internal constant ORACLE_NOT_INITIALIZED = 313;
    uint internal constant ORACLE_QUERY_TOO_OLD = 314;
    uint internal constant ORACLE_INVALID_INDEX = 315;
    uint internal constant ORACLE_BAD_SECS = 316;
    uint internal constant AMP_END_TIME_TOO_CLOSE = 317;
    uint internal constant AMP_ONGOING_UPDATE = 318;
    uint internal constant AMP_RATE_TOO_HIGH = 319;
    uint internal constant AMP_NO_ONGOING_UPDATE = 320;
    uint internal constant STABLE_INVARIANT_DIDNT_CONVERGE = 321;
    uint internal constant STABLE_GET_BALANCE_DIDNT_CONVERGE = 322;
    uint internal constant RELAYER_NOT_CONTRACT = 323;
    uint internal constant BASE_POOL_RELAYER_NOT_CALLED = 324;
    uint internal constant REBALANCING_RELAYER_REENTERED = 325;
    uint internal constant GRADUAL_UPDATE_TIME_TRAVEL = 326;
    uint internal constant SWAPS_DISABLED = 327;
    uint internal constant CALLER_IS_NOT_LBP_OWNER = 328;
    uint internal constant PRICE_RATE_OVERFLOW = 329;
    uint internal constant INVALID_JOIN_EXIT_KIND_WHILE_SWAPS_DISABLED = 330;
    uint internal constant WEIGHT_CHANGE_TOO_FAST = 331;
    uint internal constant LOWER_GREATER_THAN_UPPER_TARGET = 332;
    uint internal constant UPPER_TARGET_TOO_HIGH = 333;
    uint internal constant UNHANDLED_BY_LINEAR_POOL = 334;
    uint internal constant OUT_OF_TARGET_RANGE = 335;
    uint internal constant UNHANDLED_EXIT_KIND = 336;
    uint internal constant UNAUTHORIZED_EXIT = 337;
    uint internal constant MAX_MANAGEMENT_SWAP_FEE_PERCENTAGE = 338;
    uint internal constant UNHANDLED_BY_INVESTMENT_POOL = 339;
    uint internal constant UNHANDLED_BY_PHANTOM_POOL = 340;
    uint internal constant TOKEN_DOES_NOT_HAVE_RATE_PROVIDER = 341;
    uint internal constant INVALID_INITIALIZATION = 342;

    // Lib
    uint internal constant REENTRANCY = 400;
    uint internal constant SENDER_NOT_ALLOWED = 401;
    uint internal constant PAUSED = 402;
    uint internal constant PAUSE_WINDOW_EXPIRED = 403;
    uint internal constant MAX_PAUSE_WINDOW_DURATION = 404;
    uint internal constant MAX_BUFFER_PERIOD_DURATION = 405;
    uint internal constant INSUFFICIENT_BALANCE = 406;
    uint internal constant INSUFFICIENT_ALLOWANCE = 407;
    uint internal constant ERC20_TRANSFER_FROM_ZERO_ADDRESS = 408;
    uint internal constant ERC20_TRANSFER_TO_ZERO_ADDRESS = 409;
    uint internal constant ERC20_MINT_TO_ZERO_ADDRESS = 410;
    uint internal constant ERC20_BURN_FROM_ZERO_ADDRESS = 411;
    uint internal constant ERC20_APPROVE_FROM_ZERO_ADDRESS = 412;
    uint internal constant ERC20_APPROVE_TO_ZERO_ADDRESS = 413;
    uint internal constant ERC20_TRANSFER_EXCEEDS_ALLOWANCE = 414;
    uint internal constant ERC20_DECREASED_ALLOWANCE_BELOW_ZERO = 415;
    uint internal constant ERC20_TRANSFER_EXCEEDS_BALANCE = 416;
    uint internal constant ERC20_BURN_EXCEEDS_ALLOWANCE = 417;
    uint internal constant SAFE_ERC20_CALL_FAILED = 418;
    uint internal constant ADDRESS_INSUFFICIENT_BALANCE = 419;
    uint internal constant ADDRESS_CANNOT_SEND_VALUE = 420;
    uint internal constant SAFE_CAST_VALUE_CANT_FIT_INT256 = 421;
    uint internal constant GRANT_SENDER_NOT_ADMIN = 422;
    uint internal constant REVOKE_SENDER_NOT_ADMIN = 423;
    uint internal constant RENOUNCE_SENDER_NOT_ALLOWED = 424;
    uint internal constant BUFFER_PERIOD_EXPIRED = 425;
    uint internal constant CALLER_IS_NOT_OWNER = 426;
    uint internal constant NEW_OWNER_IS_ZERO = 427;
    uint internal constant CODE_DEPLOYMENT_FAILED = 428;
    uint internal constant CALL_TO_NON_CONTRACT = 429;
    uint internal constant LOW_LEVEL_CALL_FAILED = 430;

    // Vault
    uint internal constant INVALID_POOL_ID = 500;
    uint internal constant CALLER_NOT_POOL = 501;
    uint internal constant SENDER_NOT_ASSET_MANAGER = 502;
    uint internal constant USER_DOESNT_ALLOW_RELAYER = 503;
    uint internal constant INVALID_SIGNATURE = 504;
    uint internal constant EXIT_BELOW_MIN = 505;
    uint internal constant JOIN_ABOVE_MAX = 506;
    uint internal constant SWAP_LIMIT = 507;
    uint internal constant SWAP_DEADLINE = 508;
    uint internal constant CANNOT_SWAP_SAME_TOKEN = 509;
    uint internal constant UNKNOWN_AMOUNT_IN_FIRST_SWAP = 510;
    uint internal constant MALCONSTRUCTED_MULTIHOP_SWAP = 511;
    uint internal constant INTERNAL_BALANCE_OVERFLOW = 512;
    uint internal constant INSUFFICIENT_INTERNAL_BALANCE = 513;
    uint internal constant INVALID_ETH_INTERNAL_BALANCE = 514;
    uint internal constant INVALID_POST_LOAN_BALANCE = 515;
    uint internal constant INSUFFICIENT_ETH = 516;
    uint internal constant UNALLOCATED_ETH = 517;
    uint internal constant ETH_TRANSFER = 518;
    uint internal constant CANNOT_USE_ETH_SENTINEL = 519;
    uint internal constant TOKENS_MISMATCH = 520;
    uint internal constant TOKEN_NOT_REGISTERED = 521;
    uint internal constant TOKEN_ALREADY_REGISTERED = 522;
    uint internal constant TOKENS_ALREADY_SET = 523;
    uint internal constant TOKENS_LENGTH_MUST_BE_2 = 524;
    uint internal constant NONZERO_TOKEN_BALANCE = 525;
    uint internal constant BALANCE_TOTAL_OVERFLOW = 526;
    uint internal constant POOL_NO_TOKENS = 527;
    uint internal constant INSUFFICIENT_FLASH_LOAN_BALANCE = 528;

    // Fees
    uint internal constant SWAP_FEE_PERCENTAGE_TOO_HIGH = 600;
    uint internal constant FLASH_LOAN_FEE_PERCENTAGE_TOO_HIGH = 601;
    uint internal constant INSUFFICIENT_FLASH_LOAN_FEE_AMOUNT = 602;
}
