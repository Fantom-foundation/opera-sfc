pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./StakerConstants.sol";
import "../ownership/Ownable.sol";
import "../version/Version.sol";
import "./NodeInterface.sol";
import "./Storage.sol";

/**
 * @dev Stakers contract defines data structure and methods for validators / validators.
 */
contract SFC is Initializable, NodeInterface, Ownable, StakersConstants, Storage, Version {
    using SafeMath for uint256;

    function currentEpoch() public view returns (uint256) {
        return currentSealedEpoch + 1;
    }

    function _setGenesisDelegation(address delegator, uint256 toValidatorID, uint256 amount, uint256 rewards) external notInitialized {
        _stake(delegator, toValidatorID, amount);
        rewardsStash[delegator][toValidatorID] = rewards;
    }

    function initialize(uint256 sealedEpoch) external initializer {
        Ownable.initialize(msg.sender);
        currentSealedEpoch = sealedEpoch;
    }

    function createValidator(bytes calldata pubkey) external payable {
        require(msg.value >= minSelfStake(), "insufficient self-stake");
        _createValidator(msg.sender, pubkey);
        _stake(msg.sender, lastValidatorID, msg.value);
    }

    function _createValidator(address auth, bytes memory pubkey) internal {
        uint256 validatorID = ++lastValidatorID;
        require(getValidatorID[auth] == 0, "validator already exists");
        getValidator[validatorID] = Validator(OK_STATUS, 0, 0, 0, currentEpoch(), now, auth, pubkey);
    }

    function _isSelfStake(address delegator, uint256 toValidatorID) internal view returns (bool) {
        return getValidatorID[delegator] == toValidatorID;
    }

    function _getSelfStake(uint256 validatorID) internal view returns (uint256) {
        return getDelegation[getValidator[validatorID].auth][validatorID];
    }

    function _checkDelegatedStakeLimit(uint256 validatorID) internal view returns (bool) {
        return getValidator[validatorID].receivedStake <= _getSelfStake(validatorID).mul(maxDelegatedRatio()).div(Decimal.unit());
    }

    function stake(uint256 toValidatorID) external payable {
        require(getValidator[toValidatorID].status == OK_STATUS, "validator isn't active");
        _stake(msg.sender, toValidatorID, msg.value);
    }

    function _stake(address delegator, uint256 toValidatorID, uint256 amount) internal {
        require(_validatorExists(toValidatorID), "validator doesn't exist");
        require(amount > 0, "zero amount");

        _stashRewards(delegator, toValidatorID);

        getDelegation[delegator][toValidatorID] = getDelegation[delegator][toValidatorID].add(amount);
        getValidator[toValidatorID].receivedStake = getValidator[toValidatorID].receivedStake.add(amount);
        totalStake = totalStake.add(amount);

        require(_checkDelegatedStakeLimit(toValidatorID), "validator's delegations limit is exceeded");
        _syncValidator(toValidatorID);
    }

    function _setValidatorDeactivated(uint256 validatorID, uint256 status) internal {
        // status as a number is proportional to severity
        if (status > getValidator[validatorID].status) {
            getValidator[validatorID].status = status;
            if (getValidator[validatorID].deactivatedEpoch == 0) {
                getValidator[validatorID].deactivatedTime = now;
                getValidator[validatorID].deactivatedEpoch = currentEpoch();
            }
        }
    }

    function startUnstake(uint256 toValidatorID, uint256 urID, uint256 amount) external {
        address delegator = msg.sender;

        _stashRewards(delegator, toValidatorID);

        require(amount > 0, "zero amount");
        require(amount <= getDelegation[delegator][toValidatorID], "not enough stake");
        require(getUnstakingRequest[delegator][toValidatorID][urID].amount == 0, "urID already exists");

        getDelegation[delegator][toValidatorID] -= amount;
        getValidator[toValidatorID].receivedStake = getValidator[toValidatorID].receivedStake.sub(amount);
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
        if (getValidator[toValidatorID].deactivatedTime != 0 && getValidator[toValidatorID].deactivatedTime < requestTime) {
            requestTime = getValidator[toValidatorID].deactivatedTime;
            requestEpoch = getValidator[toValidatorID].deactivatedEpoch;
        }

        require(now >= requestTime + unstakePeriodTime(), "not enough time passed");
        require(currentEpoch() >= requestEpoch + unstakePeriodEpochs(), "not enough epochs passed");

        uint256 amount = getUnstakingRequest[delegator][toValidatorID][urID].amount;
        delete getUnstakingRequest[delegator][toValidatorID][urID];

        uint256 slashingPenalty = 0;
        bool isCheater = getValidator[toValidatorID].status & CHEATER_MASK != 0;

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

    function _calcRawValidatorEpochBaseReward(uint256 epochDuration, uint256 baseRewardPerSecond, uint256 baseRewardWeight, uint256 totalBaseRewardWeight) internal pure returns (uint256) {
        if (baseRewardWeight == 0) {
            return 0;
        }
        uint256 totalReward = epochDuration.mul(baseRewardPerSecond);
        return totalReward.mul(baseRewardWeight).div(totalBaseRewardWeight);
    }

    function _calcRawValidatorEpochTxReward(uint256 epochFee, uint256 txRewardWeight, uint256 totalTxRewardWeight) internal pure returns (uint256) {
        if (txRewardWeight == 0) {
            return 0;
        }
        uint256 txReward = epochFee.mul(txRewardWeight).div(totalTxRewardWeight);
        // fee reward except contractCommission
        return txReward.mul(Decimal.unit() - contractCommission()).div(Decimal.unit());
    }

    function _calcValidatorCommission(uint256 rawReward, uint256 commission) internal pure returns (uint256)  {
        return rawReward.mul(commission).div(Decimal.unit());
    }

    function _highestPayableEpoch(uint256 validatorID) internal view returns (uint256) {
        if (getValidator[validatorID].deactivatedEpoch != 0) {
            if (currentSealedEpoch < getValidator[validatorID].deactivatedEpoch) {
                return currentSealedEpoch;
            }
            return getValidator[validatorID].deactivatedEpoch;
        }
        return currentSealedEpoch;
    }

    function pendingRewards(address delegator, uint256 toValidatorID) public view returns (uint256) {
        uint256 claimedUntil = claimedRewardUntilEpoch[delegator][toValidatorID];
        uint256 claimedRate = getEpochSnapshot[claimedUntil].accumulatedRewardPerToken[toValidatorID];
        uint256 currentRate = getEpochSnapshot[_highestPayableEpoch(toValidatorID)].accumulatedRewardPerToken[toValidatorID];
        uint256 pending = currentRate.sub(claimedRate).mul(getDelegation[delegator][toValidatorID]).div(Decimal.unit());
        return rewardsStash[delegator][toValidatorID].add(pending);
    }

    function stashRewards(address delegator, uint256 toValidatorID) external {
        require(_stashRewards(delegator, toValidatorID), "nothing to stash");
    }

    function _stashRewards(address delegator, uint256 toValidatorID) internal returns (bool updated) {
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

    // _syncValidator updates the validator data on node
    function _syncValidator(uint256 validatorID) public {
        require(_validatorExists(validatorID), "validator doesn't exist");
        // emit special log for node
        uint256 weight = getValidator[validatorID].receivedStake;
        if (getValidator[validatorID].status != OK_STATUS) {
            weight = 0;
        }
        emit UpdatedValidatorWeight(validatorID, weight);
    }

    function _validatorExists(uint256 validatorID) view internal returns (bool) {
        return getValidator[validatorID].createdTime != 0;
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

    function _sealEpoch_offline(EpochSnapshot storage snapshot, uint256[] memory validatorIDs, uint256[] memory offlineTimes, uint256[] memory offlineBlocks) internal {
        // mark offline nodes
        for (uint256 i = 0; i < validatorIDs.length; i++) {
            if (offlineBlocks[i] > offlinePenaltyThresholdBlocksNum && offlineTimes[i] >= offlinePenaltyThresholdTime) {
                _setValidatorDeactivated(validatorIDs[i], OFFLINE_BIT);
                _syncValidator(validatorIDs[i]);
            }
            // log data
            snapshot.offlineTimes[validatorIDs[i]] = offlineTimes[i];
            snapshot.offlineBlocks[validatorIDs[i]] = offlineBlocks[i];
        }
    }

    function _sealEpoch_rewards(EpochSnapshot storage snapshot, uint256[] memory validatorIDs, uint256[] memory uptimes, uint256[] memory originatedTxsFee) internal {
        _SealEpochRewardsCtx memory ctx = _SealEpochRewardsCtx(new uint[](validatorIDs.length), 0, new uint[](validatorIDs.length), 0, 0, 0);
        EpochSnapshot storage prevSnapshot = getEpochSnapshot[currentEpoch().sub(1)];

        ctx.epochDuration = 1;
        if (now > prevSnapshot.endTime) {
            ctx.epochDuration = now - prevSnapshot.endTime;
        }

        for (uint256 i = 0; i < validatorIDs.length; i++) {
            // txRewardWeight = {originatedTxsFee} * {uptime}
            // originatedTxsFee is roughly proportional to {uptime} * {stake}, so the whole formula is roughly
            // {stake} * {uptime} ^ 2
            ctx.txRewardWeights[i] = originatedTxsFee[i].mul(uptimes[i]).div(ctx.epochDuration);
            ctx.totalTxRewardWeight = ctx.totalTxRewardWeight.add(ctx.txRewardWeights[i]);
            ctx.epochFee = ctx.epochFee.add(originatedTxsFee[i]);
        }

        for (uint256 i = 0; i < validatorIDs.length; i++) {
            // baseRewardWeight = {stake} * {uptime ^ 2}
            ctx.baseRewardWeights[i] = snapshot.receivedStakes[validatorIDs[i]].mul(uptimes[i]).div(ctx.epochDuration).mul(uptimes[i]).div(ctx.epochDuration);
            ctx.totalBaseRewardWeight = ctx.totalBaseRewardWeight.add(ctx.baseRewardWeights[i]);
        }

        for (uint256 i = 0; i < validatorIDs.length; i++) {
            uint256 rawReward = _calcRawValidatorEpochBaseReward(ctx.epochDuration, baseRewardPerSecond, ctx.baseRewardWeights[i], ctx.totalBaseRewardWeight);
            rawReward = rawReward.add(_calcRawValidatorEpochTxReward(ctx.epochFee, ctx.txRewardWeights[i], ctx.totalTxRewardWeight));

            // accounting validator's commission
            uint256 commissionReward = _calcValidatorCommission(rawReward, validatorCommission());
            uint256 validatorStash = rewardsStash[getValidator[validatorIDs[i]].auth][validatorIDs[i]];
            validatorStash = validatorStash.add(commissionReward);
            rewardsStash[getValidator[validatorIDs[i]].auth][validatorIDs[i]] = validatorStash;
            // accounting reward per token for delegators
            uint256 delegatorsReward = rawReward - commissionReward;
            uint256 rewardPerToken = delegatorsReward.mul(Decimal.unit()).div(totalStake);
            snapshot.accumulatedRewardPerToken[validatorIDs[i]] = prevSnapshot.accumulatedRewardPerToken[validatorIDs[i]].add(rewardPerToken);
            //
            snapshot.accumulatedOriginatedTxsFee[validatorIDs[i]] = prevSnapshot.accumulatedOriginatedTxsFee[validatorIDs[i]].add(originatedTxsFee[i]);
            snapshot.accumulatedUptimes[validatorIDs[i]] = prevSnapshot.accumulatedUptimes[validatorIDs[i]].add(uptimes[i]);
        }

        snapshot.epochFee = ctx.epochFee;
        snapshot.totalBaseRewardWeight = ctx.totalBaseRewardWeight;
        snapshot.totalTxRewardWeight = ctx.totalTxRewardWeight;
    }

    function sealEpoch(uint256[] calldata offlineTimes, uint256[] calldata offlineBlocks, uint256[] calldata uptimes, uint256[] calldata originatedTxsFee) external {
        require(msg.sender == address(0), "not callable");
        _sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFee);
    }

    function _sealEpoch(uint256[] memory offlineTimes, uint256[] memory offlineBlocks, uint256[] memory uptimes, uint256[] memory originatedTxsFee) internal {
        EpochSnapshot storage snapshot = getEpochSnapshot[currentEpoch()];
        uint256[] memory validatorIDs = snapshot.validatorIDs;

        _sealEpoch_offline(snapshot, validatorIDs, offlineTimes, offlineBlocks);
        _sealEpoch_rewards(snapshot, validatorIDs, uptimes, originatedTxsFee);

        currentSealedEpoch = currentEpoch();
        snapshot.endTime = now;
        snapshot.baseRewardPerSecond = baseRewardPerSecond;
        snapshot.totalSupply = totalSupply;
    }


    function _sealEpochValidators(uint256[] memory nextValidatorIDs) internal {
        // fill data for the next snapshot
        EpochSnapshot storage snapshot = getEpochSnapshot[currentEpoch()];
        for (uint256 i = 0; i < nextValidatorIDs.length; i++) {
            uint256 receivedStake = getValidator[nextValidatorIDs[i]].receivedStake;
            snapshot.receivedStakes[nextValidatorIDs[i]] = receivedStake;
            snapshot.totalStake = snapshot.totalStake.add(receivedStake);
        }
        snapshot.validatorIDs = nextValidatorIDs;
    }

    function sealEpochValidators(uint256[] calldata nextValidatorIDs) external {
        require(msg.sender == address(0), "not callable");
        _sealEpochValidators(nextValidatorIDs);
    }
}
