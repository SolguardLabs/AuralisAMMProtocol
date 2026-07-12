// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract MockVolatilityOracle {
    uint256 public sample;
    bool public shouldRevert;

    function setSample(
        uint256 newSample
    ) external {
        sample = newSample;
    }

    function setShouldRevert(
        bool newShouldRevert
    ) external {
        shouldRevert = newShouldRevert;
    }

    function volatility(
        uint32
    ) external view returns (uint256) {
        if (shouldRevert) revert();
        return sample;
    }
}
