// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract Migrations {
    address public owner;
    uint256 public lastCompletedMigration;

    /**
     * @dev The caller is not the owner.
     */
    error NotOwner();

    constructor(address contractOwner) {
        owner = contractOwner;
    }

    modifier restricted() {
        if (msg.sender != owner) {
            revert NotOwner();
        }
        _;
    }

    function setCompleted(uint256 completed) public restricted {
        lastCompletedMigration = completed;
    }

    function upgrade(address newAddress) public restricted {
        Migrations upgraded = Migrations(newAddress);
        upgraded.setCompleted(lastCompletedMigration);
    }
}
