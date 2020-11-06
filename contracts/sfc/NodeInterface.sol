pragma solidity ^0.5.0;

interface NodeInterface {

    event IncBalance(address indexed acc, uint256 value);
//    event SetBalance(address indexed acc, uint256 value);
//    event SubBalance(address indexed acc, uint256 value);
//    event SetCode(address indexed acc, address indexed from);
//    event SwapCode(address indexed acc, address indexed with);
//    event SetStorage(address indexed acc, uint256 key, uint256 value);

    event UpdatedValidatorWeight(uint256 indexed validatorID, uint256 weight);

    event UpdatedGasPowerAllocationRate(uint256 short, uint256 long);
    event UpdatedMinGasPrice(uint256 minGasPrice);

    function _deactivateValidator(uint256 validatorID, uint256 status) external;
    function _sealEpochValidators(uint256[] calldata nextValidatorIDs) external;
    function _sealEpoch(uint256[] calldata offlineTimes, uint256[] calldata offlineBlocks, uint256[] calldata uptimes, uint256[] calldata originatedTxsFee) external;
}
