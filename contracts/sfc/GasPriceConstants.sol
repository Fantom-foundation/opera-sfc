// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {Decimal} from "../common/Decimal.sol";

/**
 * @custom:security-contact security@fantom.foundation
 */
library GP {
    function trimGasPriceChangeRatio(uint256 x) internal pure returns (uint256) {
        if (x > (Decimal.unit() * 105) / 100) {
            return (Decimal.unit() * 105) / 100;
        }
        if (x < (Decimal.unit() * 95) / 100) {
            return (Decimal.unit() * 95) / 100;
        }
        return x;
    }

    function trimMinGasPrice(uint256 x) internal pure returns (uint256) {
        if (x > 1000000 * 1e9) {
            return 1000000 * 1e9;
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
