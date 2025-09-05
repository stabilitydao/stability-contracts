// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IAlgebraPoolImmutables} from "./pool/IAlgebraPoolImmutables.sol";
import {IAlgebraPoolState} from "./pool/IAlgebraPoolState.sol";
import {IAlgebraPoolDerivedState} from "./pool/IAlgebraPoolDerivedState.sol";
import {IAlgebraPoolActions} from "./pool/IAlgebraPoolActions.sol";
import {IAlgebraPoolPermissionedActions} from "./pool/IAlgebraPoolPermissionedActions.sol";
import {IAlgebraPoolEvents} from "./pool/IAlgebraPoolEvents.sol";

/**
 * @title The interface for a Algebra Pool
 * @dev The pool interface is broken up into many smaller pieces.
 * Credit to Uniswap Labs under GPL-2.0-or-later license:
 * https://github.com/Uniswap/v3-core/tree/main/contracts/interfaces
 */
interface IAlgebraPool is
    IAlgebraPoolImmutables,
    IAlgebraPoolState,
    IAlgebraPoolDerivedState,
    IAlgebraPoolActions,
    IAlgebraPoolPermissionedActions,
    IAlgebraPoolEvents
{
// used only for combining interfaces
}
