// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Decimal} from "../common/Decimal.sol";
import {SFCBase} from "./SFCBase.sol";

contract SFCLib is SFCBase {
    event CreatedValidator(
        uint256 indexed validatorID,
        address indexed auth,
        uint256 createdEpoch,
        uint256 createdTime
    );
    event Delegated(address indexed delegator, uint256 indexed toValidatorID, uint256 amount);
    event Undelegated(address indexed delegator, uint256 indexed toValidatorID, uint256 indexed wrID, uint256 amount);
    event Withdrawn(address indexed delegator, uint256 indexed toValidatorID, uint256 indexed wrID, uint256 amount);
    event ClaimedRewards(
        address indexed delegator,
        uint256 indexed toValidatorID,
        uint256 lockupExtraReward,
        uint256 lockupBaseReward,
        uint256 unlockedReward
    );
    event RestakedRewards(
        address indexed delegator,
        uint256 indexed toValidatorID,
        uint256 lockupExtraReward,
        uint256 lockupBaseReward,
        uint256 unlockedReward
    );
    event BurntFTM(uint256 amount);
    event LockedUpStake(address indexed delegator, uint256 indexed validatorID, uint256 duration, uint256 amount);
    event UnlockedStake(address indexed delegator, uint256 indexed validatorID, uint256 amount, uint256 penalty);
    event UpdatedSlashingRefundRatio(uint256 indexed validatorID, uint256 refundRatio);
    event RefundedSlashedLegacyDelegation(address indexed delegator, uint256 indexed validatorID, uint256 amount);

    /*
    Constructor
    */

    function setGenesisValidator(
        address auth,
        uint256 validatorID,
        bytes calldata pubkey,
        uint256 status,
        uint256 createdEpoch,
        uint256 createdTime,
        uint256 deactivatedEpoch,
        uint256 deactivatedTime
    ) external onlyDriver {
        _rawCreateValidator(
            auth,
            validatorID,
            pubkey,
            status,
            createdEpoch,
            createdTime,
            deactivatedEpoch,
            deactivatedTime
        );
        if (validatorID > lastValidatorID) {
            lastValidatorID = validatorID;
        }
    }

    function setGenesisDelegation(
        address delegator,
        uint256 toValidatorID,
        uint256 stake,
        uint256 lockedStake,
        uint256 lockupFromEpoch,
        uint256 lockupEndTime,
        uint256 lockupDuration,
        uint256 earlyUnlockPenalty,
        uint256 rewards
    ) external onlyDriver {
        _rawDelegate(delegator, toValidatorID, stake, false);
        _rewardsStash[delegator][toValidatorID].unlockedReward = rewards;
        _mintNativeToken(stake);
        if (lockedStake != 0) {
            if (lockedStake > stake) {
                revert LockedStakeGreaterThanTotalStake();
            }
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
        if (msg.value < c.minSelfStake()) {
            revert InsufficientSelfStake();
        }
        if (pubkey.length == 0) {
            revert EmptyPubkey();
        }
        if (pubkeyHashToValidatorID[keccak256(pubkey)] != 0) {
            revert PubkeyUsedByOtherValidator();
        }
        _createValidator(msg.sender, pubkey);
        _delegate(msg.sender, lastValidatorID, msg.value);
    }

    function _createValidator(address auth, bytes memory pubkey) internal {
        uint256 validatorID = ++lastValidatorID;
        _rawCreateValidator(auth, validatorID, pubkey, OK_STATUS, currentEpoch(), _now(), 0, 0);
    }

    function _rawCreateValidator(
        address auth,
        uint256 validatorID,
        bytes memory pubkey,
        uint256 status,
        uint256 createdEpoch,
        uint256 createdTime,
        uint256 deactivatedEpoch,
        uint256 deactivatedTime
    ) internal {
        if (getValidatorID[auth] != 0) {
            revert ValidatorExists();
        }
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
        return
            getValidator[validatorID].receivedStake <=
            (getSelfStake(validatorID) * c.maxDelegatedRatio()) / Decimal.unit();
    }

    function delegate(uint256 toValidatorID) external payable {
        _delegate(msg.sender, toValidatorID, msg.value);
    }

    function _delegate(address delegator, uint256 toValidatorID, uint256 amount) internal {
        if (!_validatorExists(toValidatorID)) {
            revert ValidatorNotExists();
        }
        if (getValidator[toValidatorID].status != OK_STATUS) {
            revert ValidatorNotActive();
        }
        _rawDelegate(delegator, toValidatorID, amount, true);
        if (!_checkDelegatedStakeLimit(toValidatorID)) {
            revert ValidatorDelegationLimitExceeded();
        }
    }

    function _rawDelegate(address delegator, uint256 toValidatorID, uint256 amount, bool strict) internal {
        if (amount == 0) {
            revert ZeroAmount();
        }

        _stashRewards(delegator, toValidatorID);

        getStake[delegator][toValidatorID] = getStake[delegator][toValidatorID] + amount;
        uint256 origStake = getValidator[toValidatorID].receivedStake;
        getValidator[toValidatorID].receivedStake = origStake + amount;
        totalStake = totalStake + amount;
        if (getValidator[toValidatorID].status == OK_STATUS) {
            totalActiveStake = totalActiveStake + amount;
        }

        _syncValidator(toValidatorID, origStake == 0);

        emit Delegated(delegator, toValidatorID, amount);

        _recountVotes(delegator, getValidator[toValidatorID].auth, strict);
    }

    function recountVotes(address delegator, address validatorAuth, bool strict, uint256 gas) external {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = voteBookAddress.call{gas: gas}(
            abi.encodeWithSignature("recountVotes(address,address)", delegator, validatorAuth)
        );
        if (!success && strict) {
            revert GovVotesRecountFailed();
        }
    }

    function _rawUndelegate(
        address delegator,
        uint256 toValidatorID,
        uint256 amount,
        bool strict,
        bool forceful,
        bool checkDelegatedStake
    ) internal {
        getStake[delegator][toValidatorID] -= amount;
        getValidator[toValidatorID].receivedStake = getValidator[toValidatorID].receivedStake - amount;
        totalStake = totalStake - amount;
        if (getValidator[toValidatorID].status == OK_STATUS) {
            totalActiveStake = totalActiveStake - amount;
        }

        uint256 selfStakeAfterwards = getSelfStake(toValidatorID);
        if (selfStakeAfterwards != 0 && getValidator[toValidatorID].status == OK_STATUS) {
            if (!(selfStakeAfterwards >= c.minSelfStake())) {
                if (forceful) {
                    revert InsufficientSelfStake();
                } else {
                    _setValidatorDeactivated(toValidatorID, WITHDRAWN_BIT);
                }
            }
            if (checkDelegatedStake && !_checkDelegatedStakeLimit(toValidatorID)) {
                revert ValidatorDelegationLimitExceeded();
            }
        } else {
            _setValidatorDeactivated(toValidatorID, WITHDRAWN_BIT);
        }

        _recountVotes(delegator, getValidator[toValidatorID].auth, strict);
    }

    function undelegate(uint256 toValidatorID, uint256 wrID, uint256 amount) public {
        address delegator = msg.sender;

        _stashRewards(delegator, toValidatorID);

        if (amount == 0) {
            revert ZeroAmount();
        }

        if (amount > getUnlockedStake(delegator, toValidatorID)) {
            revert NotEnoughUnlockedStake();
        }

        if (getWithdrawalRequest[delegator][toValidatorID][wrID].amount != 0) {
            revert RequestExists();
        }

        _rawUndelegate(delegator, toValidatorID, amount, true, false, true);

        getWithdrawalRequest[delegator][toValidatorID][wrID].amount = amount;
        getWithdrawalRequest[delegator][toValidatorID][wrID].epoch = currentEpoch();
        getWithdrawalRequest[delegator][toValidatorID][wrID].time = _now();

        _syncValidator(toValidatorID, false);

        emit Undelegated(delegator, toValidatorID, wrID, amount);
    }

    function isSlashed(uint256 validatorID) public view returns (bool) {
        return getValidator[validatorID].status & CHEATER_MASK != 0;
    }

    function getSlashingPenalty(
        uint256 amount,
        bool isCheater,
        uint256 refundRatio
    ) internal pure returns (uint256 penalty) {
        if (!isCheater || refundRatio >= Decimal.unit()) {
            return 0;
        }
        // round penalty upwards (ceiling) to prevent dust amount attacks
        penalty = (amount * (Decimal.unit() - refundRatio)) / Decimal.unit() + 1;
        if (penalty > amount) {
            return amount;
        }
        return penalty;
    }

    function _withdraw(address delegator, uint256 toValidatorID, uint256 wrID, address payable receiver) private {
        WithdrawalRequest memory request = getWithdrawalRequest[delegator][toValidatorID][wrID];
        if (request.epoch == 0) {
            revert RequestNotExists();
        }

        uint256 requestTime = request.time;
        uint256 requestEpoch = request.epoch;
        if (
            getValidator[toValidatorID].deactivatedTime != 0 &&
            getValidator[toValidatorID].deactivatedTime < requestTime
        ) {
            requestTime = getValidator[toValidatorID].deactivatedTime;
            requestEpoch = getValidator[toValidatorID].deactivatedEpoch;
        }

        if (_now() < requestTime + c.withdrawalPeriodTime()) {
            revert NotEnoughTimePassed();
        }

        if (currentEpoch() < requestEpoch + c.withdrawalPeriodEpochs()) {
            revert NotEnoughEpochsPassed();
        }

        uint256 amount = getWithdrawalRequest[delegator][toValidatorID][wrID].amount;
        bool isCheater = isSlashed(toValidatorID);
        uint256 penalty = getSlashingPenalty(amount, isCheater, slashingRefundRatio[toValidatorID]);
        delete getWithdrawalRequest[delegator][toValidatorID][wrID];

        if (amount <= penalty) {
            revert StakeIsFullySlashed();
        }
        // It's important that we transfer after erasing (protection against Re-Entrancy)
        (bool sent, ) = receiver.call{value: amount - penalty}("");
        if (!sent) {
            revert TransferFailed();
        }
        _burnFTM(penalty);

        emit Withdrawn(delegator, toValidatorID, wrID, amount);
    }

    function withdraw(uint256 toValidatorID, uint256 wrID) public {
        _withdraw(msg.sender, toValidatorID, wrID, _receiverOf(msg.sender));
    }

    function deactivateValidator(uint256 validatorID, uint256 status) external onlyDriver {
        if (status == OK_STATUS) {
            revert WrongValidatorStatus();
        }

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
        uint256 fromEpoch = getLockupInfo[delegator][validatorID].fromEpoch;
        uint256 r = currentSealedEpoch;
        if (_isLockedUpAtEpoch(delegator, validatorID, r)) {
            return r;
        }
        if (!_isLockedUpAtEpoch(delegator, validatorID, fromEpoch)) {
            return 0;
        }
        if (fromEpoch > r) {
            return 0;
        }
        while (fromEpoch < r) {
            uint256 m = (fromEpoch + r) / 2;
            if (_isLockedUpAtEpoch(delegator, validatorID, m)) {
                fromEpoch = m + 1;
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
        uint256 unlockedStake = wholeStake - ld.lockedStake;
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

    function _newRewardsOf(
        uint256 stakeAmount,
        uint256 toValidatorID,
        uint256 fromEpoch,
        uint256 toEpoch
    ) internal view returns (uint256) {
        if (fromEpoch >= toEpoch) {
            return 0;
        }
        uint256 stashedRate = getEpochSnapshot[fromEpoch].accumulatedRewardPerToken[toValidatorID];
        uint256 currentRate = getEpochSnapshot[toEpoch].accumulatedRewardPerToken[toValidatorID];
        return ((currentRate - stashedRate) * stakeAmount) / Decimal.unit();
    }

    function _pendingRewards(address delegator, uint256 toValidatorID) internal view returns (Rewards memory) {
        Rewards memory reward = _newRewards(delegator, toValidatorID);
        return sumRewards(_rewardsStash[delegator][toValidatorID], reward);
    }

    function pendingRewards(address delegator, uint256 toValidatorID) public view returns (uint256) {
        Rewards memory reward = _pendingRewards(delegator, toValidatorID);
        return reward.unlockedReward + reward.lockupBaseReward + reward.lockupExtraReward;
    }

    function stashRewards(address delegator, uint256 toValidatorID) external {
        if (!_stashRewards(delegator, toValidatorID)) {
            revert NothingToStash();
        }
    }

    function _stashRewards(address delegator, uint256 toValidatorID) internal returns (bool updated) {
        Rewards memory nonStashedReward = _newRewards(delegator, toValidatorID);
        stashedRewardsUntilEpoch[delegator][toValidatorID] = _highestPayableEpoch(toValidatorID);
        _rewardsStash[delegator][toValidatorID] = sumRewards(_rewardsStash[delegator][toValidatorID], nonStashedReward);
        getStashedLockupRewards[delegator][toValidatorID] = sumRewards(
            getStashedLockupRewards[delegator][toValidatorID],
            nonStashedReward
        );
        if (!isLockedUp(delegator, toValidatorID)) {
            delete getLockupInfo[delegator][toValidatorID];
            delete getStashedLockupRewards[delegator][toValidatorID];
        }
        _truncateLegacyPenalty(delegator, toValidatorID);
        return
            nonStashedReward.lockupBaseReward != 0 ||
            nonStashedReward.lockupExtraReward != 0 ||
            nonStashedReward.unlockedReward != 0;
    }

    function _claimRewards(address delegator, uint256 toValidatorID) internal returns (Rewards memory rewards) {
        _stashRewards(delegator, toValidatorID);
        rewards = _rewardsStash[delegator][toValidatorID];
        uint256 totalReward = rewards.unlockedReward + rewards.lockupBaseReward + rewards.lockupExtraReward;
        if (totalReward == 0) {
            revert ZeroRewards();
        }
        delete _rewardsStash[delegator][toValidatorID];
        // It's important that we mint after erasing (protection against Re-Entrancy)
        _mintNativeToken(totalReward);
        return rewards;
    }

    function claimRewards(uint256 toValidatorID) public {
        address delegator = msg.sender;
        Rewards memory rewards = _claimRewards(delegator, toValidatorID);
        // It's important that we transfer after erasing (protection against Re-Entrancy)
        (bool sent, ) = _receiverOf(delegator).call{
            value: rewards.lockupExtraReward + rewards.lockupBaseReward + rewards.unlockedReward
        }("");

        if (!sent) {
            revert TransferFailed();
        }

        emit ClaimedRewards(
            delegator,
            toValidatorID,
            rewards.lockupExtraReward,
            rewards.lockupBaseReward,
            rewards.unlockedReward
        );
    }

    function restakeRewards(uint256 toValidatorID) public {
        address delegator = msg.sender;
        Rewards memory rewards = _claimRewards(delegator, toValidatorID);

        uint256 lockupReward = rewards.lockupExtraReward + rewards.lockupBaseReward;
        _delegate(delegator, toValidatorID, lockupReward + rewards.unlockedReward);
        getLockupInfo[delegator][toValidatorID].lockedStake += lockupReward;
        emit RestakedRewards(
            delegator,
            toValidatorID,
            rewards.lockupExtraReward,
            rewards.lockupBaseReward,
            rewards.unlockedReward
        );
    }

    // burnFTM allows SFC to burn an arbitrary amount of FTM tokens
    function burnFTM(uint256 amount) external onlyOwner {
        _burnFTM(amount);
    }

    function _burnFTM(uint256 amount) internal {
        if (amount != 0) {
            payable(address(0)).transfer(amount);
            emit BurntFTM(amount);
        }
    }

    function epochEndTime(uint256 epoch) internal view returns (uint256) {
        return getEpochSnapshot[epoch].endTime;
    }

    function _isLockedUpAtEpoch(address delegator, uint256 toValidatorID, uint256 epoch) internal view returns (bool) {
        return
            getLockupInfo[delegator][toValidatorID].fromEpoch <= epoch &&
            epochEndTime(epoch) <= getLockupInfo[delegator][toValidatorID].endTime;
    }

    function getUnlockedStake(address delegator, uint256 toValidatorID) public view returns (uint256) {
        if (!isLockedUp(delegator, toValidatorID)) {
            return getStake[delegator][toValidatorID];
        }
        return getStake[delegator][toValidatorID] - getLockupInfo[delegator][toValidatorID].lockedStake;
    }

    function _lockStake(
        address delegator,
        uint256 toValidatorID,
        uint256 lockupDuration,
        uint256 amount,
        bool relock
    ) internal {
        if (_redirected(delegator)) {
            revert Redirected();
        }

        if (amount > getUnlockedStake(delegator, toValidatorID)) {
            revert NotEnoughUnlockedStake();
        }

        if (getValidator[toValidatorID].status != OK_STATUS) {
            revert ValidatorNotActive();
        }

        if (lockupDuration < c.minLockupDuration() || lockupDuration > c.maxLockupDuration()) {
            revert IncorrectDuration();
        }

        uint256 endTime = _now() + lockupDuration;
        address validatorAddr = getValidator[toValidatorID].auth;
        if (
            delegator != validatorAddr &&
            getLockupInfo[validatorAddr][toValidatorID].endTime + 30 * 24 * 60 * 60 < endTime
        ) {
            revert ValidatorLockupTooShort();
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
                if (penalties.length > 30) {
                    revert TooManyReLocks();
                }
                if (
                    amount <= ld.lockedStake / 100 && penalties.length > 3 && endTime < ld.endTime + 14 * 24 * 60 * 60
                ) {
                    revert TooFrequentReLocks();
                }
            }
        }

        // check lockup duration after _stashRewards, which has erased previous lockup if it has unlocked already
        if (lockupDuration < ld.duration) {
            revert LockupDurationDecreased();
        }

        ld.lockedStake = ld.lockedStake + amount;
        ld.fromEpoch = currentEpoch();
        ld.endTime = endTime;
        ld.duration = lockupDuration;

        emit LockedUpStake(delegator, toValidatorID, lockupDuration, amount);
    }

    function lockStake(uint256 toValidatorID, uint256 lockupDuration, uint256 amount) public {
        address delegator = msg.sender;
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (isLockedUp(delegator, toValidatorID)) {
            revert AlreadyLockedUp();
        }
        _lockStake(delegator, toValidatorID, lockupDuration, amount, false);
    }

    function relockStake(uint256 toValidatorID, uint256 lockupDuration, uint256 amount) public {
        address delegator = msg.sender;
        if (!isLockedUp(delegator, toValidatorID)) {
            revert NotLockedUp();
        }
        _lockStake(delegator, toValidatorID, lockupDuration, amount, true);
    }

    function _popNonStashedUnlockPenalty(
        address delegator,
        uint256 toValidatorID,
        uint256 unlockAmount,
        uint256 totalAmount
    ) internal returns (uint256) {
        Rewards storage r = getStashedLockupRewards[delegator][toValidatorID];
        uint256 lockupExtraRewardShare = (r.lockupExtraReward * unlockAmount) / totalAmount;
        uint256 lockupBaseRewardShare = (r.lockupBaseReward * unlockAmount) / totalAmount;
        uint256 penalty = lockupExtraRewardShare + lockupBaseRewardShare / 2;
        r.lockupExtraReward = r.lockupExtraReward - lockupExtraRewardShare;
        r.lockupBaseReward = r.lockupBaseReward - lockupBaseRewardShare;
        return penalty;
    }

    function _popStashedUnlockPenalty(
        address delegator,
        uint256 toValidatorID,
        uint256 unlockAmount,
        uint256 totalAmount
    ) internal returns (uint256) {
        _delStalePenalties(delegator, toValidatorID);
        Penalty[] storage penalties = getStashedPenalties[delegator][toValidatorID];
        uint256 total = 0;
        for (uint256 i = 0; i < penalties.length; i++) {
            uint256 penalty = (penalties[i].amount * unlockAmount) / totalAmount;
            penalties[i].amount = penalties[i].amount - penalty;
            total = total + penalty;
        }
        return total;
    }

    function _popWholeUnlockPenalty(
        address delegator,
        uint256 toValidatorID,
        uint256 unlockAmount,
        uint256 totalAmount
    ) internal returns (uint256) {
        uint256 nonStashed = _popNonStashedUnlockPenalty(delegator, toValidatorID, unlockAmount, totalAmount);
        uint256 stashed = _popStashedUnlockPenalty(delegator, toValidatorID, unlockAmount, totalAmount);
        return nonStashed + stashed;
    }

    function unlockStake(uint256 toValidatorID, uint256 amount) external returns (uint256) {
        address delegator = msg.sender;
        LockedDelegation storage ld = getLockupInfo[delegator][toValidatorID];

        if (amount == 0) {
            revert ZeroAmount();
        }
        if (!isLockedUp(delegator, toValidatorID)) {
            revert NotLockedUp();
        }
        if (amount > ld.lockedStake) {
            revert NotEnoughLockedStake();
        }
        if (_redirected(delegator)) {
            revert Redirected();
        }

        _stashRewards(delegator, toValidatorID);

        uint256 penalty = _popWholeUnlockPenalty(delegator, toValidatorID, amount, ld.lockedStake);
        if (penalty > amount) {
            penalty = amount;
        }
        ld.lockedStake -= amount;
        if (penalty != 0) {
            _rawUndelegate(delegator, toValidatorID, penalty, true, false, false);
            (bool success, ) = treasuryAddress.call{value: penalty}("");
            if (!success) {
                revert TransferFailed();
            }
        }

        emit UnlockedStake(delegator, toValidatorID, amount, penalty);
        return penalty;
    }

    function updateSlashingRefundRatio(uint256 validatorID, uint256 refundRatio) external onlyOwner {
        if (!isSlashed(validatorID)) {
            revert ValidatorNotSlashed();
        }
        if (refundRatio > Decimal.unit()) {
            revert RefundRatioTooHigh();
        }
        slashingRefundRatio[validatorID] = refundRatio;
        emit UpdatedSlashingRefundRatio(validatorID, refundRatio);
    }

    function _delStalePenalties(address delegator, uint256 toValidatorID) public {
        Penalty[] storage penalties = getStashedPenalties[delegator][toValidatorID];
        for (uint256 i = 0; i < penalties.length; ) {
            if (penalties[i].end < _now() || penalties[i].amount == 0) {
                penalties[i] = penalties[penalties.length - 1];
                penalties.pop();
            } else {
                i++;
            }
        }
    }

    function _redirected(address addr) internal view returns (bool) {
        return getRedirection[addr] != address(0);
    }

    function _receiverOf(address addr) internal view returns (address payable) {
        address to = getRedirection[addr];
        if (to == address(0)) {
            return payable(address(uint160(addr)));
        }
        return payable(address(uint160(to)));
    }

    // code below can be erased after 1 year since deployment of multipenalties

    function _getAvgEpochStep(uint256 duration) internal view virtual returns (uint256) {
        // estimate number of epochs such that we would make approximately 15 iterations
        uint256 tryEpochs = currentSealedEpoch / 5;
        if (tryEpochs > 10000) {
            tryEpochs = 10000;
        }
        uint256 tryEndTime = getEpochSnapshot[currentSealedEpoch - tryEpochs].endTime;
        if (tryEndTime == 0 || tryEpochs == 0) {
            return 0;
        }
        uint256 secondsPerEpoch = (_now() - tryEndTime) / tryEpochs;
        return duration / (secondsPerEpoch * 15 + 1);
    }

    function _getAvgReceivedStake(uint256 validatorID, uint256 duration, uint256 step) internal view returns (uint256) {
        uint256 receivedStakeSum = getValidator[validatorID].receivedStake;
        uint256 samples = 1;

        uint256 until = _now() - duration;
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

    function _getAvgUptime(
        uint256 validatorID,
        uint256 duration,
        uint256 step
    ) internal view virtual returns (uint256) {
        uint256 until = _now() - duration;
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
        if (uptime > (duration * 4) / 5) {
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
        uint256 rps = (_getAvgUptime(toValidatorID, duration, step) * 2092846271) / duration; // corresponds to 6.6% APR
        uint256 selfStake = getStake[delegator][toValidatorID];

        uint256 avgFullReward = (((selfStake * rps * duration) / 1e18) * (Decimal.unit() - c.validatorCommission())) /
            Decimal.unit(); // reward for self-stake
        if (getValidator[toValidatorID].auth == delegator) {
            // reward for received portion of stake
            uint256 receivedStakeAvg = (_getAvgReceivedStake(toValidatorID, duration, step) * 11) / 10;
            avgFullReward += (((receivedStakeAvg * rps * duration) / 1e18) * c.validatorCommission()) / Decimal.unit();
        }
        avgFullReward = (avgFullReward * lockedStake) / selfStake;
        Rewards memory avgReward = _scaleLockupReward(avgFullReward, duration);
        uint256 maxReasonablePenalty = avgReward.lockupBaseReward / 2 + avgReward.lockupExtraReward;
        maxReasonablePenalty = maxReasonablePenalty;
        if (storedPenalty > maxReasonablePenalty) {
            r.lockupExtraReward = (r.lockupExtraReward * maxReasonablePenalty) / storedPenalty;
            r.lockupBaseReward = (r.lockupBaseReward * maxReasonablePenalty) / storedPenalty;
        }
    }
}
