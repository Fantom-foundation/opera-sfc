pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

/**
 * @dev INode
 */
interface INode {
    /**
     * @dev List of events
     */

    event IncBalance(address indexed acc, uint256 value);
    //    event SetBalance(address indexed acc, uint256 value);
    //    event SubBalance(address indexed acc, uint256 value);
    //    event SetCode(address indexed acc, address indexed from);
    //    event SwapCode(address indexed acc, address indexed with);
    //    event SetStorage(address indexed acc, uint256 key, uint256 value);

    event UpdatedValidatorWeight(uint256 indexed validatorID, uint256 weight);


    //
    function _deactivateValidator(int256 validatorID, uint256 status) external;

    //
    function sealEpochValidators(uint256[] calldata nextValidatorIDs) external;

    //
    function sealEpoch(
        uint256[] calldata offlineTimes,
        uint256[] calldata offlineBlocks,
        uint256[] calldata uptimes,
        uint256[] calldata originatedTxsFee)  external;

    // other functions
    // offline validator
    //
}