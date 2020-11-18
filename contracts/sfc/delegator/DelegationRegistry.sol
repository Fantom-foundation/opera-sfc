pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interface/IDelegationRegistry.sol";

/**
 * @dev A registry for all delegations
 */
contract DelegationRegistry is IDelegationRegistry {
    using SafeMath for uint256;

    constructor() public {

    }

    mapping(address => mapping(uint256 => uint256)) public delegations;

    function createDelegation(uint256 toValidatorID, uint256 urID, uint256 amount) external payable {

    }

    function startUndelegate(uint256 toValidatorID, uint256 urID, uint256 amount) external {

    }

    function finishUndelegate(uint256 toValidatorID, uint256 urID) external {

    }

    function delegationAmount(address addr, uint256 urID) public view returns (uint256)  {
        return delegations[addr][urID];
    }

    function increase(address addr, uint256 urID, uint256 amount) external {
        delegations[addr][urID] = delegations[addr][urID].add(amount);
    }

    function decrease(address addr, uint256 urID, uint256 amount) external {
        delegations[addr][urID] -= amount;
    }


    //    function _delegationExists(uint256 validatorID, uint256 urID) view internal returns (bool);
}