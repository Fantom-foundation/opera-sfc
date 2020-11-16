pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

/**
 * @dev A registry for all validators
 */
interface ValidatorRegistry {
    using SafeMath for uint256;

    function setGenesisDelegation(address delegator, uint256 toValidatorID, uint256 amount, uint256 rewards) external notInitialized;

    function createValidator(bytes calldata pubkey) external payable;

    function stake(uint256 toValidatorID) external payable;

    function startUnstake(uint256 toValidatorID, uint256 urID, uint256 amount) external;

    function finishUnstake(uint256 toValidatorID, uint256 urID) external;

    function deactivateValidator(uint256 validatorID, uint256 status) external;

//    function _isSelfStake(address delegator, uint256 toValidatorID) internal view returns (bool);

//    function _getSelfStake(uint256 validatorID) internal view returns (uint256);

//    function _checkDelegatedStakeLimit(uint256 validatorID) internal view returns (bool);

//    function _setValidatorDeactivated(uint256 validatorID, uint256 status) internal;

    // _syncValidator updates the validator data on node
//    function _syncValidator(uint256 validatorID) public;

//    function _validatorExists(uint256 validatorID) view internal returns (bool);
}