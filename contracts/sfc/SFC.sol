pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./StakerConstants.sol";
import "../ownership/Ownable.sol";
import "../version/Version.sol";
import "./NodeInterface.sol";

/**
 * @dev Stakers contract defines data structure and methods for validators / validators.
 */
contract SFC is Initializable, NodeInterface, Ownable, StakersConstants, Version {
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
    }

    uint256 public currentSealedEpoch;
    mapping(uint256 => Validator) public getValidator;
    mapping(address => uint256) public getValidatorID;
    mapping(uint256 => bytes) public getValidatorPubkey;

    uint256 public lastValidatorID;
    uint256 public totalStake;
    uint256 public totalSlashedStake;

    mapping(address => mapping(uint256 => uint256)) public rewardsStash; // addr, validatorID -> StashedRewards

    struct UnstakingRequest {
        uint256 epoch;
        uint256 time;

        uint256 amount;
    }

    mapping(address => mapping(uint256 => mapping(uint256 => UnstakingRequest))) public getUnstakingRequest;

    struct LockedDelegation {
        uint256 lockedStake;
        uint256 fromEpoch;
        uint256 endTime;
        uint256 duration;
        uint256 earlyUnlockPenalty;
    }

    mapping(address => mapping(uint256 => uint256)) public getStake;

    mapping(address => mapping(uint256 => LockedDelegation)) public getLockupInfo;

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

    /*
    Getters
    */

    function currentEpoch() public view returns (uint256) {
        return currentSealedEpoch + 1;
    }

    /*
    Constructor
    */

    function _setGenesisValidator(address auth, uint256 validatorID, bytes calldata pubkey, uint256 status, uint256 createdEpoch, uint256 createdTime, uint256 deactivatedEpoch, uint256 deactivatedTime) external notInitialized {
        _rawCreateValidator(auth, validatorID, pubkey, status, createdEpoch, createdTime, deactivatedEpoch, deactivatedTime);
        if (validatorID > lastValidatorID) {
            lastValidatorID = validatorID;
        }
    }

    function _setGenesisDelegation(address delegator, uint256 toValidatorID, uint256 amount, uint256 rewards) external notInitialized {
        _rawStake(delegator, toValidatorID, amount);
        rewardsStash[delegator][toValidatorID] = rewards;
    }

    function initialize(uint256 sealedEpoch) external initializer {
        Ownable.initialize(msg.sender);
        currentSealedEpoch = sealedEpoch;
    }

    /*
    Methods
    */

    function createValidator(bytes calldata pubkey) external payable {
        require(msg.value >= minSelfStake(), "insufficient self-stake");
        _createValidator(msg.sender, pubkey);
        _stake(msg.sender, lastValidatorID, msg.value);
    }

    function _createValidator(address auth, bytes memory pubkey) internal {
        uint256 validatorID = ++lastValidatorID;
        _rawCreateValidator(auth, validatorID, pubkey, OK_STATUS, currentEpoch(), _now(), 0, 0);
    }

    function _rawCreateValidator(address auth, uint256 validatorID, bytes memory pubkey, uint256 status, uint256 createdEpoch, uint256 createdTime, uint256 deactivatedEpoch, uint256 deactivatedTime) internal {
        require(getValidatorID[auth] == 0, "validator already exists");
        getValidatorID[auth] = validatorID;
        getValidator[validatorID].status = status;
        getValidator[validatorID].createdEpoch = createdEpoch;
        getValidator[validatorID].createdTime = createdTime;
        getValidator[validatorID].deactivatedTime = deactivatedTime;
        getValidator[validatorID].deactivatedEpoch = deactivatedEpoch;
        getValidator[validatorID].auth = auth;
        getValidatorPubkey[validatorID] = pubkey;
        emit UpdatedValidatorPubkey(validatorID, pubkey);
    }

    function _isSelfStake(address delegator, uint256 toValidatorID) internal view returns (bool) {
        return getValidatorID[delegator] == toValidatorID;
    }

    function _getSelfStake(uint256 validatorID) internal view returns (uint256) {
        return getStake[getValidator[validatorID].auth][validatorID];
    }

    function _checkDelegatedStakeLimit(uint256 validatorID) internal view returns (bool) {
        return getValidator[validatorID].receivedStake <= _getSelfStake(validatorID).mul(maxDelegatedRatio()).div(Decimal.unit());
    }

    function stake(uint256 toValidatorID) external payable {
        _stake(msg.sender, toValidatorID, msg.value);
    }

    function _stake(address delegator, uint256 toValidatorID, uint256 amount) internal {
        require(_validatorExists(toValidatorID), "validator doesn't exist");
        require(getValidator[toValidatorID].status == OK_STATUS, "validator isn't active");
        _rawStake(delegator, toValidatorID, amount);
        require(_checkDelegatedStakeLimit(toValidatorID), "validator's delegations limit is exceeded");
    }

    function _rawStake(address delegator, uint256 toValidatorID, uint256 amount) internal {
        require(amount > 0, "zero amount");

        _stashRewards(delegator, toValidatorID);

        getStake[delegator][toValidatorID] = getStake[delegator][toValidatorID].add(amount);
        getValidator[toValidatorID].receivedStake = getValidator[toValidatorID].receivedStake.add(amount);
        totalStake = totalStake.add(amount);

        _syncValidator(toValidatorID);
    }

    function _setValidatorDeactivated(uint256 validatorID, uint256 status) internal {
        // status as a number is proportional to severity
        if (status > getValidator[validatorID].status) {
            getValidator[validatorID].status = status;
            if (getValidator[validatorID].deactivatedEpoch == 0) {
                getValidator[validatorID].deactivatedTime = _now();
                getValidator[validatorID].deactivatedEpoch = currentEpoch();
            }
        }
    }

    function startUnstake(uint256 toValidatorID, uint256 urID, uint256 amount) external {
        address delegator = msg.sender;

        _stashRewards(delegator, toValidatorID);

        require(amount > 0, "zero amount");
        require(amount <= getUnlockedStake(delegator, toValidatorID), "not enough unlocked stake");

        require(getUnstakingRequest[delegator][toValidatorID][urID].amount == 0, "urID already exists");

        getStake[delegator][toValidatorID] -= amount;
        getValidator[toValidatorID].receivedStake = getValidator[toValidatorID].receivedStake.sub(amount);
        totalStake = totalStake.sub(amount);

        require(_checkDelegatedStakeLimit(toValidatorID) || _getSelfStake(toValidatorID) == 0, "validator's delegations limit is exceeded");
        if (_getSelfStake(toValidatorID) == 0) {
            _setValidatorDeactivated(toValidatorID, WITHDRAWN_BIT);
        }

        getUnstakingRequest[delegator][toValidatorID][urID].amount = amount;
        getUnstakingRequest[delegator][toValidatorID][urID].epoch = currentEpoch();
        getUnstakingRequest[delegator][toValidatorID][urID].time = _now();

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

        require(_now() >= requestTime + unstakePeriodTime(), "not enough time passed");
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


    function _deactivateValidator(uint256 validatorID, uint256 status) external {
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

    mapping(address => mapping(uint256 => uint256)) public claimedRewardUntilEpoch;

    function _highestPayableEpoch(uint256 validatorID) internal view returns (uint256) {
        if (getValidator[validatorID].deactivatedEpoch != 0) {
            if (currentSealedEpoch < getValidator[validatorID].deactivatedEpoch) {
                return currentSealedEpoch;
            }
            return getValidator[validatorID].deactivatedEpoch;
        }
        return currentSealedEpoch;
    }

    // find highest epoch such that _isLockedUpAtEpoch returns true (using binary search)
    function _highestLockupEpoch(address delegator, uint256 validatorID) internal view returns (uint256) {
        uint256 l = getLockupInfo[delegator][validatorID].fromEpoch;
        uint256 r = currentSealedEpoch;
        if (_isLockedUpAtEpoch(delegator, validatorID, r)) {
            return r;
        }
        if (!_isLockedUpAtEpoch(delegator, validatorID, l)) {
            return 0;
        }
        if (l > r) {
            return 0;
        }
        while (l < r) {
            uint256 m = (l + r) / 2;
            if (_isLockedUpAtEpoch(delegator, validatorID, m)) {
                l = m + 1;
            } else {
                r = m;
            }
        }
        if (r == 0) {
            return 0;
        }
        return r - 1;
    }

    function _scaleLockupReward(uint256 fullReward, bool isLockedUp, uint256 lockupDuration) private pure returns (uint256 reward, uint256 penalty) {
        if (isLockedUp) {
            uint256 maxLockupExtraRatio = Decimal.unit() - unlockedRewardRatio();
            uint256 lockupExtraRatio = maxLockupExtraRatio.mul(lockupDuration).div(maxLockupDuration());
            reward = fullReward.mul(unlockedRewardRatio() + lockupExtraRatio).div(Decimal.unit());
            penalty = fullReward.mul(unlockedRewardRatio() / 2 + lockupExtraRatio).div(Decimal.unit());
        } else {
            reward = fullReward.mul(unlockedRewardRatio()).div(Decimal.unit());
            penalty = 0;
        }
        return (reward, penalty);
    }

    function _nonStashedRewards(address delegator, uint256 toValidatorID) internal view returns (uint256 reward, uint256 penalty) {
        uint256 claimedUntil = claimedRewardUntilEpoch[delegator][toValidatorID];
        uint256 payableUntil = _highestPayableEpoch(toValidatorID);
        uint256 lockedUntil = _highestLockupEpoch(delegator, toValidatorID);
        if (lockedUntil > payableUntil) {
            lockedUntil = payableUntil;
        }
        if (lockedUntil < claimedUntil) {
            lockedUntil = claimedUntil;
        }

        LockedDelegation storage ld = getLockupInfo[delegator][toValidatorID];
        uint256 wholeStake = getStake[delegator][toValidatorID];
        uint256 unlockedStake = wholeStake.sub(ld.lockedStake);
        uint256 fullReward;

        // count reward for locked stake during lockup epochs
        fullReward = _nonStashedRewardsOf(ld.lockedStake, toValidatorID, claimedUntil, lockedUntil);
        (uint256 plReward, uint256 plPenalty) = _scaleLockupReward(fullReward, true, ld.duration);
        // count reward for unlocked stake during lockup epochs
        fullReward = _nonStashedRewardsOf(unlockedStake, toValidatorID, claimedUntil, lockedUntil);
        (uint256 puReward, uint256 puPenalty) = _scaleLockupReward(fullReward, false, ld.duration);
        // count lockup reward for unlocked stake during unlocked epochs
        fullReward = _nonStashedRewardsOf(wholeStake, toValidatorID, lockedUntil, payableUntil);
        (uint256 wuReward, uint256 wuPenalty) = _scaleLockupReward(fullReward, false, ld.duration);

        return (plReward.add(puReward).add(wuReward), plPenalty.add(puPenalty).add(wuPenalty));
    }

    function _nonStashedRewardsOf(uint256 stakeAmount, uint256 toValidatorID, uint256 fromEpoch, uint256 toEpoch) public view returns (uint256) {
        if (fromEpoch >= toEpoch) {
            return 0;
        }
        uint256 claimedRate = getEpochSnapshot[fromEpoch].accumulatedRewardPerToken[toValidatorID];
        uint256 currentRate = getEpochSnapshot[toEpoch].accumulatedRewardPerToken[toValidatorID];
        return currentRate.sub(claimedRate).mul(stakeAmount).div(Decimal.unit());
    }

    function pendingRewards(address delegator, uint256 toValidatorID) public view returns (uint256) {
        (uint256 reward,) = _nonStashedRewards(delegator, toValidatorID);
        return rewardsStash[delegator][toValidatorID].add(reward);
    }

    function stashRewards(address delegator, uint256 toValidatorID) external {
        require(_stashRewards(delegator, toValidatorID), "nothing to stash");
    }

    function _stashRewards(address delegator, uint256 toValidatorID) internal returns (bool updated) {
        (uint256 nonStashedReward, uint256 nonStashedPenalty) = _nonStashedRewards(delegator, toValidatorID);
        claimedRewardUntilEpoch[delegator][toValidatorID] = _highestPayableEpoch(toValidatorID);
        rewardsStash[delegator][toValidatorID] = rewardsStash[delegator][toValidatorID].add(nonStashedReward);
        LockedDelegation storage ld = getLockupInfo[delegator][toValidatorID];
        ld.earlyUnlockPenalty = ld.earlyUnlockPenalty.add(nonStashedPenalty);
        return true;
    }

    function _mintNativeToken(uint256 amount) internal {
        // balance will be increased after the transaction is processed
        emit IncBalance(address(this), amount);
    }

    function claimRewards(uint256 toValidatorID) external {
        address payable delegator = msg.sender;
        _stashRewards(delegator, toValidatorID);
        uint256 rewards = rewardsStash[delegator][toValidatorID];
        require(rewards != 0, "zero rewards");
        delete rewardsStash[delegator][toValidatorID];
        // It's important that we transfer after erasing (protection against Re-Entrancy)
        delegator.transfer(rewards);
        _mintNativeToken(rewards);
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

    event UpdatedBaseRewardPerSec(uint256 value);
    event UpdatedOfflinePenaltyThreshold(uint256 blocksNum, uint256 period);

    uint256 offlinePenaltyThresholdBlocksNum;
    uint256 offlinePenaltyThresholdTime;

    function offlinePenaltyThreshold() public view returns (uint256 blocksNum, uint256 time) {
        return (offlinePenaltyThresholdBlocksNum, offlinePenaltyThresholdTime);
    }

    function _updateGasPowerAllocationRate(uint256 short, uint256 long) onlyOwner external {
        emit UpdatedGasPowerAllocationRate(short, long);
    }

    function _updateBaseRewardPerSecond(uint256 value) onlyOwner external {
        baseRewardPerSecond = value;
        emit UpdatedBaseRewardPerSec(value);
    }

    function _updateOfflinePenaltyThreshold(uint256 blocksNum, uint256 time) onlyOwner external {
        offlinePenaltyThresholdTime = time;
        offlinePenaltyThresholdBlocksNum = blocksNum;
        emit UpdatedOfflinePenaltyThreshold(blocksNum, time);
    }

    function _updateMinGasPrice(uint256 minGasPrice) onlyOwner external {
        emit UpdatedMinGasPrice(minGasPrice);
    }

    uint256 public baseRewardPerSecond;
    uint256 public totalSupply;
    mapping(uint256 => EpochSnapshot) public getEpochSnapshot;

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

    struct _SealEpochRewardsCtx {
        uint256[] baseRewardWeights;
        uint256 totalBaseRewardWeight;
        uint256[] txRewardWeights;
        uint256 totalTxRewardWeight;
        uint256 epochDuration;
        uint256 epochFee;
    }

    function _sealEpoch_rewards(EpochSnapshot storage snapshot, uint256[] memory validatorIDs, uint256[] memory uptimes, uint256[] memory originatedTxsFee) internal {
        _SealEpochRewardsCtx memory ctx = _SealEpochRewardsCtx(new uint[](validatorIDs.length), 0, new uint[](validatorIDs.length), 0, 0, 0);
        EpochSnapshot storage prevSnapshot = getEpochSnapshot[currentEpoch().sub(1)];

        ctx.epochDuration = 1;
        if (_now() > prevSnapshot.endTime) {
            ctx.epochDuration = _now() - prevSnapshot.endTime;
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

            uint256 validatorID = validatorIDs[i];
            address validatorAddr = getValidator[validatorID].auth;
            // accounting validator's commission
            LockedDelegation storage ld = getLockupInfo[validatorAddr][validatorID];
            uint256 commissionRewardFull = _calcValidatorCommission(rawReward, validatorCommission());
            {
                uint256 lCommissionRewardFull = commissionRewardFull * getLockedStake(validatorAddr, validatorID) / getStake[validatorAddr][validatorID];
                uint256 uCommissionRewardFull = commissionRewardFull - lCommissionRewardFull;
                (uint256 lCommissionReward, uint256 lCommissionPenalty) = _scaleLockupReward(lCommissionRewardFull, true, ld.duration);
                (uint256 uCommissionReward, uint256 uCommissionPenalty) = _scaleLockupReward(uCommissionRewardFull, false, ld.duration);
                rewardsStash[validatorAddr][validatorID] = rewardsStash[validatorAddr][validatorID].add(lCommissionReward).add(uCommissionReward);
                ld.earlyUnlockPenalty = ld.earlyUnlockPenalty.add(lCommissionPenalty).add(uCommissionPenalty);
            }
            // accounting reward per token for delegators
            uint256 delegatorsReward = rawReward - commissionRewardFull;
            uint256 rewardPerToken = delegatorsReward.mul(Decimal.unit()).div(totalStake);
            snapshot.accumulatedRewardPerToken[validatorID] = prevSnapshot.accumulatedRewardPerToken[validatorID].add(rewardPerToken);
            //
            snapshot.accumulatedOriginatedTxsFee[validatorID] = prevSnapshot.accumulatedOriginatedTxsFee[validatorID].add(originatedTxsFee[i]);
            snapshot.accumulatedUptimes[validatorID] = prevSnapshot.accumulatedUptimes[validatorID].add(uptimes[i]);
        }

        snapshot.epochFee = ctx.epochFee;
        snapshot.totalBaseRewardWeight = ctx.totalBaseRewardWeight;
        snapshot.totalTxRewardWeight = ctx.totalTxRewardWeight;
    }

    function __sealEpoch(uint256[] memory offlineTimes, uint256[] memory offlineBlocks, uint256[] memory uptimes, uint256[] memory originatedTxsFee) internal {
        EpochSnapshot storage snapshot = getEpochSnapshot[currentEpoch()];
        uint256[] memory validatorIDs = snapshot.validatorIDs;

        _sealEpoch_offline(snapshot, validatorIDs, offlineTimes, offlineBlocks);
        _sealEpoch_rewards(snapshot, validatorIDs, uptimes, originatedTxsFee);

        currentSealedEpoch = currentEpoch();
        snapshot.endTime = _now();
        snapshot.baseRewardPerSecond = baseRewardPerSecond;
        snapshot.totalSupply = totalSupply;
    }

    function _sealEpoch(uint256[] calldata offlineTimes, uint256[] calldata offlineBlocks, uint256[] calldata uptimes, uint256[] calldata originatedTxsFee) external {
        require(msg.sender == address(0), "not callable");
        __sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFee);
    }

    function __sealEpochValidators(uint256[] memory nextValidatorIDs) internal {
        // fill data for the next snapshot
        EpochSnapshot storage snapshot = getEpochSnapshot[currentEpoch()];
        for (uint256 i = 0; i < nextValidatorIDs.length; i++) {
            uint256 receivedStake = getValidator[nextValidatorIDs[i]].receivedStake;
            snapshot.receivedStakes[nextValidatorIDs[i]] = receivedStake;
            snapshot.totalStake = snapshot.totalStake.add(receivedStake);
        }
        snapshot.validatorIDs = nextValidatorIDs;
    }

    function _sealEpochValidators(uint256[] calldata nextValidatorIDs) external {
        require(msg.sender == address(0), "not callable");
        __sealEpochValidators(nextValidatorIDs);
    }

    function _now() internal view returns (uint256) {
        return block.timestamp;
    }

    function epochEndTime(uint256 epoch) view internal returns (uint256) {
        return getEpochSnapshot[epoch].endTime;
    }

    function isLockedUp(address delegator, uint256 toValidatorID) view public returns (bool) {
        return getLockupInfo[delegator][toValidatorID].endTime != 0 && _now() <= getLockupInfo[delegator][toValidatorID].endTime;
    }

    function _isLockedUpAtEpoch(address delegator, uint256 toValidatorID, uint256 epoch) internal view returns (bool) {
        return getLockupInfo[delegator][toValidatorID].fromEpoch <= epoch && epochEndTime(epoch) <= getLockupInfo[delegator][toValidatorID].endTime;
    }

    function getUnlockedStake(address delegator, uint256 toValidatorID) public view returns (uint256) {
        if (!isLockedUp(delegator, toValidatorID)) {
            return getStake[delegator][toValidatorID];
        }
        return getStake[delegator][toValidatorID].sub(getLockupInfo[delegator][toValidatorID].lockedStake);
    }

    function getLockedStake(address delegator, uint256 toValidatorID) public view returns (uint256) {
        if (!isLockedUp(delegator, toValidatorID)) {
            return 0;
        }
        return getLockupInfo[delegator][toValidatorID].lockedStake;
    }

    event LockedUpStake(address indexed delegator, uint256 indexed validatorID, uint256 duration, uint256 amount);

    function lockStake(uint256 toValidatorID, uint256 lockupDuration, uint256 amount) external {
        address delegator = msg.sender;

        require(amount > 0, "zero amount");
        require(!isLockedUp(delegator, toValidatorID), "already locked up");
        require(amount <= getUnlockedStake(delegator, toValidatorID), "not enough stake");
        require(getValidator[toValidatorID].status == OK_STATUS, "validator isn't active");

        require(lockupDuration >= minLockupDuration() && lockupDuration <= maxLockupDuration(), "incorrect duration");
        uint256 endTime = _now().add(lockupDuration);
        address validatorAddr = getValidator[toValidatorID].auth;
        if (delegator != validatorAddr) {
            require(getLockupInfo[validatorAddr][toValidatorID].endTime >= endTime, "validator lockup period will end earlier");
        }

        _stashRewards(delegator, toValidatorID);

        LockedDelegation storage ld = getLockupInfo[delegator][toValidatorID];
        ld.lockedStake = amount;
        ld.fromEpoch = currentEpoch();
        ld.endTime = endTime;
        ld.duration = lockupDuration;
        ld.earlyUnlockPenalty = 0;

        emit LockedUpStake(delegator, toValidatorID, lockupDuration, amount);
    }

    function _calcDelegationUnlockPenalty(uint256 totalPenaltyAmount, uint256 unlockAmount, uint256 totalAmount) internal pure returns (uint256) {
        uint256 penalty = totalPenaltyAmount.mul(unlockAmount).div(totalAmount);
        if (penalty >= unlockAmount) {
            penalty = unlockAmount;
        }
        return penalty;
    }

    event UnlockedStake(address indexed delegator, uint256 indexed validatorID, uint256 amount, uint256 penalty);

    function unlockStake(uint256 toValidatorID, uint256 amount) external returns (uint256) {
        address delegator = msg.sender;
        LockedDelegation storage ld = getLockupInfo[delegator][toValidatorID];

        require(amount > 0, "zero amount");
        require(isLockedUp(delegator, toValidatorID), "not locked up");
        require(amount <= ld.lockedStake, "not enough locked stake");

        _stashRewards(delegator, toValidatorID);

        uint256 penalty = _calcDelegationUnlockPenalty(ld.earlyUnlockPenalty, amount, ld.lockedStake);

        ld.earlyUnlockPenalty -= penalty;
        ld.lockedStake -= amount;
        getStake[delegator][toValidatorID] -= penalty;

        emit UnlockedStake(delegator, toValidatorID, amount, penalty);
        return penalty;
    }
}
