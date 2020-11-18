pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interface/IValidatorRegistry.sol";
import "../../common/Initializable.sol";
import "../../common/Decimal.sol";
import "../node/Node.sol";
import "../StakerConstants.sol";
import "../interface/INode.sol";
import "../delegator/DelegationRegistry.sol";
import "./Reward.sol";
import "../../ownership/Ownable.sol";

/**
 * @dev A registry for all validators
 */
contract ValidatorRegistry is IValidatorRegistry, Initializable, StakersConstants, Ownable, INode {
    using SafeMath for uint256;

    /**
     * @dev The staking for validation
     */
    struct Validator {
        uint256 status;
        uint256 deactivatedTime;
        uint256 deactivatedEpoch;
        uint256 receivedStake;
        uint256 createdEpoch;
        uint256 createdTime;
        address auth;
        bytes pubkey;
    }

    struct UnstakingRequest {
        uint256 epoch;
        uint256 time;
        uint256 amount;
    }

    // Validator
    mapping(uint256 => Validator) public validators;
    mapping(address => uint256) public validatorIDs;
    mapping(uint256 => bytes) public validatorMetadata;

    mapping(address => mapping(uint256 => mapping(uint256 => UnstakingRequest))) public getUnstakingRequest;

    uint256 public currentSealedEpoch;
    uint256 public lastValidatorID;
    uint256 public totalStake;
    uint256 public totalSlashedStake;

    DelegationRegistry delegationReg;


    struct EpochSnapshot {
        mapping(uint256 => uint256) receivedStakes;
        mapping(uint256 => uint256) accumulatedRewardPerToken;
        mapping(uint256 => uint256) accumulatedUptimes;
        mapping(uint256 => uint256) accumulatedOriginatedTxsFee;
        mapping(uint256 => uint256) offlineTimes;
        mapping(uint256 => uint256) offlineBlocks;

        uint256[] validatorIDs;

        uint256 endTime;
        uint256 epochFee;
        uint256 totalBaseRewardWeight;
        uint256 totalTxRewardWeight;
        uint256 baseRewardPerSecond;
        uint256 totalStake;
        uint256 totalSupply;
    }

    mapping(uint256 => EpochSnapshot) public getEpochSnapshot;



//    Reward
    mapping(address => mapping(uint256 => uint256)) public rewardsStash; // addr, validatorID -> StashedRewards

    mapping(address => mapping(uint256 => uint256)) public claimedRewardUntilEpoch;

    uint256 offlinePenaltyThresholdBlocksNum;
    uint256 offlinePenaltyThresholdTime;
    uint256 public baseRewardPerSecond;
    uint256 public totalSupply;

    event UpdatedBaseRewardPerSec(uint256 value);
    event UpdatedOfflinePenaltyThreshold(uint256 blocksNum, uint256 period);

    function currentEpoch() public view returns (uint256) {
        return currentSealedEpoch + 1;
    }

    function setGenesisDelegation(address delegator, uint256 toValidatorID, uint256 amount, uint256 rewards) external notInitialized {
        _rawStake(delegator, toValidatorID, amount);
        rewardsStash[delegator][toValidatorID] = rewards;
    }

    function createValidator(bytes calldata pubkey) external payable {
        require(msg.value >= minSelfStake(), "insufficient self-stake");
        _createValidator(msg.sender, pubkey);
        _stake(msg.sender, lastValidatorID, msg.value);
    }

    function _createValidator(address auth, bytes memory pubkey) internal {
        uint256 validatorID = ++lastValidatorID;
        require(validatorIDs[auth] == 0, "validator already exists");
        validators[validatorID] = Validator(OK_STATUS, 0, 0, 0, currentEpoch(), now, auth, pubkey);
    }

    function _isSelfStake(address delegator, uint256 toValidatorID) internal view returns (bool) {
        return validatorIDs[delegator] == toValidatorID;
    }

    function _getSelfStake(uint256 validatorID) internal view returns (uint256) {
//        return delegationReg.delegations[validators[validatorID].auth][validatorID];
        return delegationReg.delegationAmount(validators[validatorID].auth, validatorID);
    }

    function _checkDelegatedStakeLimit(uint256 validatorID) internal view returns (bool) {
        return validators[validatorID].receivedStake <= _getSelfStake(validatorID).mul(maxDelegatedRatio()).div(Decimal.unit());
    }

    function stake(uint256 toValidatorID) external payable {
        _stake(msg.sender, toValidatorID, msg.value);
    }

    function _stake(address delegator, uint256 toValidatorID, uint256 amount) internal {
        require(validators[toValidatorID].status == OK_STATUS, "validator isn't active");
        _rawStake(delegator, toValidatorID, amount);
    }

    function _rawStake(address delegator, uint256 toValidatorID, uint256 amount) internal {
        require(amount > 0, "zero amount");
        require(_validatorExists(toValidatorID), "validator doesn't exist");

        _stashRewards(delegator, toValidatorID);

        // delegationReg.delegations[delegator][toValidatorID] = delegationReg.delegations[delegator][toValidatorID].add(amount);
        delegationReg.increase(delegator, toValidatorID, amount);

        validators[toValidatorID].receivedStake = validators[toValidatorID].receivedStake.add(amount);
        totalStake = totalStake.add(amount);

        require(_checkDelegatedStakeLimit(toValidatorID), "validator's delegations limit is exceeded");
        _syncValidator(toValidatorID);
    }

    function _validatorExists(uint256 validatorID) view internal returns (bool) {
        return validators[validatorID].createdTime != 0;
    }

    function startUnstake(uint256 toValidatorID, uint256 urID, uint256 amount) external {
        address delegator = msg.sender;

        _stashRewards(delegator, toValidatorID);

        require(amount > 0, "zero amount");
//        require(amount <= delegationReg.delegations[delegator][toValidatorID], "not enough stake");
        require(amount <= delegationReg.delegationAmount(delegator, toValidatorID), "not enough stake");

        require(getUnstakingRequest[delegator][toValidatorID][urID].amount == 0, "urID already exists");


//        delegationReg.delegations[delegator][toValidatorID] -= amount;
        delegationReg.decrease(delegator, toValidatorID, amount);

        validators[toValidatorID].receivedStake = validators[toValidatorID].receivedStake.sub(amount);
        totalStake = totalStake.sub(amount);

        require(_checkDelegatedStakeLimit(toValidatorID) || _getSelfStake(toValidatorID) == 0, "validator's delegations limit is exceeded");
        if (_getSelfStake(toValidatorID) == 0) {
            _setValidatorDeactivated(toValidatorID, WITHDRAWN_BIT);
        }
        getUnstakingRequest[delegator][toValidatorID][urID] = UnstakingRequest(currentEpoch(), now, amount);
        _syncValidator(toValidatorID);
    }

    function finishUnstake(uint256 toValidatorID, uint256 urID) external {
        address payable delegator = msg.sender;
        UnstakingRequest memory request = getUnstakingRequest[delegator][toValidatorID][urID];
        require(request.epoch != 0, "request doesn't exist");

        uint256 requestTime = request.time;
        uint256 requestEpoch = request.epoch;
        if (validators[toValidatorID].deactivatedTime != 0 && validators[toValidatorID].deactivatedTime < requestTime) {
            requestTime = validators[toValidatorID].deactivatedTime;
            requestEpoch = validators[toValidatorID].deactivatedEpoch;
        }

        require(now >= requestTime + unstakePeriodTime(), "not enough time passed");
        require(currentEpoch() >= requestEpoch + unstakePeriodEpochs(), "not enough epochs passed");

        uint256 amount = getUnstakingRequest[delegator][toValidatorID][urID].amount;
        delete getUnstakingRequest[delegator][toValidatorID][urID];

        uint256 slashingPenalty = 0;
        bool isCheater = validators[toValidatorID].status & CHEATER_MASK != 0;

        // It's important that we transfer after erasing (protection against Re-Entrancy)
        if (isCheater == false) {
            delegator.transfer(amount);
        } else {
            slashingPenalty = amount;
        }
        totalSlashedStake += slashingPenalty;
    }

    function deactivateValidator(uint256 validatorID, uint256 status) external {
        require(msg.sender == address(0), "not callable");
        require(status != OK_STATUS, "wrong status");

        _setValidatorDeactivated(validatorID, status);
        _syncValidator(validatorID);
    }

    // _syncValidator updates the validator data on node
    function _syncValidator(uint256 validatorID) public {
        require(_validatorExists(validatorID), "validator doesn't exist");
        // emit special log for node
        uint256 weight = validators[validatorID].receivedStake;
        if (validators[validatorID].status != OK_STATUS) {
            weight = 0;
        }
        emit UpdatedValidatorWeight(validatorID, weight);
    }

    function _setValidatorDeactivated(uint256 validatorID, uint256 status) internal {
        // status as a number is proportional to severity
        if (status > validators[validatorID].status) {
            validators[validatorID].status = status;
            if (validators[validatorID].deactivatedEpoch == 0) {
                validators[validatorID].deactivatedTime = now;
                validators[validatorID].deactivatedEpoch = currentEpoch();
            }
        }
    }

    // Reward functions


    function pendingRewards(address delegator, uint256 toValidatorID) public view returns (uint256) {
        uint256 claimedUntil = claimedRewardUntilEpoch[delegator][toValidatorID];
        uint256 claimedRate = getEpochSnapshot[claimedUntil].accumulatedRewardPerToken[toValidatorID];
        uint256 currentRate = getEpochSnapshot[_highestPayableEpoch(toValidatorID)].accumulatedRewardPerToken[toValidatorID];
        uint256 pending = currentRate.sub(claimedRate).mul(delegationReg.delegationAmount(delegator,toValidatorID)).div(Decimal.unit());
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