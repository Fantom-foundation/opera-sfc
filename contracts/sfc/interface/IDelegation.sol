pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

/**
 * @dev Delegation
 */
interface IDelegation {

    struct Delegation {
        uint256 startedEpoch;
        uint256 duration;
        uint256 amount;
    }

//    struct DelegationStorage {
//
//    }
}