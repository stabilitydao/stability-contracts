// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IPoolActions} from "./pool/IPoolActions.sol";
import {IPoolEvents} from "./pool/IPoolEvents.sol";
import {IPoolStorage} from "./pool/IPoolStorage.sol";

interface IPool is IPoolActions, IPoolEvents, IPoolStorage {}
