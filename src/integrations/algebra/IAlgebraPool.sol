// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import './pool/IAlgebraPoolImmutables.sol';
import './pool/IAlgebraPoolState.sol';
import './pool/IAlgebraPoolDerivedState.sol';
import './pool/IAlgebraPoolActions.sol';
import './pool/IAlgebraPoolPermissionedActions.sol';
import './pool/IAlgebraPoolEvents.sol';

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
