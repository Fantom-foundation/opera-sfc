pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interface/INode.sol";

/**
 * @dev Node
 */
contract Node is INode {
    //
    function _deactivateValidator(int256 validatorID, uint256 status) external {}

    //
    function sealEpochValidators(uint256[] calldata nextValidatorIDs) external {}

    //
    function sealEpoch(
        uint256[] calldata offlineTimes,
        uint256[] calldata offlineBlocks,
        uint256[] calldata uptimes,
        uint256[] calldata originatedTxsFee)  external {}

    // other functions
    // offline validator
    //
}