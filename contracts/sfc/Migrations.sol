// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract Migrations {
    address public owner;
    uint public last_completed_migration;

    constructor(address contractOwner) {
        owner = contractOwner;
    }

    modifier restricted() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    function setCompleted(uint completed) public restricted {
        last_completed_migration = completed;
    }

    function upgrade(address new_address) public restricted {
        Migrations upgraded = Migrations(new_address);
        upgraded.setCompleted(last_completed_migration);
    }
}
