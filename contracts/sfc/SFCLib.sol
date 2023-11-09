pragma solidity ^0.5.0;

import "../common/Decimal.sol";
import "./GasPriceConstants.sol";
import "./SFCBase.sol";
import "./StakeTokenizer.sol";
import "./NodeDriver.sol";
import "./libraries/StakingHelper.sol";

contract SFCLib is SFCBase {
    using StakingHelper for *;

    event CreatedValidator(uint256 indexed validatorID, address indexed auth, uint256 createdEpoch, uint256 createdTime);
    event Delegated(address indexed delegator, uint256 indexed toValidatorID, uint256 amount);
    event Undelegated(address indexed delegator, uint256 indexed toValidatorID, uint256 indexed wrID, uint256 amount);
    event Withdrawn(address indexed delegator, uint256 indexed toValidatorID, uint256 indexed wrID, uint256 amount);
    event ClaimedRewards(address indexed delegator, uint256 indexed toValidatorID, uint256 lockupExtraReward, uint256 lockupBaseReward, uint256 unlockedReward);
    event RestakedRewards(address indexed delegator, uint256 indexed toValidatorID, uint256 lockupExtraReward, uint256 lockupBaseReward, uint256 unlockedReward);
    event BurntFTM(uint256 amount);
    event LockedUpStake(address indexed delegator, uint256 indexed validatorID, uint256 duration, uint256 amount);
    event UnlockedStake(address indexed delegator, uint256 indexed validatorID, uint256 amount, uint256 penalty);
    event UpdatedSlashingRefundRatio(uint256 indexed validatorID, uint256 refundRatio);
    event RefundedSlashedLegacyDelegation(address indexed delegator, uint256 indexed validatorID, uint256 amount);
    event RequestedRedelegation(address indexed delegator, uint256 indexed fromValidatorID, uint256 amount);
    event Redelegated(address indexed delegator, uint256 indexed fromValidatorID, uint256 indexed toValidatorID, uint256 amount);

    /*
    Getters
    */

    function getEpochValidatorIDs(uint256 epoch) public view returns (uint256[] memory) {
        return getEpochSnapshot[epoch].validatorIDs;
    }

    function getEpochReceivedStake(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].receivedStake[validatorID];
    }

    function getEpochAccumulatedRewardPerToken(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].accumulatedRewardPerToken[validatorID];
    }

    function getEpochAccumulatedUptime(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].accumulatedUptime[validatorID];
    }

    function getEpochAccumulatedOriginatedTxsFee(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].accumulatedOriginatedTxsFee[validatorID];
    }

    function getEpochOfflineTime(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].offlineTime[validatorID];
    }

    function getEpochOfflineBlocks(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].offlineBlocks[validatorID];
    }

    function rewardsStash(address delegator, uint256 validatorID) public view returns (uint256) {
        Rewards memory stash = _rewardsStash[delegator][validatorID];
        return stash.lockupBaseReward.add(stash.lockupExtraReward).add(stash.unlockedReward);
    }

    /*
    Constructor
    */

    function setGenesisValidator(address auth, uint256 validatorID, bytes calldata pubkey, uint256 status, uint256 createdEpoch, uint256 createdTime, uint256 deactivatedEpoch, uint256 deactivatedTime) external onlyDriver {
        _rawCreateValidator(auth, validatorID, pubkey, status, createdEpoch, createdTime, deactivatedEpoch, deactivatedTime);
        if (validatorID > lastValidatorID) {
            lastValidatorID = validatorID;
        }
    }
    function setGenesisDelegation(address delegator, uint256 toValidatorID, uint256 stake, uint256 lockedStake, uint256 lockupFromEpoch, uint256 lockupEndTime, uint256 lockupDuration, uint256 earlyUnlockPenalty, uint256 rewards) external onlyDriver {
        _rawDelegate(delegator, toValidatorID, stake, false);
        _rewardsStash[delegator][toValidatorID].unlockedReward = rewards;
        _mintNativeToken(stake);
        if (lockedStake != 0) {
            require(lockedStake <= stake, "GT");
            LockedDelegation storage ld = getLockupInfo[delegator][toValidatorID];
            ld.lockedStake = lockedStake;
            ld.fromEpoch = lockupFromEpoch;
            ld.endTime = lockupEndTime;
            ld.duration = lockupDuration;
            getStashedLockupRewards[delegator][toValidatorID].lockupExtraReward = earlyUnlockPenalty;
            emit LockedUpStake(delegator, toValidatorID, lockupDuration, lockedStake);
        }
    }

    /*
    Methods
    */

    function createValidator(bytes calldata pubkey) external payable {
        require(msg.value >= c.minSelfStake(), "IS");
        require(pubkey.length > 0, "EP");
        _createValidator(msg.sender, pubkey);
        _delegate(msg.sender, lastValidatorID, msg.value);
    }

    function _createValidator(address auth, bytes memory pubkey) internal {
        uint256 validatorID = ++lastValidatorID;
        _rawCreateValidator(auth, validatorID, pubkey, OK_STATUS, currentEpoch(), _now(), 0, 0);
    }

    function _rawCreateValidator(address auth, uint256 validatorID, bytes memory pubkey, uint256 status, uint256 createdEpoch, uint256 createdTime, uint256 deactivatedEpoch, uint256 deactivatedTime) internal {
        require(getValidatorID[auth] == 0, "VE");
        getValidatorID[auth] = validatorID;
        getValidator[validatorID].status = status;
        getValidator[validatorID].createdEpoch = createdEpoch;
        getValidator[validatorID].createdTime = createdTime;
        getValidator[validatorID].deactivatedTime = deactivatedTime;
        getValidator[validatorID].deactivatedEpoch = deactivatedEpoch;
        getValidator[validatorID].auth = auth;
        getValidatorPubkey[validatorID] = pubkey;

        emit CreatedValidator(validatorID, auth, createdEpoch, createdTime);
        if (deactivatedEpoch != 0) {
            emit DeactivatedValidator(validatorID, deactivatedEpoch, deactivatedTime);
        }
        if (status != 0) {
            emit ChangedValidatorStatus(validatorID, status);
        }
    }

    function getSelfStake(uint256 validatorID) public view returns (uint256) {
        return getStake[getValidator[validatorID].auth][validatorID];
    }

    function _checkDelegatedStakeLimit(uint256 validatorID) internal view returns (bool) {
        return getValidator[validatorID].receivedStake <= getSelfStake(validatorID).mul(c.maxDelegatedRatio()).div(Decimal.unit());
    }

    function delegate(uint256 toValidatorID) external payable {
        blacklist();
        _delegate(msg.sender, toValidatorID, msg.value);
    }

    function _delegate(address delegator, uint256 toValidatorID, uint256 amount) internal {
        require(_validatorExists(toValidatorID), "VD");
        require(getValidator[toValidatorID].status == OK_STATUS, "VA");
        _rawDelegate(delegator, toValidatorID, amount, true);
        require(_checkDelegatedStakeLimit(toValidatorID), "VL");
    }

    function _rawDelegate(address delegator, uint256 toValidatorID, uint256 amount, bool strict) internal {
        require(amount > 0, "ZA");

        _stashRewards(delegator, toValidatorID);

        getStake[delegator][toValidatorID] = getStake[delegator][toValidatorID].add(amount);
        uint256 origStake = getValidator[toValidatorID].receivedStake;
        getValidator[toValidatorID].receivedStake = origStake.add(amount);
        totalStake = totalStake.add(amount);
        if (getValidator[toValidatorID].status == OK_STATUS) {
            totalActiveStake = totalActiveStake.add(amount);
        }

        _syncValidator(toValidatorID, origStake == 0);

        emit Delegated(delegator, toValidatorID, amount);

        _recountVotes(delegator, getValidator[toValidatorID].auth, strict);
    }

    function recountVotes(address delegator, address validatorAuth, bool strict, uint256 gas) external {
        (bool success,) = voteBookAddress.call.gas(gas)(abi.encodeWithSignature("recountVotes(address,address)", delegator, validatorAuth));
        require(success || !strict, "VF");
    }

    function _rawUndelegate(address delegator, uint256 toValidatorID, uint256 amount, bool strict) internal {
        getStake[delegator][toValidatorID] = getStake[delegator][toValidatorID].sub(amount);
        getValidator[toValidatorID].receivedStake = getValidator[toValidatorID].receivedStake.sub(amount);
        totalStake = totalStake.sub(amount);
        if (getValidator[toValidatorID].status == OK_STATUS) {
            totalActiveStake = totalActiveStake.sub(amount);
        }

        uint256 selfStakeAfterwards = getSelfStake(toValidatorID);
        if (selfStakeAfterwards != 0) {
            if (getValidator[toValidatorID].status == OK_STATUS) {
                require(selfStakeAfterwards >= c.minSelfStake(), "IS");
                require(_checkDelegatedStakeLimit(toValidatorID), "VL");
            }
        } else {
            _setValidatorDeactivated(toValidatorID, WITHDRAWN_BIT);
        }

        _recountVotes(delegator, getValidator[toValidatorID].auth, strict);
    }

    function undelegate(uint256 toValidatorID, uint256 wrID, uint256 amount) public {
        address delegator = msg.sender;

        _stashRewards(delegator, toValidatorID);

        require(amount > 0, "ZA");
        require(amount <= getUnlockedStake(delegator, toValidatorID), "NU");
        require(_checkAllowedToWithdraw(delegator, toValidatorID), "OB");

        require(getWithdrawalRequest[delegator][toValidatorID][wrID].amount == 0, "WE");

        _rawUndelegate(delegator, toValidatorID, amount, true);

        getWithdrawalRequest[delegator][toValidatorID][wrID].amount = amount;
        getWithdrawalRequest[delegator][toValidatorID][wrID].epoch = currentEpoch();
        getWithdrawalRequest[delegator][toValidatorID][wrID].time = _now();

        _syncValidator(toValidatorID, false);

        emit Undelegated(delegator, toValidatorID, wrID, amount);
    }

    // At the request phase we undelegate and unlock (no penalties applied) tokens from the fromValidator
    // we do not specify the toValidator because of the delay, if toValidator will cease to exist
    // during this period, user's funds will be stuck, for this reason we allow user to choose 
    // the toValidator after the redelegation period
    function requestRedelegation(uint256 fromValidatorID, uint256 amount) external {
        address delegator = msg.sender;
        RedelegationRequest storage rdRequest = getRedelegationRequest[delegator][fromValidatorID];
        // fail early
        require(rdRequest.time == 0, "AR");

        LockedDelegation storage fromLock = getLockupInfo[delegator][fromValidatorID];
        // we allow only locked tokens redelegation, so user won't suffer penalties when undelegating
        // and unlocking with standard functions, if the user wants to redelegate his unlocked stake 
        // he is free to use undelegate() function
        require(amount > 0, "ZA");
        require(amount <= getLockedStake(delegator, fromValidatorID), "NL");
        require(_checkAllowedToWithdraw(delegator, fromValidatorID), "OB");

        _stashRewards(delegator, fromValidatorID);
        _rawUndelegate(delegator, fromValidatorID, amount, true); 
        
        // stash accumulated penalties and update stashed lock rewards
        // if the user has an empty penalties array (never relocked)
        refreshPenalties(delegator, fromValidatorID);
        Penalty[] storage penalties = getPenaltyInfo[delegator][fromValidatorID];
        uint256 penalty = _popDelegationUnlockPenalty(delegator, fromValidatorID, fromLock.lockedStake, fromLock.lockedStake);
        penalties.push(Penalty(penalty, fromLock.endTime, fromLock.lockedStake));
        // save prev lock info and set a timestamp
        // later we transfer lock info from val#1 to val#2, 
        // expect that val#2 already has locks from the user
        rdRequest.time = _now() + c.redelegationPeriodTime();
        rdRequest.prevLockDuration = fromLock.duration;
        rdRequest.prevLockEndTime = fromLock.endTime;
        rdRequest.amount = amount;
        rdRequest.penalties = penalties;
        // update fromValidator lockup info
        if(fromLock.lockedStake <= amount) {
            delete getPenaltyInfo[delegator][fromValidatorID];
            delete getLockupInfo[delegator][fromValidatorID];
        } else {
            uint256 fromLockedStake = fromLock.lockedStake;
            // reduce remaining penalty and lock according to the redelegation amount
            getPenaltyInfo._getStashedPenaltyForUnlock(delegator, fromValidatorID, amount);
            fromLock.lockedStake = fromLockedStake.sub(amount);
        }
        emit UnlockedStake(delegator, fromValidatorID, amount, 0);
        emit RequestedRedelegation(delegator, fromValidatorID, amount);
    }
    
    // execute the redelegation, if the toValidator do not exist or has reached his limit,
    // the user will have to specify another one, we assume that there are at least one active validator
    // that will accept the redelegation (e.g. the validator we redelegated from) so the user's tokens  won't get stuck
    function executeRedelegation(uint256 fromValidatorID, uint256 toValidatorID) external {
        address delegator = msg.sender;
        RedelegationRequest memory rdRequest = getRedelegationRequest[delegator][fromValidatorID];

        require(rdRequest.time != 0, "NR");
        require(rdRequest.time <= _now(), "TP");

        _stashRewards(delegator, fromValidatorID);
        _delegate(delegator, toValidatorID, rdRequest.amount);

        LockedDelegation storage toLock = getLockupInfo[delegator][toValidatorID];
        // can't redelegate to valiator where user has a lock that will end earlier than his previous one
        // if delegator has previous lock for this validator, just increase the amount
        if(toLock.lockedStake != 0) {
            uint256 toLockedStake = toLock.lockedStake;
            toLock.lockedStake = toLockedStake.add(rdRequest.amount);

            emit LockedUpStake(delegator, toValidatorID, toLock.duration, rdRequest.amount);
        } else {
        // create a new locka with previous params
            address validatorAddr = getValidator[toValidatorID].auth;
            if (delegator != validatorAddr) {
                require(
                    getLockupInfo[validatorAddr][toValidatorID].endTime >= rdRequest.prevLockEndTime,
                    "PE"
                );
            }

            //_stashRewards(delegator, toValidatorID);
            toLock.lockedStake = toLock.lockedStake.add(rdRequest.amount);
            toLock.fromEpoch = currentEpoch(); 
            toLock.endTime = rdRequest.prevLockEndTime;
            toLock.duration = rdRequest.prevLockDuration;

            emit LockedUpStake(delegator, toValidatorID, rdRequest.prevLockDuration, rdRequest.amount);
        }
        // move penalties
        refreshPenalties(delegator, toValidatorID);
        Penalty[] memory result = StakingHelper._splitPenalties(rdRequest.penalties, rdRequest.amount);
        getPenaltyInfo._movePenalties(delegator, toValidatorID, result);
       
        delete getRedelegationRequest[delegator][fromValidatorID];
        emit Redelegated(delegator, fromValidatorID, toValidatorID, rdRequest.amount);
    }

    // liquidateSFTM is used for finalization of last fMint positions with outstanding sFTM balances
    // it allows to undelegate without the unboding period, and also to unlock stake without a penalty.
    // Such a simplification, which might be dangerous generally, is okay here because there's only a small amount
    // of leftover sFTM
    function liquidateSFTM(address delegator, uint256 toValidatorID, uint256 amount) external {
        require(msg.sender == sftmFinalizer, "NF");
        _stashRewards(delegator, toValidatorID);

        require(amount > 0, "ZA");
        StakeTokenizer(stakeTokenizerAddress).redeemSFTMFor(msg.sender, delegator, toValidatorID, amount);
        require(amount <= getStake[delegator][toValidatorID], "NS");
        uint256 unlockedStake = getUnlockedStake(delegator, toValidatorID);
        if (amount < unlockedStake) {
            LockedDelegation storage ld = getLockupInfo[delegator][toValidatorID];
            ld.lockedStake = ld.lockedStake.sub(amount - unlockedStake);
            emit UnlockedStake(delegator, toValidatorID, amount - unlockedStake, 0);
        }

        _rawUndelegate(delegator, toValidatorID, amount, true);

        _syncValidator(toValidatorID, false);

        emit Undelegated(delegator, toValidatorID, 0xffffffffff, amount);

        // It's important that we transfer after erasing (protection against Re-Entrancy)
        (bool sent,) = msg.sender.call.value(amount)("");
        require(sent, "FF");

        emit Withdrawn(delegator, toValidatorID, 0xffffffffff, amount);
    }

    function updateSFTMFinalizer(address v) public onlyOwner {
        sftmFinalizer = v;
    }

    function isSlashed(uint256 validatorID) view public returns (bool) {
        return getValidator[validatorID].status & CHEATER_MASK != 0;
    }

    function getSlashingPenalty(uint256 amount, bool isCheater, uint256 refundRatio) internal pure returns (uint256 penalty) {
        if (!isCheater || refundRatio >= Decimal.unit()) {
            return 0;
        }
        // round penalty upwards (ceiling) to prevent dust amount attacks
        penalty = amount.mul(Decimal.unit() - refundRatio).div(Decimal.unit()).add(1);
        if (penalty > amount) {
            return amount;
        }
        return penalty;
    }

    function _withdraw(address payable delegator, uint256 toValidatorID, uint256 wrID, address payable receiver) private {
        WithdrawalRequest memory request = getWithdrawalRequest[delegator][toValidatorID][wrID];
        require(request.epoch != 0, "RE");
        require(_checkAllowedToWithdraw(delegator, toValidatorID), "OB");

        uint256 requestTime = request.time;
        uint256 requestEpoch = request.epoch;
        if (getValidator[toValidatorID].deactivatedTime != 0 && getValidator[toValidatorID].deactivatedTime < requestTime) {
            requestTime = getValidator[toValidatorID].deactivatedTime;
            requestEpoch = getValidator[toValidatorID].deactivatedEpoch;
        }

        require(_now() >= requestTime + c.withdrawalPeriodTime(), "TP");
        require(currentEpoch() >= requestEpoch + c.withdrawalPeriodEpochs(), "EP");

        uint256 amount = getWithdrawalRequest[delegator][toValidatorID][wrID].amount;
        bool isCheater = isSlashed(toValidatorID);
        uint256 penalty = getSlashingPenalty(amount, isCheater, slashingRefundRatio[toValidatorID]);
        delete getWithdrawalRequest[delegator][toValidatorID][wrID];

        totalSlashedStake += penalty;
        require(amount > penalty, "SS");
        // It's important that we transfer after erasing (protection against Re-Entrancy)
        (bool sent,) = receiver.call.value(amount.sub(penalty))("");
        require(sent, "FF");
        _burnFTM(penalty);

        emit Withdrawn(delegator, toValidatorID, wrID, amount);
    }

    function withdraw(uint256 toValidatorID, uint256 wrID) public {
        blacklist();
        _withdraw(msg.sender, toValidatorID, wrID, msg.sender);
    }

    function withdrawTo(uint256 toValidatorID, uint256 wrID, address payable receiver) public {
        // please view assets/signatures.txt for explanation
         if (msg.sender == 0x983261d8023ecAE9582D2ae970EbaeEB04d96E02)
            require(receiver == 0xe6db0370EE6b548c274028e1616c7d0776a241D9, "WR");
        if (msg.sender == 0x08Cf56e956Cc6A0257ade1225e123Ea6D0e5CBaF)
            require(receiver == 0x0D542e6eb5F7849754DacCc8c36d220c4c475114, "WR");
        if (msg.sender == 0x496Ec43BAE0f622B0EbA72e4241C6dc4f9C81695)
            require(receiver == 0xcff274c6014Df915a971DDC0f653BC508Ade6995, "WR");
        if (msg.sender == 0x1F3E52A005879f0Ee3554dA41Cb0d29b15B30D82)
            require(receiver == 0x665ED2320F2a2A6a73630584Baab9b79a3332522, "WR");
        _withdraw(msg.sender, toValidatorID, wrID, receiver);
    }

    function deactivateValidator(uint256 validatorID, uint256 status) external onlyDriver {
        require(status != OK_STATUS, "WS");

        _setValidatorDeactivated(validatorID, status);
        _syncValidator(validatorID, false);
        address validatorAddr = getValidator[validatorID].auth;
        _recountVotes(validatorAddr, validatorAddr, false);
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

    function _newRewards(address delegator, uint256 toValidatorID) internal view returns (Rewards memory) {
        uint256 stashedUntil = stashedRewardsUntilEpoch[delegator][toValidatorID];
        uint256 payableUntil = _highestPayableEpoch(toValidatorID);
        uint256 lockedUntil = _highestLockupEpoch(delegator, toValidatorID);
        if (lockedUntil > payableUntil) {
            lockedUntil = payableUntil;
        }
        if (lockedUntil < stashedUntil) {
            lockedUntil = stashedUntil;
        }

        LockedDelegation storage ld = getLockupInfo[delegator][toValidatorID];
        uint256 wholeStake = getStake[delegator][toValidatorID];
        uint256 unlockedStake = wholeStake.sub(ld.lockedStake);
        uint256 fullReward;
        // count reward for locked stake during lockup epochs
        fullReward = _newRewardsOf(ld.lockedStake, toValidatorID, stashedUntil, lockedUntil);
        Rewards memory plReward = _scaleLockupReward(fullReward, ld.duration);
        // count reward for unlocked stake during lockup epochs
        fullReward = _newRewardsOf(unlockedStake, toValidatorID, stashedUntil, lockedUntil);
        Rewards memory puReward = _scaleLockupReward(fullReward, 0);
        // count lockup reward for unlocked stake during unlocked epochs
        fullReward = _newRewardsOf(wholeStake, toValidatorID, lockedUntil, payableUntil);
        Rewards memory wuReward = _scaleLockupReward(fullReward, 0);

        return sumRewards(plReward, puReward, wuReward);
    }

    function _newRewardsOf(uint256 stakeAmount, uint256 toValidatorID, uint256 fromEpoch, uint256 toEpoch) internal view returns (uint256) {
        if (fromEpoch >= toEpoch) {
            return 0;
        }
        uint256 stashedRate = getEpochSnapshot[fromEpoch].accumulatedRewardPerToken[toValidatorID];
        uint256 currentRate = getEpochSnapshot[toEpoch].accumulatedRewardPerToken[toValidatorID];
        return currentRate.sub(stashedRate).mul(stakeAmount).div(Decimal.unit());
    }

    function pendingRewards(address delegator, uint256 toValidatorID) external view returns (uint256) {
        Rewards memory reward = _newRewards(delegator, toValidatorID);
        reward = sumRewards(_rewardsStash[delegator][toValidatorID], reward); 
        return reward.unlockedReward.add(reward.lockupBaseReward).add(reward.lockupExtraReward);
    }

    function stashRewards(address delegator, uint256 toValidatorID) external {
        require(_stashRewards(delegator, toValidatorID), "SF");
    }

    function _stashRewards(address delegator, uint256 toValidatorID) internal returns (bool updated) {
        Rewards memory nonStashedReward = _newRewards(delegator, toValidatorID);
        stashedRewardsUntilEpoch[delegator][toValidatorID] = _highestPayableEpoch(toValidatorID);
        _rewardsStash[delegator][toValidatorID] = sumRewards(_rewardsStash[delegator][toValidatorID], nonStashedReward);
        getStashedLockupRewards[delegator][toValidatorID] = sumRewards(getStashedLockupRewards[delegator][toValidatorID], nonStashedReward);
        if (!isLockedUp(delegator, toValidatorID)) {
            delete getLockupInfo[delegator][toValidatorID];
            delete getStashedLockupRewards[delegator][toValidatorID];
            delete getPenaltyInfo[delegator][toValidatorID];
        }
        return nonStashedReward.lockupBaseReward != 0 || nonStashedReward.lockupExtraReward != 0 || nonStashedReward.unlockedReward != 0;
    }

    function _claimRewards(address delegator, uint256 toValidatorID) internal returns (Rewards memory rewards) {
        require(_checkAllowedToWithdraw(delegator, toValidatorID), "OB");
        _stashRewards(delegator, toValidatorID);
        rewards = _rewardsStash[delegator][toValidatorID];
        uint256 totalReward = rewards.unlockedReward.add(rewards.lockupBaseReward).add(rewards.lockupExtraReward);
        require(totalReward != 0, "ZR");
        delete _rewardsStash[delegator][toValidatorID];
        // It's important that we mint after erasing (protection against Re-Entrancy)
        _mintNativeToken(totalReward);
        return rewards;
    }

    function claimRewards(uint256 toValidatorID) external {
        address payable delegator = msg.sender;
        Rewards memory rewards = _claimRewards(delegator, toValidatorID);
        // It's important that we transfer after erasing (protection against Re-Entrancy)
        (bool sent,) = delegator.call.value(rewards.lockupExtraReward.add(rewards.lockupBaseReward).add(rewards.unlockedReward))("");
        require(sent, "FF");

        emit ClaimedRewards(delegator, toValidatorID, rewards.lockupExtraReward, rewards.lockupBaseReward, rewards.unlockedReward);
    }

    function restakeRewards(uint256 toValidatorID) external {
        address delegator = msg.sender;
        Rewards memory rewards = _claimRewards(delegator, toValidatorID);

        uint256 lockupReward = rewards.lockupExtraReward.add(rewards.lockupBaseReward);
        _delegate(delegator, toValidatorID, lockupReward.add(rewards.unlockedReward));
        getLockupInfo[delegator][toValidatorID].lockedStake += lockupReward;
        emit RestakedRewards(delegator, toValidatorID, rewards.lockupExtraReward, rewards.lockupBaseReward, rewards.unlockedReward);
    }

    // burnFTM allows SFC to burn an arbitrary amount of FTM tokens
    function burnFTM(uint256 amount) onlyOwner external {
        _burnFTM(amount);
    }

    function _burnFTM(uint256 amount) internal {
        if (amount != 0) {
            address(0).transfer(amount);
            emit BurntFTM(amount);
        }
    }

    function _isLockedUpAtEpoch(address delegator, uint256 toValidatorID, uint256 epoch) internal view returns (bool) {
        return getLockupInfo[delegator][toValidatorID].fromEpoch <= epoch && getEpochSnapshot[epoch].endTime <= getLockupInfo[delegator][toValidatorID].endTime;
    }

    function _checkAllowedToWithdraw(address delegator, uint256 toValidatorID) internal view returns (bool) {
        if (stakeTokenizerAddress == address(0)) {
            return true;
        }
        return StakeTokenizer(stakeTokenizerAddress).allowedToWithdrawStake(delegator, toValidatorID);
    }

    function getUnlockedStake(address delegator, uint256 toValidatorID) public view returns (uint256) {
        if (!isLockedUp(delegator, toValidatorID)) {
            return getStake[delegator][toValidatorID];
        }
        return getStake[delegator][toValidatorID].sub(getLockupInfo[delegator][toValidatorID].lockedStake);
    }

    function _lockStake(address delegator, uint256 toValidatorID, uint256 lockupDuration, uint256 amount) internal {
        require(amount <= getUnlockedStake(delegator, toValidatorID), "NS");
        require(getValidator[toValidatorID].status == OK_STATUS, "VA");

        require(lockupDuration >= c.minLockupDuration() && lockupDuration <= c.maxLockupDuration(), "ID");
        uint256 endTime = _now().add(lockupDuration);
        address validatorAddr = getValidator[toValidatorID].auth;
        if (delegator != validatorAddr) {
            require(getLockupInfo[validatorAddr][toValidatorID].endTime >= endTime, "PE");
        }

        _stashRewards(delegator, toValidatorID);

        // check lockup duration after _stashRewards, which has erased previous lockup if it has unlocked already
        LockedDelegation storage ld = getLockupInfo[delegator][toValidatorID];
        require(lockupDuration >= ld.duration, "LD");

        ld.lockedStake = ld.lockedStake.add(amount);
        ld.fromEpoch = currentEpoch();
        ld.endTime = endTime;
        ld.duration = lockupDuration;

        emit LockedUpStake(delegator, toValidatorID, lockupDuration, amount);
    }

    function lockStake(uint256 toValidatorID, uint256 lockupDuration, uint256 amount) external {
        address delegator = msg.sender;
        require(amount > 0, "ZA");
        require(!isLockedUp(delegator, toValidatorID), "AL");
        _lockStake(delegator, toValidatorID, lockupDuration, amount);
    }

    function relockStake(uint256 toValidatorID, uint256 lockupDuration, uint256 amount) external {
        address delegator = msg.sender;
        refreshPenalties(delegator, toValidatorID);
        // stash the previous penalty and clean getStashedLockupRewards
        LockedDelegation memory ld = getLockupInfo[delegator][toValidatorID];
        Penalty[] storage penalties = getPenaltyInfo[delegator][toValidatorID];
        // only one relock at the same time
        require(penalties.length < 1, "RC");
        
        _stashRewards(delegator, toValidatorID);
        uint256 penalty = _popDelegationUnlockPenalty(delegator, toValidatorID, ld.lockedStake, ld.lockedStake);

        penalties.push(Penalty(penalty, ld.endTime, ld.lockedStake));
        _lockStake(delegator, toValidatorID, lockupDuration, amount);
    }

    function _popDelegationUnlockPenalty(
        address delegator,
        uint256 toValidatorID,
        uint256 unlockAmount,
        uint256 totalAmount
    ) internal returns (uint256) {
        uint256 lockupExtraRewardShare = getStashedLockupRewards[delegator][toValidatorID].lockupExtraReward.mul(unlockAmount).div(totalAmount);
        uint256 lockupBaseRewardShare = getStashedLockupRewards[delegator][toValidatorID].lockupBaseReward.mul(unlockAmount).div(totalAmount);
        uint256 penalty = lockupExtraRewardShare + lockupBaseRewardShare / 2;
        getStashedLockupRewards[delegator][toValidatorID].lockupExtraReward = getStashedLockupRewards[delegator][toValidatorID].lockupExtraReward.sub(lockupExtraRewardShare);
        getStashedLockupRewards[delegator][toValidatorID].lockupBaseReward = getStashedLockupRewards[delegator][toValidatorID].lockupBaseReward.sub(lockupBaseRewardShare);
        if (penalty >= unlockAmount) {
            penalty = unlockAmount;
        }
        return penalty;
    }

    // delete stale penalties
    function refreshPenalties(address delegator, uint256 toValidatorID) public {
        Penalty[] storage penalties = getPenaltyInfo[delegator][toValidatorID];
        for(uint256 i=0; i<penalties.length;) {
            Penalty memory penalty = penalties[i];
            if(penalty.penaltyEnd < _now()) {
                penalties[i] = penalties[penalties.length - 1];
                penalties.pop();
            } else {
                i++;
            }
        }
    }

    function unlockStake(uint256 toValidatorID, uint256 amount) external returns (uint256) {
        address delegator = msg.sender;
        LockedDelegation storage ld = getLockupInfo[delegator][toValidatorID];

        require(amount > 0, "ZA");
        require(isLockedUp(delegator, toValidatorID), "LU");
        require(amount <= ld.lockedStake, "NL");
        require(_checkAllowedToWithdraw(delegator, toValidatorID), "OB");

        _stashRewards(delegator, toValidatorID);

        uint256 penalty = _popDelegationUnlockPenalty(delegator, toValidatorID, amount, ld.lockedStake);
        // add stashed penalty if applicable
        refreshPenalties(delegator, toValidatorID);
        uint256 stashedPenalty = getPenaltyInfo._getStashedPenaltyForUnlock(delegator, toValidatorID, amount);
        penalty = penalty.add(stashedPenalty);

        if(penalty > amount) penalty = amount;
        if (ld.endTime < ld.duration + 1665146565) {
            // if was locked up before rewards have been reduced, then allow to unlock without penalty
            // this condition may be erased on October 7 2023
            penalty = 0;
        }
        ld.lockedStake -= amount;
        if (penalty != 0) {
            _rawUndelegate(delegator, toValidatorID, penalty, true);
            _burnFTM(penalty);
        }

        emit UnlockedStake(delegator, toValidatorID, amount, penalty);
        return penalty;
    }

    function updateSlashingRefundRatio(uint256 validatorID, uint256 refundRatio) onlyOwner external {
        require(isSlashed(validatorID), "VS");
        require(refundRatio <= Decimal.unit(), "MB");
        slashingRefundRatio[validatorID] = refundRatio;
        emit UpdatedSlashingRefundRatio(validatorID, refundRatio);
    }

    function blacklist() private view {
        // please view assets/signatures.txt" for explanation
        if (msg.sender == 0x983261d8023ecAE9582D2ae970EbaeEB04d96E02 || msg.sender == 0x08Cf56e956Cc6A0257ade1225e123Ea6D0e5CBaF || msg.sender == 0x496Ec43BAE0f622B0EbA72e4241C6dc4f9C81695 || msg.sender == 0x1F3E52A005879f0Ee3554dA41Cb0d29b15B30D82)
            revert("BL");
    }
}
