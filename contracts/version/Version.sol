// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

/**
 * @dev Version contract gives the versioning information of the implementation contract
 */
contract Version {
    /**
     * @dev Returns the address of the current owner.
     */
    function version() public pure returns (bytes3) {
        // version 2.0.2
        return "202";
    }
}
