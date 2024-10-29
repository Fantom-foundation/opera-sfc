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
    event ClaimedRewards(address indexed delegator, uint256 indexed toValidatorID, uint256 rewards);
    event RestakedRewards(address indexed delegator, uint256 indexed toValidatorID, uint256 rewards);
    event BurntFTM(uint256 amount);
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

    function setGenesisDelegation(address delegator, uint256 toValidatorID, uint256 stake) external onlyDriver {
        _rawDelegate(delegator, toValidatorID, stake, false);
        _mintNativeToken(stake);
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

    function _newRewards(address delegator, uint256 toValidatorID) internal view returns (uint256) {
        uint256 stashedUntil = stashedRewardsUntilEpoch[delegator][toValidatorID];
        uint256 payableUntil = _highestPayableEpoch(toValidatorID);
        uint256 wholeStake = getStake[delegator][toValidatorID];
        uint256 fullReward = _newRewardsOf(wholeStake, toValidatorID, stashedUntil, payableUntil);
        return _scaleReward(fullReward);
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

    function pendingRewards(address delegator, uint256 toValidatorID) public view returns (uint256) {
        uint256 reward = _newRewards(delegator, toValidatorID);
        return _rewardsStash[delegator][toValidatorID] + reward;
    }

    function stashRewards(address delegator, uint256 toValidatorID) external {
        if (!_stashRewards(delegator, toValidatorID)) {
            revert NothingToStash();
        }
    }

    function _stashRewards(address delegator, uint256 toValidatorID) internal returns (bool updated) {
        uint256 nonStashedReward = _newRewards(delegator, toValidatorID);
        if (nonStashedReward == 0) {
            return false;
        }
        stashedRewardsUntilEpoch[delegator][toValidatorID] = _highestPayableEpoch(toValidatorID);
        _rewardsStash[delegator][toValidatorID] = _rewardsStash[delegator][toValidatorID] + nonStashedReward;
        return true;
    }

    function _claimRewards(address delegator, uint256 toValidatorID) internal returns (uint256) {
        _stashRewards(delegator, toValidatorID);
        uint256 rewards = _rewardsStash[delegator][toValidatorID];
        if (rewards == 0) {
            revert ZeroRewards();
        }
        delete _rewardsStash[delegator][toValidatorID];
        // It's important that we mint after erasing (protection against Re-Entrancy)
        _mintNativeToken(rewards);
        return rewards;
    }

    function claimRewards(uint256 toValidatorID) public {
        address delegator = msg.sender;
        uint256 rewards = _claimRewards(delegator, toValidatorID);
        // It's important that we transfer after erasing (protection against Re-Entrancy)
        (bool sent, ) = _receiverOf(delegator).call{value: rewards}("");
        if (!sent) {
            revert TransferFailed();
        }

        emit ClaimedRewards(delegator, toValidatorID, rewards);
    }

    function restakeRewards(uint256 toValidatorID) public {
        address delegator = msg.sender;
        uint256 rewards = _claimRewards(delegator, toValidatorID);

        _delegate(delegator, toValidatorID, rewards);
        emit RestakedRewards(delegator, toValidatorID, rewards);
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
}
