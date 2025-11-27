// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import {console, Test, Vm} from "forge-std/Test.sol";

contract XTokenBridgeTest is Test {

    //region ------------------------------------- Data types
    struct ChainConfig {
        uint fork;

        address multisig;
        address platform;
        address lzToken;
        address xToken;

        address oapp;
        uint32 endpointId;
        address endpoint;
        address sendLib;
        address receiveLib;
        address executor;
    }
    //endregion ------------------------------------- Data types

    ChainConfig internal sonic;
    ChainConfig internal avalanche;
    ChainConfig internal plasma;

}