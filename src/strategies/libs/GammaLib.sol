// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

library GammaLib {
    enum Presets{ NARROW, WIDE, DYNAMIC, STABLE }

    function getPresetName(uint preset) external pure returns (string memory) {
        if (preset == uint(Presets.NARROW)) {
            return "Narrow";
        }
        if (preset == uint(Presets.WIDE)) {
            return "Wide";
        }
        if (preset == uint(Presets.DYNAMIC)) {
            return "Pegged";
        }
        if (preset == uint(Presets.STABLE)) {
            return "Stable";
        }

        return "";
    }
}
