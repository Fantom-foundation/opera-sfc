pragma solidity ^0.5.0;

import "../common/Decimal.sol";

library GP {
    function trimGasPriceChangeRatio(uint256 x) internal pure returns (uint256) {
        if (x > Decimal.unit() * 101 / 100) {
            return Decimal.unit() * 101 / 100;
        }
        if (x < Decimal.unit() * 99 / 100) {
            return Decimal.unit() * 99 / 100;
        }
        return x;
    }

    function trimMinGasPrice(uint256 x) internal pure returns (uint256) {
        if (x > 100000 * 1e9) {
            return 100000 * 1e9;
        }
        if (x < 1e9) {
            return 1e9;
        }
        return x;
    }

    function initialMinGasPrice() internal pure returns (uint256) {
        return 100 * 1e9;
    }
}
