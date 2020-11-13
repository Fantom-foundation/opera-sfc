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
    }

    uint256 public currentSealedEpoch;

    mapping(address => Validator) public getValidator;
    mapping(address => bytes) public getValidatorPubkey;

    address public lastValidatorID;
    uint256 public totalStake;
    uint256 public totalSlashedStake;

    mapping(uint256 => bytes) public validatorMetadata;

    mapping(address => mapping(address => uint256)) public rewardsStash; // addr, validatorID -> StashedRewards

    struct UnstakingRequest {
        uint256 epoch;
        uint256 time;

        uint256 amount;
    }

    mapping(address => mapping(address => mapping(address => UnstakingRequest))) public getUnstakingRequest;

    mapping(address => mapping(address => uint256)) public getDelegation;

    struct EpochSnapshot {
        mapping(uint256 => uint256) receivedStakes;
        mapping(address => uint256) accumulatedRewardPerToken;
        mapping(uint256 => uint256) accumulatedUptimes;
        mapping(uint256 => uint256) accumulatedOriginatedTxsFee;
        mapping(address => uint256) offlineTimes;
        mapping(address => uint256) offlineBlocks;

        address[] validatorIDs;

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


    /// Removed Auth + Replace validatorID(uint) by validatorAddress(address)
    function _setGenesisValidator(address validatorAddress, bytes calldata pubkey, uint256 status, uint256 createdEpoch, uint256 createdTime, uint256 deactivatedEpoch, uint256 deactivatedTime) external notInitialized {
        _rawCreateValidator(validatorAddress, pubkey, status, createdEpoch, createdTime, deactivatedEpoch, deactivatedTime);
    }

    function _setGenesisDelegation(address delegator, address validatorAddress, uint256 amount, uint256 rewards) external notInitialized {
        _rawStake(delegator, validatorAddress, amount);
        rewardsStash[delegator][validatorAddress] = rewards;
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
        _rawCreateValidator(auth, pubkey, OK_STATUS, currentEpoch(), _now(), 0, 0);
    }

    function _rawCreateValidator(address validatorAddress,  bytes memory pubkey, uint256 status, uint256 createdEpoch, uint256 createdTime, uint256 deactivatedEpoch, uint256 deactivatedTime) internal {
        require(getValidator[validatorAddress].createdTime == 0, "validator already exists");
        getValidator[validatorAddress].status = status;
        getValidator[validatorAddress].createdEpoch = createdEpoch;
        getValidator[validatorAddress].createdTime = createdTime;
        getValidator[validatorAddress].deactivatedTime = deactivatedTime;
        getValidator[validatorAddress].deactivatedEpoch = deactivatedEpoch;
        getValidatorPubkey[validatorAddress] = pubkey;
    }

    function _isSelfStake(address delegator, address validatorAddress) internal view returns (bool) {
        return delegator == validatorAddress;
    }

    function _getSelfStake(address validatorAddress) internal view returns (uint256) {
        return getDelegation[validatorAddress][validatorAddress];
    }

    function _checkDelegatedStakeLimit(address validatorAddress) internal view returns (bool) {
        return getValidator[validatorAddress].receivedStake <= _getSelfStake(validatorAddress).mul(maxDelegatedRatio()).div(Decimal.unit());
    }

    function stake(address validatorAddress) external payable {
        _stake(msg.sender, validatorAddress, msg.value);
    }

    function _stake(address delegator, address validatorAddress, uint256 amount) internal {
        require(getValidator[validatorAddress].status == OK_STATUS, "validator isn't active");
        _rawStake(delegator, validatorAddress, amount);
    }

    function _rawStake(address delegator, address validatorAddress, uint256 amount) internal {
        require(amount > 0, "zero amount");
        require(_validatorExists(validatorAddress), "validator doesn't exist");

        _stashRewards(delegator, validatorAddress);

        getDelegation[delegator][validatorAddress] = getDelegation[delegator][validatorAddress].add(amount);
        getValidator[validatorAddress].receivedStake = getValidator[validatorAddress].receivedStake.add(amount);
        totalStake = totalStake.add(amount);

        require(_checkDelegatedStakeLimit(validatorAddress), "validator's delegations limit is exceeded");
        _syncValidator(validatorAddress);
    }

    function _setValidatorDeactivated(address validatorAddress, uint256 status) internal {
        // status as a number is proportional to severity
        if (status > getValidator[validatorAddress].status) {
            getValidator[validatorAddress].status = status;
            if (getValidator[validatorAddress].deactivatedEpoch == 0) {
                getValidator[validatorAddress].deactivatedTime = _now();
                getValidator[validatorAddress].deactivatedEpoch = currentEpoch();
            }
        }
    }

    function startUnstake(address validatorAddress, address urID, uint256 amount) external {
        address delegator = msg.sender;

        _stashRewards(delegator, validatorAddress);

        require(amount > 0, "zero amount");
        require(amount <= getDelegation[delegator][validatorAddress], "not enough stake");

        require(getUnstakingRequest[delegator][validatorAddress][urID].amount == 0, "urID already exists");

        getDelegation[delegator][validatorAddress] -= amount;
        getValidator[validatorAddress].receivedStake = getValidator[validatorAddress].receivedStake.sub(amount);
        totalStake = totalStake.sub(amount);

        require(_checkDelegatedStakeLimit(validatorAddress) || _getSelfStake(validatorAddress) == 0, "validator's delegations limit is exceeded");
        if (_getSelfStake(validatorAddress) == 0) {
            _setValidatorDeactivated(validatorAddress, WITHDRAWN_BIT);
        }

        getUnstakingRequest[delegator][validatorAddress][urID].amount = amount;
        getUnstakingRequest[delegator][validatorAddress][urID].epoch = currentEpoch();
        getUnstakingRequest[delegator][validatorAddress][urID].time = _now();

        _syncValidator(validatorAddress);
    }

    function finishUnstake(address validatorAddress, address urID) external {
        address payable delegator = msg.sender;
        UnstakingRequest memory request = getUnstakingRequest[delegator][validatorAddress][urID];
        require(request.epoch != 0, "request doesn't exist");

        uint256 requestTime = request.time;
        uint256 requestEpoch = request.epoch;
        if (getValidator[validatorAddress].deactivatedTime != 0 && getValidator[validatorAddress].deactivatedTime < requestTime) {
            requestTime = getValidator[validatorAddress].deactivatedTime;
            requestEpoch = getValidator[validatorAddress].deactivatedEpoch;
        }

        require(_now() >= requestTime + unstakePeriodTime(), "not enough time passed");
        require(currentEpoch() >= requestEpoch + unstakePeriodEpochs(), "not enough epochs passed");

        uint256 amount = getUnstakingRequest[delegator][validatorAddress][urID].amount;
        delete getUnstakingRequest[delegator][validatorAddress][urID];

        uint256 slashingPenalty = 0;
        bool isCheater = getValidator[validatorAddress].status & CHEATER_MASK != 0;

        // It's important that we transfer after erasing (protection against Re-Entrancy)
        if (isCheater == false) {
            delegator.transfer(amount);
        } else {
            slashingPenalty = amount;
        }
        totalSlashedStake += slashingPenalty;
    }


    function _deactivateValidator(address validatorAddress, uint256 status) external {
        require(msg.sender == address(0), "not callable");
        require(status != OK_STATUS, "wrong status");

        _setValidatorDeactivated(validatorAddress, status);
        _syncValidator(validatorAddress);
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

    mapping(address => mapping(address => uint256)) public claimedRewardUntilEpoch;

    function _highestPayableEpoch(address validatorAddress) internal view returns (uint256) {
        if (getValidator[validatorAddress].deactivatedEpoch != 0) {
            if (currentSealedEpoch < getValidator[validatorAddress].deactivatedEpoch) {
                return currentSealedEpoch;
            }
            return getValidator[validatorAddress].deactivatedEpoch;
        }
        return currentSealedEpoch;
    }

    function pendingRewards(address delegator, address validatorAddress) public view returns (uint256) {
        uint256 claimedUntil = claimedRewardUntilEpoch[delegator][validatorAddress];
        uint256 claimedRate = getEpochSnapshot[claimedUntil].accumulatedRewardPerToken[validatorAddress];
        uint256 currentRate = getEpochSnapshot[_highestPayableEpoch(validatorAddress)].accumulatedRewardPerToken[validatorAddress];
        uint256 pending = currentRate.sub(claimedRate).mul(getDelegation[delegator][validatorAddress]).div(Decimal.unit());
        return rewardsStash[delegator][validatorAddress].add(pending);
    }

    function stashRewards(address delegator, address validatorAddress) external {
        require(_stashRewards(delegator, validatorAddress), "nothing to stash");
    }

    function _stashRewards(address delegator, address validatorAddress) internal returns (bool updated) {
        uint256 pending = pendingRewards(delegator, validatorAddress);
        claimedRewardUntilEpoch[delegator][validatorAddress] = _highestPayableEpoch(validatorAddress);
        if (rewardsStash[delegator][validatorAddress] == pending) {
            return false;
        }
        rewardsStash[delegator][validatorAddress] = pending;
        return true;
    }

    function _mintNativeToken(uint256 amount) internal {
        // balance will be increased after the transaction is processed
        emit IncBalance(address(this), amount);
    }

    function claimRewards(address validatorAddress) external {
        address payable delegator = msg.sender;
        uint256 pending = pendingRewards(delegator, validatorAddress);
        require(pending != 0, "zero rewards");
        delete rewardsStash[delegator][validatorAddress];
        claimedRewardUntilEpoch[delegator][validatorAddress] = _highestPayableEpoch(validatorAddress);
        // It's important that we transfer after erasing (protection against Re-Entrancy)
        delegator.transfer(pending);
        _mintNativeToken(pending);
    }

    // _syncValidator updates the validator data on node
    function _syncValidator(address validatorAddress) public {
        require(_validatorExists(validatorAddress), "validator doesn't exist");
        // emit special log for node
        uint256 weight = getValidator[validatorAddress].receivedStake;
        if (getValidator[validatorAddress].status != OK_STATUS) {
            weight = 0;
        }
        emit UpdatedValidatorWeight(validatorAddress, weight);
    }

    function _validatorExists(address validatorAddress) view internal returns (bool) {
        return getValidator[validatorAddress].createdTime != 0;
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

    function _sealEpoch_offline(EpochSnapshot storage snapshot, address[] memory validatorAddresses, uint256[] memory offlineTimes, uint256[] memory offlineBlocks) internal {
        // mark offline nodes
        for (uint256 i = 0; i < validatorAddresses.length; i++) {
            if (offlineBlocks[i] > offlinePenaltyThresholdBlocksNum && offlineTimes[i] >= offlinePenaltyThresholdTime) {
                _setValidatorDeactivated(validatorAddresses[i], OFFLINE_BIT);
                _syncValidator(validatorAddresses[i]);
            }
            // log data
            snapshot.offlineTimes[validatorAddresses[i]] = offlineTimes[i];
            snapshot.offlineBlocks[validatorAddresses[i]] = offlineBlocks[i];
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

            // accounting validator's commission
            uint256 commissionReward = _calcValidatorCommission(rawReward, validatorCommission());
            uint256 validatorStash = rewardsStash[getValidator[validatorIDs[i]]][validatorIDs[i]];
            validatorStash = validatorStash.add(commissionReward);
            rewardsStash[getValidator[validatorIDs[i]]][validatorIDs[i]] = validatorStash;
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

    function __sealEpoch(uint256[] memory offlineTimes, uint256[] memory offlineBlocks, uint256[] memory uptimes, uint256[] memory originatedTxsFee) internal {
        EpochSnapshot storage snapshot = getEpochSnapshot[currentEpoch()];
        address[] memory validatorAddresses = snapshot.validatorIDs;

        _sealEpoch_offline(snapshot, validatorAddresses, offlineTimes, offlineBlocks);
        _sealEpoch_rewards(snapshot, validatorAddresses, uptimes, originatedTxsFee);

        currentSealedEpoch = currentEpoch();
        snapshot.endTime = _now();
        snapshot.baseRewardPerSecond = baseRewardPerSecond;
        snapshot.totalSupply = totalSupply;
    }

    function _sealEpoch(uint256[] calldata offlineTimes, uint256[] calldata offlineBlocks, uint256[] calldata uptimes, uint256[] calldata originatedTxsFee) external {
        require(msg.sender == address(0), "not callable");
        __sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFee);
    }

    function __sealEpochValidators(address[] memory nextValidatorIDs) internal {
        // fill data for the next snapshot
        EpochSnapshot storage snapshot = getEpochSnapshot[currentEpoch()];
        for (uint256 i = 0; i < nextValidatorIDs.length; i++) {
            uint256 receivedStake = getValidator[nextValidatorIDs[i]].receivedStake;
            snapshot.receivedStakes[nextValidatorIDs[i]] = receivedStake;
            snapshot.totalStake = snapshot.totalStake.add(receivedStake);
        }
        snapshot.validatorIDs = nextValidatorIDs;
    }

    function _sealEpochValidators(address[] calldata nextValidatorIDs) external {
        require(msg.sender == address(0), "not callable");
        __sealEpochValidators(nextValidatorIDs);
    }

    function _now() internal view returns (uint256) {
        return block.timestamp;
    }
}
