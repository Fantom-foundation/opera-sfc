pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

/**
 * @dev A registry for all delegations
 */
interface IDelegationRegistry {
    using SafeMath for uint256;

    function createDelegation(uint256 toValidatorID, uint256 urID, uint256 amount) external payable;

    function startUndelegate(uint256 toValidatorID, uint256 urID, uint256 amount) external;

    function finishUndelegate(uint256 toValidatorID, uint256 urID) external;

    //    function _delegationExists(uint256 validatorID, uint256 urID) view internal returns (bool);
}