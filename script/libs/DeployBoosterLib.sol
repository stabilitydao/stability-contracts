// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../src/core/proxy/Proxy.sol";
import "../../src/core/tokens/LiquidToken.sol";
import "../../src/boosters/libs/BoosterIdLib.sol";
import "../../src/boosters/RetroBooster.sol";

library DeployBoosterLib {
    function deployBooster(address platform, string memory id, address ve, address veUnderlying) internal returns (address booster, address liquidToken) {
        Proxy boosterProxy = new Proxy();
        Proxy tokenProxy = new Proxy();
        booster = address(boosterProxy);
        liquidToken = address(tokenProxy);

        if (_eq(id, BoosterIdLib.RETRO)) {
            boosterProxy.initProxy(address(new RetroBooster()));
            RetroBooster(booster).initialize(platform, liquidToken, ve, veUnderlying);
            tokenProxy.initProxy(address(new LiquidToken()));
            LiquidToken(liquidToken).initialize(platform, booster, "Liquid staked veRETRO", "lsRETRO");
        }

        require(boosterProxy.implementation() != address(0), string.concat("DeployBoosterLib: unknown booster ID ", id));
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
