pragma solidity ^0.5.0;

import "./SFCInterface.sol";

contract Storage is SFCInterface {

    constructor() public {}

    // Validator
    mapping(uint256 => Validator) public validators;
    mapping(address => uint256) public validatorIDs;
    // mapping(uint256 => bytes) public validatorMetadata;

    mapping(address => mapping(uint256 => mapping(uint256 => UnstakingRequest))) public getUnstakingRequest;
    mapping(address => mapping(uint256 => uint256)) public rewardsStash; // addr, validatorID -> StashedRewards
    mapping(address => mapping(uint256 => uint256)) public delegations;
    mapping(uint256 => EpochSnapshot) public getEpochSnapshot;
    mapping(address => mapping(uint256 => uint256)) public claimedRewardUntilEpoch;

    uint256 public currentSealedEpoch;
    uint256 public lastValidatorID;
    uint256 public totalStake;
    uint256 public totalSlashedStake;
    uint256 offlinePenaltyThresholdBlocksNum;
    uint256 offlinePenaltyThresholdTime;
    uint256 public baseRewardPerSecond;
    uint256 public totalSupply;

    event UpdatedBaseRewardPerSec(uint256 value);
    event UpdatedOfflinePenaltyThreshold(uint256 blocksNum, uint256 period);

}
