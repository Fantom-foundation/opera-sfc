// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

library Decimal {
    // unit is used for decimals, e.g. 0.123456
    function unit() internal pure returns (uint256) {
        return 1e18;
    }
}
