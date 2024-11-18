// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

/**
 * @dev Version contract gives the versioning information of the implementation contract
 */
contract Version {
    /**
     * @dev Returns the version of the SFC contract
     */
    function version() public pure returns (bytes3) {
        return 0x040000; // version 4.0.0
    }
}
