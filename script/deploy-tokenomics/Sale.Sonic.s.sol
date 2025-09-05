// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {Sale} from "../../src/tokenomics/Sale.sol";
import {SaleReceiptToken} from "../../src/tokenomics/SaleReceiptToken.sol";

contract DeploySale is Script {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant TOKEN_USDC = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    uint public constant SALE_PRICE = 125000; // $0.125
    uint64 public constant SALE_START = 1741132800; // Wed Mar 05 2025 00:00:00 GMT+0000
    uint64 public constant SALE_END = 1741564800; // Mon Mar 10 2025 00:00:00 GMT+0000
    uint64 public constant TGE = 1741737600; // Wed Mar 12 2025 00:00:00 GMT+0000

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address saleAddress = address(new Sale(PLATFORM, TOKEN_USDC, SALE_PRICE, SALE_START, SALE_END, TGE));
        new SaleReceiptToken(saleAddress, "STBL Sale Receipt", "saleSTBL");
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
