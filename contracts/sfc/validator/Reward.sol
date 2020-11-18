pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interface/IReward.sol";
import "../interface/INode.sol";
import "../../common/Decimal.sol";
import "../../ownership/Ownable.sol";
import "./Storage.sol";
import "./ValidatorRegistry.sol";

/**
 * @dev Reward
 */
contract Reward is Ownable, IReward, INode, Storage {
    using SafeMath for uint256;

//    struct EpochSnapshot {
//        mapping(uint256 => uint256) receivedStakes;
//        mapping(uint256 => uint256) accumulatedRewardPerToken;
//        mapping(uint256 => uint256) accumulatedUptimes;
//        mapping(uint256 => uint256) accumulatedOriginatedTxsFee;
//        mapping(uint256 => uint256) offlineTimes;
//        mapping(uint256 => uint256) offlineBlocks;
//
//        uint256[] validatorIDs;
//
//        uint256 endTime;
//        uint256 epochFee;
//        uint256 totalBaseRewardWeight;
//        uint256 totalTxRewardWeight;
//        uint256 baseRewardPerSecond;
//        uint256 totalStake;
//        uint256 totalSupply;
//    }
//
//    mapping(address => mapping(uint256 => uint256)) public rewardsStash; // addr, validatorID -> StashedRewards
//    mapping(address => mapping(uint256 => uint256)) public delegations;
//    mapping(uint256 => EpochSnapshot) public getEpochSnapshot;
//    mapping(address => mapping(uint256 => uint256)) public claimedRewardUntilEpoch;

    constructor(Storage store) public {

    }

    Storage store;

    function pendingRewards(address delegator, uint256 toValidatorID) public view returns (uint256) {
        uint256 claimedUntil = claimedRewardUntilEpoch[delegator][toValidatorID];
        uint256 claimedRate = getEpochSnapshot[claimedUntil].accumulatedRewardPerToken[toValidatorID];
        uint256 currentRate = getEpochSnapshot[_highestPayableEpoch(toValidatorID)].accumulatedRewardPerToken[toValidatorID];
        uint256 pending = currentRate.sub(claimedRate).mul(delegations[delegator][toValidatorID]).div(Decimal.unit());
        return rewardsStash[delegator][toValidatorID].add(pending);
    }

    function _highestPayableEpoch(uint256 validatorID) internal view returns (uint256) {
        if (validators[validatorID].deactivatedEpoch != 0) {
            if (currentSealedEpoch < validators[validatorID].deactivatedEpoch) {
                return currentSealedEpoch;
            }
            return validators[validatorID].deactivatedEpoch;
        }
        return currentSealedEpoch;
    }

    function stashRewards(address delegator, uint256 toValidatorID) external {
        require(_stashRewards(delegator, toValidatorID), "nothing to stash");
    }

    function _stashRewards(address delegator, uint256 toValidatorID) public returns (bool updated) {
        uint256 pending = pendingRewards(delegator, toValidatorID);
        claimedRewardUntilEpoch[delegator][toValidatorID] = _highestPayableEpoch(toValidatorID);
        if (rewardsStash[delegator][toValidatorID] == pending) {
            return false;
        }
        rewardsStash[delegator][toValidatorID] = pending;
        return true;
    }

    function claimRewards(uint256 toValidatorID) external {
        address payable delegator = msg.sender;
        uint256 pending = pendingRewards(delegator, toValidatorID);
        require(pending != 0, "zero rewards");
        delete rewardsStash[delegator][toValidatorID];
        claimedRewardUntilEpoch[delegator][toValidatorID] = _highestPayableEpoch(toValidatorID);
        // It's important that we transfer after erasing (protection against Re-Entrancy)
        delegator.transfer(pending);
        emit IncBalance(address(this), pending);
    }

    function offlinePenaltyThreshold() public view returns (uint256 blocksNum, uint256 time) {
        return (offlinePenaltyThresholdBlocksNum, offlinePenaltyThresholdTime);
    }

    function updateBaseRewardPerSecond(uint256 value) onlyOwner external {
        baseRewardPerSecond = value;
        emit UpdatedBaseRewardPerSec(value);
    }

    function updateOfflinePenaltyThreshold(uint256 blocksNum, uint256 time) onlyOwner external {
        offlinePenaltyThresholdTime = time;
        offlinePenaltyThresholdBlocksNum = blocksNum;
        emit UpdatedOfflinePenaltyThreshold(blocksNum, time);
    }
}