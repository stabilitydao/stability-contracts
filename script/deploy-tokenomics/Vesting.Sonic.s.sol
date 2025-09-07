// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {Vesting} from "../../src/tokenomics/Vesting.sol";

contract DeployVesting is Script {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STBL = 0x78a76316F66224CBaCA6e70acB24D5ee5b2Bd2c7;
    uint64 public constant TGE = 1741186800; // Wed Mar 05 2025 15:00:00 GMT+0000
    uint64 public constant ONE_YEAR = 365 days;
    uint64 public constant HALF_YEAR = ONE_YEAR / 2;
    uint64 public constant FOUR_YEARS = 4 * ONE_YEAR;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new Vesting(PLATFORM, STBL, "Investors", ONE_YEAR, TGE + HALF_YEAR);
        new Vesting(PLATFORM, STBL, "Foundation", FOUR_YEARS, TGE + HALF_YEAR);
        new Vesting(PLATFORM, STBL, "Community", FOUR_YEARS, TGE + HALF_YEAR);
        new Vesting(PLATFORM, STBL, "Team", FOUR_YEARS, TGE + HALF_YEAR);
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
