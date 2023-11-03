// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;


interface IHardWorker {
    event Call(uint hardworks, uint gasUsed, uint gasCost, bool server);
    event DedicatedServerMsgSender(address indexed sender, bool allowed);
    event DedicatedGelatoMsgSender(address oldSender, address newSender);
    event Delays(uint delayServer, uint delayGelato);
    event GelatoTask(bytes32 id);
    event GelatoDeposit(uint amount);

    function dedicatedServerMsgSender(address sender) external view returns(bool allowed);

    function dedicatedGelatoMsgSender() external view returns(address);

    function checkerServer() external view returns(bool canExec, bytes memory execPayload);

    function checkerGelato() external view returns(bool canExec, bytes memory execPayload);

    function gelatoBalance() external view returns(uint);

    function setDedicatedServerMsgSender(address sender, bool allowed) external;

    function setDelays(uint delayServer_, uint delayGelato_) external;

    function call(address[] memory vaults) external;

}
