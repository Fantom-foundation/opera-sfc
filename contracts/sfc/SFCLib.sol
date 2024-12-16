pragma solidity ^0.5.0;

import "../common/Decimal.sol";
import "./GasPriceConstants.sol";
import "./SFCBase.sol";
import "./StakeTokenizer.sol";
import "./NodeDriver.sol";

contract SFCLib is SFCBase {
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
            require(lockedStake <= stake, "locked stake is greater than the whole stake");
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
        require(msg.value >= c.minSelfStake(), "insufficient self-stake");
        require(pubkey.length == 66 && pubkey[0] == 0xc0, "malformed pubkey");
        require(pubkeyHashToValidatorID[keccak256(pubkey)] == 0, "already used");
        _createValidator(msg.sender, pubkey);
        _delegate(msg.sender, lastValidatorID, msg.value);
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
        pubkeyHashToValidatorID[keccak256(pubkey)] = validatorID;

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
        _delegate(_addrToValidator(msg.sender, toValidatorID), toValidatorID, msg.value);
    }

    function _delegate(address delegator, uint256 toValidatorID, uint256 amount) internal {
        require(_validatorExists(toValidatorID), "validator doesn't exist");
        require(getValidator[toValidatorID].status == OK_STATUS, "validator isn't active");
        _rawDelegate(delegator, toValidatorID, amount, true);
        require(_checkDelegatedStakeLimit(toValidatorID), "validator's delegations limit is exceeded");
    }

    function _rawDelegate(address delegator, uint256 toValidatorID, uint256 amount, bool strict) internal {
        // Delegations are disabled to protect current chain while migrating to the new sonic chain
        revert("delegation disabled");

        require(amount > 0, "zero amount");

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
        require(success || !strict, "gov votes recounting failed");
    }

    function _rawUndelegate(address delegator, uint256 toValidatorID, uint256 amount, bool strict, bool forceful, bool checkDelegatedStake) internal {
        getStake[delegator][toValidatorID] -= amount;
        getValidator[toValidatorID].receivedStake = getValidator[toValidatorID].receivedStake.sub(amount);
        totalStake = totalStake.sub(amount);
        if (getValidator[toValidatorID].status == OK_STATUS) {
            totalActiveStake = totalActiveStake.sub(amount);
        }

        uint256 selfStakeAfterwards = getSelfStake(toValidatorID);
        if (selfStakeAfterwards != 0 && getValidator[toValidatorID].status == OK_STATUS) {
            if (!(selfStakeAfterwards >= c.minSelfStake())) {
                if (forceful) {
                    revert("insufficient self-stake");
                } else {
                    _setValidatorDeactivated(toValidatorID, WITHDRAWN_BIT);
                }
            }
            require(!checkDelegatedStake || _checkDelegatedStakeLimit(toValidatorID), "validator's delegations limit is exceeded");
        } else {
            _setValidatorDeactivated(toValidatorID, WITHDRAWN_BIT);
        }

        _recountVotes(delegator, getValidator[toValidatorID].auth, strict);
    }

    function undelegate(uint256 toValidatorID, uint256 wrID, uint256 amount) public {
        address delegator = _addrToValidator(msg.sender, toValidatorID);

        _stashRewards(delegator, toValidatorID);

        require(amount > 0, "zero amount");
        require(amount <= getUnlockedStake(delegator, toValidatorID), "not enough unlocked stake");
        require(_checkAllowedToWithdraw(delegator, toValidatorID), "outstanding sFTM balance");

        require(getWithdrawalRequest[delegator][toValidatorID][wrID].amount == 0, "wrID already exists");

        _rawUndelegate(delegator, toValidatorID, amount, true, false, true);

        getWithdrawalRequest[delegator][toValidatorID][wrID].amount = amount;
        getWithdrawalRequest[delegator][toValidatorID][wrID].epoch = currentEpoch();
        getWithdrawalRequest[delegator][toValidatorID][wrID].time = _now();

        _syncValidator(toValidatorID, false);

        emit Undelegated(delegator, toValidatorID, wrID, amount);
    }

    // liquidateSFTM is used for finalization of last fMint positions with outstanding sFTM balances
    // it allows to undelegate without the unboding period, and also to unlock stake without a penalty.
    // Such a simplification, which might be dangerous generally, is okay here because there's only a small amount
    // of leftover sFTM
    function liquidateSFTM(address delegator, uint256 toValidatorID, uint256 amount) external {
        require(msg.sender == sftmFinalizer, "not sFTM finalizer");
        _stashRewards(delegator, toValidatorID);

        require(amount > 0, "zero amount");
        StakeTokenizer(stakeTokenizerAddress).redeemSFTMFor(msg.sender, delegator, toValidatorID, amount);
        require(amount <= getStake[delegator][toValidatorID], "not enough stake");
        uint256 unlockedStake = getUnlockedStake(delegator, toValidatorID);
        if (amount > unlockedStake) {
            LockedDelegation storage ld = getLockupInfo[delegator][toValidatorID];
            ld.lockedStake = ld.lockedStake.sub(amount - unlockedStake);
            emit UnlockedStake(delegator, toValidatorID, amount - unlockedStake, 0);
        }

        _rawUndelegate(delegator, toValidatorID, amount, false, true, false);

        _syncValidator(toValidatorID, false);

        emit Undelegated(delegator, toValidatorID, 0xffffffffff, amount);

        // It's important that we transfer after erasing (protection against Re-Entrancy)
        (bool sent,) = msg.sender.call.value(amount)("");
        require(sent, "Failed to send FTM");

        emit Withdrawn(delegator, toValidatorID, 0xffffffffff, amount);
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
        require(request.epoch != 0, "request doesn't exist");
        require(_checkAllowedToWithdraw(delegator, toValidatorID), "outstanding sFTM balance");

        uint256 requestTime = request.time;
        uint256 requestEpoch = request.epoch;
        if (getValidator[toValidatorID].deactivatedTime != 0 && getValidator[toValidatorID].deactivatedTime < requestTime) {
            requestTime = getValidator[toValidatorID].deactivatedTime;
            requestEpoch = getValidator[toValidatorID].deactivatedEpoch;
        }

        require(_now() >= requestTime + c.withdrawalPeriodTime(), "not enough time passed");
        require(currentEpoch() >= requestEpoch + c.withdrawalPeriodEpochs(), "not enough epochs passed");

        uint256 amount = getWithdrawalRequest[delegator][toValidatorID][wrID].amount;
        bool isCheater = isSlashed(toValidatorID);
        uint256 penalty = getSlashingPenalty(amount, isCheater, slashingRefundRatio[toValidatorID]);
        delete getWithdrawalRequest[delegator][toValidatorID][wrID];

        totalSlashedStake += penalty;
        require(amount > penalty, "stake is fully slashed");
        // It's important that we transfer after erasing (protection against Re-Entrancy)
        (bool sent,) = receiver.call.value(amount.sub(penalty))("");
        require(sent, "Failed to send FTM");
        _burnFTM(penalty);

        emit Withdrawn(delegator, toValidatorID, wrID, amount);
    }

    function withdraw(uint256 toValidatorID, uint256 wrID) public {
        address payable sender = address(uint160(_addrToValidator(msg.sender, toValidatorID)));
        _withdraw(sender, toValidatorID, wrID, _receiverOf(sender));
    }

    function deactivateValidator(uint256 validatorID, uint256 status) external onlyDriver {
        require(status != OK_STATUS, "wrong status");

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

    function _pendingRewards(address delegator, uint256 toValidatorID) internal view returns (Rewards memory) {
        Rewards memory reward = _newRewards(delegator, toValidatorID);
        return sumRewards(_rewardsStash[delegator][toValidatorID], reward);
    }

    function pendingRewards(address delegator, uint256 toValidatorID) public view returns (uint256) {
        Rewards memory reward = _pendingRewards(delegator, toValidatorID);
        return reward.unlockedReward.add(reward.lockupBaseReward).add(reward.lockupExtraReward);
    }

    function stashRewards(address delegator, uint256 toValidatorID) external {
        require(_stashRewards(delegator, toValidatorID), "nothing to stash");
    }

    function _stashRewards(address delegator, uint256 toValidatorID) internal returns (bool updated) {
        Rewards memory nonStashedReward = _newRewards(delegator, toValidatorID);
        stashedRewardsUntilEpoch[delegator][toValidatorID] = _highestPayableEpoch(toValidatorID);
        _rewardsStash[delegator][toValidatorID] = sumRewards(_rewardsStash[delegator][toValidatorID], nonStashedReward);
        getStashedLockupRewards[delegator][toValidatorID] = sumRewards(getStashedLockupRewards[delegator][toValidatorID], nonStashedReward);
        if (!isLockedUp(delegator, toValidatorID)) {
            delete getLockupInfo[delegator][toValidatorID];
            delete getStashedLockupRewards[delegator][toValidatorID];
        }
        _truncateLegacyPenalty(delegator, toValidatorID);
        return nonStashedReward.lockupBaseReward != 0 || nonStashedReward.lockupExtraReward != 0 || nonStashedReward.unlockedReward != 0;
    }

    function _claimRewards(address delegator, uint256 toValidatorID) internal returns (Rewards memory rewards) {
        require(_checkAllowedToWithdraw(delegator, toValidatorID), "outstanding sFTM balance");
        _stashRewards(delegator, toValidatorID);
        rewards = _rewardsStash[delegator][toValidatorID];
        uint256 totalReward = rewards.unlockedReward.add(rewards.lockupBaseReward).add(rewards.lockupExtraReward);
        require(totalReward != 0, "zero rewards");
        delete _rewardsStash[delegator][toValidatorID];
        // It's important that we mint after erasing (protection against Re-Entrancy)
        _mintNativeToken(totalReward);
        return rewards;
    }

    function claimRewards(uint256 toValidatorID) public {
        address delegator = _addrToValidator(msg.sender, toValidatorID);
        Rewards memory rewards = _claimRewards(delegator, toValidatorID);
        // It's important that we transfer after erasing (protection against Re-Entrancy)
        (bool sent,) = _receiverOf(delegator).call.value(rewards.lockupExtraReward.add(rewards.lockupBaseReward).add(rewards.unlockedReward))("");
        require(sent, "Failed to send FTM");

        emit ClaimedRewards(delegator, toValidatorID, rewards.lockupExtraReward, rewards.lockupBaseReward, rewards.unlockedReward);
    }

    function restakeRewards(uint256 toValidatorID) public {
        address delegator = _addrToValidator(msg.sender, toValidatorID);
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

    function burnNativeTokens() external payable {
        require(msg.value > 0, "No amount sent");
        _burnFTM(msg.value);
    }

    function _burnFTM(uint256 amount) internal {
        if (amount != 0 && totalSupply >= amount) {
            totalSupply -= amount;
            address(0).transfer(amount);
            emit BurntFTM(amount);
        }
    }

    function epochEndTime(uint256 epoch) view internal returns (uint256) {
        return getEpochSnapshot[epoch].endTime;
    }

    function _isLockedUpAtEpoch(address delegator, uint256 toValidatorID, uint256 epoch) internal view returns (bool) {
        return getLockupInfo[delegator][toValidatorID].fromEpoch <= epoch && epochEndTime(epoch) <= getLockupInfo[delegator][toValidatorID].endTime;
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

    function _lockStake(address delegator, uint256 toValidatorID, uint256 lockupDuration, uint256 amount, bool relock) internal {
        // Locks are disabled due to chain migrating to the new sonic chain
        revert("stake lock disabled");

        require(!_redirected(delegator), "redirected");
        require(amount <= getUnlockedStake(delegator, toValidatorID), "not enough stake");
        require(getValidator[toValidatorID].status == OK_STATUS, "validator isn't active");

        require(lockupDuration >= c.minLockupDuration() && lockupDuration <= c.maxLockupDuration(), "incorrect duration");
        uint256 endTime = _now().add(lockupDuration);
        address validatorAddr = getValidator[toValidatorID].auth;
        if (delegator != validatorAddr) {
            require(getLockupInfo[validatorAddr][toValidatorID].endTime + 30 * 24 * 60 * 60 >= endTime, "validator's lockup will end too early");
        }

        _stashRewards(delegator, toValidatorID);
        _delStalePenalties(delegator, toValidatorID);

        // stash the previous penalty and clean getStashedLockupRewards
        LockedDelegation storage ld = getLockupInfo[delegator][toValidatorID];
        if (relock) {
            Penalty[] storage penalties = getStashedPenalties[delegator][toValidatorID];

            uint256 penalty = _popNonStashedUnlockPenalty(delegator, toValidatorID, ld.lockedStake, ld.lockedStake);
            if (penalty != 0) {
                penalties.push(Penalty(penalty, ld.endTime));
                require(penalties.length <= 30, "too many ongoing relocks");
                require(amount > ld.lockedStake / 100 || penalties.length <= 3 || endTime >= ld.endTime + 14 * 24 * 60 * 60, "too frequent relocks (github.com/Fantom-foundation/opera-sfc/wiki/Lockup-calls-reference#re-lock-stake)");
            }
        }

        // check lockup duration after _stashRewards, which has erased previous lockup if it has unlocked already
        require(lockupDuration >= ld.duration, "lockup duration cannot decrease");

        ld.lockedStake = ld.lockedStake.add(amount);
        ld.fromEpoch = currentEpoch();
        ld.endTime = endTime;
        ld.duration = lockupDuration;

        emit LockedUpStake(delegator, toValidatorID, lockupDuration, amount);
    }

    function lockStake(uint256 toValidatorID, uint256 lockupDuration, uint256 amount) public {
        address delegator = _addrToValidator(msg.sender, toValidatorID);
        require(amount > 0, "zero amount");
        require(!isLockedUp(delegator, toValidatorID), "already locked up");
        _lockStake(delegator, toValidatorID, lockupDuration, amount, false);
    }

    function relockStake(uint256 toValidatorID, uint256 lockupDuration, uint256 amount) public {
        address delegator = _addrToValidator(msg.sender, toValidatorID);
        require(isLockedUp(delegator, toValidatorID), "not locked up");
        _lockStake(delegator, toValidatorID, lockupDuration, amount, true);
    }

    function _popNonStashedUnlockPenalty(address delegator, uint256 toValidatorID, uint256 unlockAmount, uint256 totalAmount) internal returns (uint256) {
//        Rewards storage r = getStashedLockupRewards[delegator][toValidatorID];
//        uint256 lockupExtraRewardShare = r.lockupExtraReward.mul(unlockAmount).div(totalAmount);
//        uint256 lockupBaseRewardShare = r.lockupBaseReward.mul(unlockAmount).div(totalAmount);
//        uint256 penalty = lockupExtraRewardShare + lockupBaseRewardShare / 2;
//        r.lockupExtraReward = r.lockupExtraReward.sub(lockupExtraRewardShare);
//        r.lockupBaseReward = r.lockupBaseReward.sub(lockupBaseRewardShare);
//        return penalty;
        return 0;
    }

    function _popStashedUnlockPenalty(address delegator, uint256 toValidatorID, uint256 unlockAmount, uint256 totalAmount) internal returns (uint256) {
        _delStalePenalties(delegator, toValidatorID);
//        Penalty[] storage penalties = getStashedPenalties[delegator][toValidatorID];
//        uint256 total = 0;
//        for (uint256 i = 0; i < penalties.length; i++) {
//            uint256 penalty = penalties[i].amount.mul(unlockAmount).div(totalAmount);
//            penalties[i].amount = penalties[i].amount.sub(penalty);
//            total = total.add(penalty);
//        }
//        return total;
        return 0;
    }

    function _popWholeUnlockPenalty(address delegator, uint256 toValidatorID, uint256 unlockAmount, uint256 totalAmount) internal returns (uint256) {
        uint256 nonStashed = _popNonStashedUnlockPenalty(delegator, toValidatorID, unlockAmount, totalAmount);
        uint256 stashed = _popStashedUnlockPenalty(delegator, toValidatorID, unlockAmount, totalAmount);
        return nonStashed + stashed;
    }

    function unlockStake(uint256 toValidatorID, uint256 amount) external returns (uint256) {
        address delegator = _addrToValidator(msg.sender, toValidatorID);
        LockedDelegation storage ld = getLockupInfo[delegator][toValidatorID];

        require(amount > 0, "zero amount");
        require(isLockedUp(delegator, toValidatorID), "not locked up");
        require(amount <= ld.lockedStake, "not enough locked stake");
        require(_checkAllowedToWithdraw(delegator, toValidatorID), "outstanding sFTM balance");
//        require(!_redirected(delegator), "redirected");

        _stashRewards(delegator, toValidatorID);

        uint256 penalty = _popWholeUnlockPenalty(delegator, toValidatorID, amount, ld.lockedStake);
        if (penalty > amount) {
            penalty = amount;
        }
        ld.lockedStake -= amount;
        if (penalty != 0) {
            _rawUndelegate(delegator, toValidatorID, penalty, true, false, false);
            treasuryAddress.call.value(penalty)("");
        }

        emit UnlockedStake(delegator, toValidatorID, amount, penalty);
        return penalty;
    }

    function updateSlashingRefundRatio(uint256 validatorID, uint256 refundRatio) onlyOwner external {
        require(isSlashed(validatorID), "validator isn't slashed");
        require(refundRatio <= Decimal.unit(), "must be less than or equal to 1.0");
        slashingRefundRatio[validatorID] = refundRatio;
        emit UpdatedSlashingRefundRatio(validatorID, refundRatio);
    }

    function _delStalePenalties(address delegator, uint256 toValidatorID) public {
        Penalty[] storage penalties = getStashedPenalties[delegator][toValidatorID];
        for (uint256 i = 0; i < penalties.length;) {
            if (penalties[i].end < _now() || penalties[i].amount == 0) {
                penalties[i] = penalties[penalties.length - 1];
                penalties.pop();
            } else {
                i++;
            }
        }
    }

    function redirectedAccs() private pure returns(address[] memory, address[] memory) {
        // the addresses below were reported as stolen by their owners via the signatures below:
//        I redirect SFC withdrawals to account 0x80f93310709624636852d0111fd6c4A6e02ED0aA due to a potential attacker gaining access to my account.
//        {
//        "address": "0x93419fcb5d9dc7989439f0512d4f737421ed48d9",
//        "msg": "0x4920726564697265637420534643207769746864726177616c7320746f206163636f756e74203078383066393333313037303936323436333638353264303131316664366334413665303245443061412064756520746f206120706f74656e7469616c2061747461636b6572206761696e696e672061636365737320746f206d79206163636f756e742e",
//        "sig": "1c4f3168e01d499a657f0d1cd453b26e5f69aaf14372983ff62e54a1d53959e55edb0746f4aea0959899b06bf31dc6a0160f6ac428cd75d4657184ab2337e46e1c",
//        "version": "3",
//        "signer": "MEW"
//        }
//        --
//        I redirect SFC withdrawals to account 0x91B20102Dfd2ff1b00D0915266584009d0b1Ae39 due to a potential attacker gaining access to my account.
//        {
//        "address": "0xfbcae1b28ca5039dafec4f10a89e022bc8118394",
//        "msg": "0x4920726564697265637420534643207769746864726177616c7320746f206163636f756e74203078393142323031303244666432666631623030443039313532363635383430303964306231416533392064756520746f206120706f74656e7469616c2061747461636b6572206761696e696e672061636365737320746f206d79206163636f756e742e",
//        "sig": "c98431cc1b6f26b8248ca83f860721f31ec79097831e69c28d352512182bbfa93911564ed46ba11547b544c4d65380781a4f3cc6afe9f075d43a24e0947853151c",
//        "version": "3",
//        "signer": "MEW"
//        }
//        --
//        I redirect SFC withdrawals to account 0xCA3C54c11172A7263300a801E9937780b5143c08 due to a potential attacker gaining access to my account.
//        {
//        "address": "0x15c2ec517905fb3282f26f3ac3e12889755a2ed7",
//        "msg": "0x4920726564697265637420534643207769746864726177616c7320746f206163636f756e74203078434133433534633131313732413732363333303061383031453939333737383062353134336330382064756520746f206120706f74656e7469616c2061747461636b6572206761696e696e672061636365737320746f206d79206163636f756e742e",
//        "sig": "8d933ea6b1dfaa70c92d7dd8f68e9c821934eabd9c454dc792a90c9c58d0c4ec5c60d7737e7b8ed38cfdfe3bd7fce9a2c38133b9a98d6699088d79edb09ec3c21b",
//        "version": "3",
//        "signer": "MEW"
//        }
// --
// I redirect SFC withdrawals to account 0x5A1CAd027EACE4C052f5DEE0f42Da6c62E39b779 due to a potential attacker gaining access to my account.
// {
//  "address": "0xbdAaEC5f9317cC63D26FD7d79aD17372Ccd7d763",
//  "msg": "0x4920726564697265637420534643207769746864726177616c7320746f206163636f756e74203078354131434164303237454143453443303532663544454530663432446136633632453339623737392064756520746f206120706f74656e7469616c2061747461636b6572206761696e696e672061636365737320746f206d79206163636f756e742e",
//  "sig": "0e9b3ce37f665ab03bdfd3095671249e1b2842b1dd314fd4281bbed527ea69014ca510227e57f973b35ef175c1214fb1a842be70ff5a9290cb260799c544eed900",
//  "version": "3",
//  "signer": "MEW"
// }
// --
// I redirect SFC withdrawals to account 0x4A15B527475977D9B0CB3fcfE825d6Aa7428fAFC due to a potential attacker gaining access to my account.
// {
//  "address": "0xf72148504819A1D1B038694B02d299F65BfA312d",
//  "msg": "0x4920726564697265637420534643207769746864726177616c7320746f206163636f756e74203078344131354235323734373539373744394230434233666366453832356436416137343238664146432064756520746f206120706f74656e7469616c2061747461636b6572206761696e696e672061636365737320746f206d79206163636f756e742e",
//  "sig": "cf6386edbbee504c07ae95cb7c5ef06e7e0f57b34d51ab4e4047b5cb326af9bc236f544a3ced994cd20601047966e683aaaf329772fbb6bf37f0bd12200d1e6100",
//  "version": "3",
//  "signer": "MEW"
// }
        // The contract does not lock these positions; instead, it restricts withdrawals exclusively to the account designated in the signature.
        // This measure prevents an attacker from transferring FTM following a withdrawal.

        address[] memory froms = new address[](5);
        address[] memory tos = new address[](5);
        assert(froms.length == tos.length);
        froms[0] = 0x93419FcB5d9DC7989439f0512d4F737421ed48D9;
        tos[0] = 0x80f93310709624636852d0111fd6c4A6e02ED0aA;
        froms[1] = 0xFbCAe1B28ca5039DAFec4f10A89e022Bc8118394;
        tos[1] = 0x91B20102Dfd2ff1b00D0915266584009d0b1Ae39;
        froms[2] = 0x15C2EC517905fB3282f26F3aC3e12889755a2ed7;
        tos[2] = 0xCA3C54c11172A7263300a801E9937780b5143c08;
        froms[3] = 0xbdAaEC5f9317cC63D26FD7d79aD17372Ccd7d763;
        tos[3] = 0x5A1CAd027EACE4C052f5DEE0f42Da6c62E39b779;
        froms[4] = 0xf72148504819A1D1B038694B02d299F65BfA312d;
        tos[4] = 0x4A15B527475977D9B0CB3fcfE825d6Aa7428fAFC;
        return (froms, tos);
    }

    function _redirected(address addr) internal view returns(bool) {
        (address[] memory froms,) = redirectedAccs();
        for (uint256 i = 0; i < froms.length; i++) {
            if (addr == froms[i]) {
                return true;
            }
        }
        return getRedirection[addr] != address(0);
    }

    function _redirectedTo(address addr) internal view returns(address) {
        (address[] memory froms, address[] memory tos) = redirectedAccs();
        for (uint256 i = 0; i < froms.length; i++) {
            if (addr == froms[i]) {
                return tos[i];
            }
        }
        return getRedirection[addr];
    }

    function _receiverOf(address addr) internal view returns(address payable) {
        address to = _redirectedTo(addr);
        if (to == address(0)) {
            return address(uint160(addr));
        }
        return address(uint160(to));
    }

    /// Convert an address to validator's address if the address is white-listed address.
    /// Converts only to validators managed by Fantom Foundation. It is necessary to enable
    /// smooth transition to the new sonic chain.
    function _addrToValidator(address addr, uint256 validatorID) internal view returns(address) {
        // Fantom's wallet to make requests from
        if (addr != 0x0b2E90c831626A65a26f75153Be54aeaAeeb8363) {
            return addr;
        }

        // Fantom's validators <1,11>, 64
        if ((validatorID < 1 || validatorID > 11) && validatorID != 64) {
            return addr;
        }

        address validatorAddr = getValidator[validatorID].auth;
        if (validatorAddr == address(0)) {
            return addr;
        }

        return validatorAddr;
    }

    // code below can be erased after 1 year since deployment of multipenalties

    function _getAvgEpochStep(uint256 duration) internal view returns(uint256) {
        // estimate number of epochs such that we would make approximately 15 iterations
        uint256 tryEpochs = currentSealedEpoch / 5;
        if (tryEpochs > 10000) {
            tryEpochs = 10000;
        }
        uint256 tryEndTime = getEpochSnapshot[currentSealedEpoch - tryEpochs].endTime;
        if (tryEndTime == 0 || tryEpochs == 0) {
            return 0;
        }
        uint256 secondsPerEpoch = _now().sub(tryEndTime) / tryEpochs;
        return duration / (secondsPerEpoch * 15 + 1);
    }

    function _getAvgReceivedStake(uint256 validatorID, uint256 duration, uint256 step) internal view returns(uint256) {
        uint256 receivedStakeSum = getValidator[validatorID].receivedStake;
        uint256 samples = 1;

        uint256 until = _now().sub(duration);
        for (uint256 i = 1; i <= 30; i++) {
            uint256 e = currentSealedEpoch - i * step;
            EpochSnapshot storage s = getEpochSnapshot[e];
            if (s.endTime < until) {
                break;
            }
            uint256 sample = s.receivedStake[validatorID];
            if (sample != 0) {
                samples++;
                receivedStakeSum += sample;
            }
        }
        return receivedStakeSum / samples;
    }

    function _getAvgUptime(uint256 validatorID, uint256 duration, uint256 step) internal view returns(uint256) {
        uint256 until = _now().sub(duration);
        uint256 oldUptimeCounter = 0;
        uint256 newUptimeCounter = 0;
        for (uint256 i = 0; i <= 30; i++) {
            uint256 e = currentSealedEpoch - i * step;
            EpochSnapshot storage s = getEpochSnapshot[e];
            uint256 endTime = s.endTime;
            if (endTime < until) {
                if (i <= 2) {
                    return duration;
                }
                break;
            }
            uint256 uptimeCounter = s.accumulatedUptime[validatorID];
            if (uptimeCounter != 0) {
                oldUptimeCounter = uptimeCounter;
                if (newUptimeCounter == 0) {
                    newUptimeCounter = uptimeCounter;
                }
            }
        }
        uint256 uptime = newUptimeCounter - oldUptimeCounter;
        if (uptime > duration*4/5) {
            return duration;
        }
        return uptime;
    }

    function _truncateLegacyPenalty(address delegator, uint256 toValidatorID) internal {
        Rewards storage r = getStashedLockupRewards[delegator][toValidatorID];
        uint256 storedPenalty = r.lockupExtraReward + r.lockupBaseReward / 2;
        if (storedPenalty == 0) {
            return;
        }
        LockedDelegation storage ld = getLockupInfo[delegator][toValidatorID];
        uint256 duration = ld.duration;
        uint256 lockedStake = ld.lockedStake;
        uint256 step = _getAvgEpochStep(duration);
        if (step == 0) {
            return;
        }
        uint256 RPS = _getAvgUptime(toValidatorID, duration, step).mul(2092846271).div(duration); // corresponds to 6.6% APR
        uint256 selfStake = getStake[delegator][toValidatorID];

        uint256 avgFullReward = selfStake.mul(RPS).mul(duration).div(1e18).mul(Decimal.unit().sub(c.validatorCommission())).div(Decimal.unit()); // reward for self-stake
        if (getValidator[toValidatorID].auth == delegator) { // reward for received portion of stake
            uint256 receivedStakeAvg = _getAvgReceivedStake(toValidatorID, duration, step).mul(11).div(10);
            avgFullReward += receivedStakeAvg.mul(RPS).mul(duration).div(1e18).mul(c.validatorCommission()).div(Decimal.unit());
        }
        avgFullReward = avgFullReward.mul(lockedStake).div(selfStake);
        Rewards memory avgReward = _scaleLockupReward(avgFullReward, duration);
        uint256 maxReasonablePenalty = avgReward.lockupBaseReward / 2 + avgReward.lockupExtraReward;
        maxReasonablePenalty = maxReasonablePenalty;
        if (storedPenalty > maxReasonablePenalty) {
            r.lockupExtraReward = r.lockupExtraReward.mul(maxReasonablePenalty).div(storedPenalty);
            r.lockupBaseReward = r.lockupBaseReward.mul(maxReasonablePenalty).div(storedPenalty);
        }
    }
}
