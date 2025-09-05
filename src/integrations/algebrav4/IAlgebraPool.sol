// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IAlgebraPoolImmutables} from "./pool/IAlgebraPoolImmutables.sol";
import {IAlgebraPoolState} from "./pool/IAlgebraPoolState.sol";
import {IAlgebraPoolActions} from "./pool/IAlgebraPoolActions.sol";
import {IAlgebraPoolPermissionedActions} from "./pool/IAlgebraPoolPermissionedActions.sol";
import {IAlgebraPoolEvents} from "./pool/IAlgebraPoolEvents.sol";
import {IAlgebraPoolErrors} from "./pool/IAlgebraPoolErrors.sol";

/// @title The interface for a Algebra Pool
/// @dev The pool interface is broken up into many smaller pieces.
/// This interface includes custom error definitions and cannot be used in older versions of Solidity.
/// For older versions of Solidity use #IAlgebraPoolLegacy
/// Credit to Uniswap Labs under GPL-2.0-or-later license:
/// https://github.com/Uniswap/v3-core/tree/main/contracts/interfaces
interface IAlgebraPool is
    IAlgebraPoolImmutables,
    IAlgebraPoolState,
    IAlgebraPoolActions,
    IAlgebraPoolPermissionedActions,
    IAlgebraPoolEvents,
    IAlgebraPoolErrors
{
// used only for combining interfaces
}
