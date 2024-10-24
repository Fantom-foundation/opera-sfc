// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Decimal} from "../common/Decimal.sol";
import {SFCState} from "./SFCState.sol";

contract SFCBase is SFCState {
    uint256 internal constant OK_STATUS = 0;
    uint256 internal constant WITHDRAWN_BIT = 1;
    uint256 internal constant OFFLINE_BIT = 1 << 3;
    uint256 internal constant DOUBLESIGN_BIT = 1 << 7;
    uint256 internal constant CHEATER_MASK = DOUBLESIGN_BIT;

    // auth
    error NotDriverAuth();
    error NotAuthorized();

    // addresses
    error ZeroAddress();
    error SameAddress();

    // values
    error ZeroAmount();
    error ZeroRewards();

    // pubkeys
    error PubkeyUsedByOtherValidator();
    error MalformedPubkey();
    error PubkeyNotChanged();
    error EmptyPubkey();
    error TooManyPubkeyUpdates();

    // redirections
    error SameRedirectionAuthorizer();
    error Redirected();

    // validators
    error ValidatorNotExists();
    error ValidatorExists();
    error ValidatorNotActive();
    error ValidatorDelegationLimitExceeded();
    error WrongValidatorStatus();

    // requests
    error AlreadyRedirected();
    error RequestExists();
    error RequestNotExists();

    // transfers
    error TransfersNotAllowed();
    error TransferFailed();

    // updater
    error SFCAlreadyUpdated();
    error SFCWrongVersion();
    error SFCGovAlreadyUpdated();
    error SFCWrongGovVersion();

    // governance
    error GovVotesRecountFailed();

    // staking
    error LockedStakeGreaterThanTotalStake();
    error InsufficientSelfStake();
    error NotEnoughUnlockedStake();
    error NotEnoughLockedStake();
    error NotEnoughTimePassed();
    error NotEnoughEpochsPassed();
    error StakeIsFullySlashed();
    error IncorrectDuration();
    error ValidatorLockupTooShort();
    error TooManyReLocks();
    error TooFrequentReLocks();
    error LockupDurationDecreased();
    error AlreadyLockedUp();
    error NotLockedUp();

    // stashing
    error NothingToStash();

    // slashing
    error ValidatorNotSlashed();
    error RefundRatioTooHigh();

    event DeactivatedValidator(uint256 indexed validatorID, uint256 deactivatedEpoch, uint256 deactivatedTime);
    event ChangedValidatorStatus(uint256 indexed validatorID, uint256 status);

    function isNode(address addr) internal view virtual returns (bool) {
        return addr == address(node);
    }

    modifier onlyDriver() {
        if (!isNode(msg.sender)) {
            revert NotDriverAuth();
        }
        _;
    }

    function currentEpoch() public view returns (uint256) {
        return currentSealedEpoch + 1;
    }

    function _calcRawValidatorEpochTxReward(
        uint256 epochFee,
        uint256 txRewardWeight,
        uint256 totalTxRewardWeight
    ) internal view returns (uint256) {
        if (txRewardWeight == 0) {
            return 0;
        }
        uint256 txReward = (epochFee * txRewardWeight) / totalTxRewardWeight;
        // fee reward except burntFeeShare and treasuryFeeShare
        return (txReward * (Decimal.unit() - c.burntFeeShare() - c.treasuryFeeShare())) / Decimal.unit();
    }

    function _calcRawValidatorEpochBaseReward(
        uint256 epochDuration,
        uint256 _baseRewardPerSecond,
        uint256 baseRewardWeight,
        uint256 totalBaseRewardWeight
    ) internal pure returns (uint256) {
        if (baseRewardWeight == 0) {
            return 0;
        }
        uint256 totalReward = epochDuration * _baseRewardPerSecond;
        return (totalReward * baseRewardWeight) / totalBaseRewardWeight;
    }

    function _mintNativeToken(uint256 amount) internal {
        // balance will be increased after the transaction is processed
        node.incBalance(address(this), amount);
        totalSupply = totalSupply + amount;
    }

    function sumRewards(Rewards memory a, Rewards memory b) internal pure returns (Rewards memory) {
        return
            Rewards(
                a.lockupExtraReward + b.lockupExtraReward,
                a.lockupBaseReward + b.lockupBaseReward,
                a.unlockedReward + b.unlockedReward
            );
    }

    function sumRewards(Rewards memory a, Rewards memory b, Rewards memory c) internal pure returns (Rewards memory) {
        return sumRewards(sumRewards(a, b), c);
    }

    function _scaleLockupReward(
        uint256 fullReward,
        uint256 lockupDuration
    ) internal view returns (Rewards memory reward) {
        reward = Rewards(0, 0, 0);
        uint256 unlockedRewardRatio = c.unlockedRewardRatio();
        if (lockupDuration != 0) {
            uint256 maxLockupExtraRatio = Decimal.unit() - unlockedRewardRatio;
            uint256 lockupExtraRatio = (maxLockupExtraRatio * lockupDuration) / c.maxLockupDuration();
            uint256 totalScaledReward = (fullReward * (unlockedRewardRatio + lockupExtraRatio)) / Decimal.unit();
            reward.lockupBaseReward = (fullReward * unlockedRewardRatio) / Decimal.unit();
            reward.lockupExtraReward = totalScaledReward - reward.lockupBaseReward;
        } else {
            reward.unlockedReward = (fullReward * unlockedRewardRatio) / Decimal.unit();
        }
        return reward;
    }

    function _recountVotes(address delegator, address validatorAuth, bool strict) internal {
        if (voteBookAddress != address(0)) {
            // Don't allow recountVotes to use up all the gas
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = voteBookAddress.call{gas: 8000000}(
                abi.encodeWithSignature("recountVotes(address,address)", delegator, validatorAuth)
            );
            // Don't revert if recountVotes failed unless strict mode enabled
            if (!success && strict) {
                revert GovVotesRecountFailed();
            }
        }
    }

    function _setValidatorDeactivated(uint256 validatorID, uint256 status) internal {
        if (getValidator[validatorID].status == OK_STATUS && status != OK_STATUS) {
            totalActiveStake = totalActiveStake - getValidator[validatorID].receivedStake;
        }
        // status as a number is proportional to severity
        if (status > getValidator[validatorID].status) {
            getValidator[validatorID].status = status;
            if (getValidator[validatorID].deactivatedEpoch == 0) {
                getValidator[validatorID].deactivatedEpoch = currentEpoch();
                getValidator[validatorID].deactivatedTime = _now();
                emit DeactivatedValidator(
                    validatorID,
                    getValidator[validatorID].deactivatedEpoch,
                    getValidator[validatorID].deactivatedTime
                );
            }
            emit ChangedValidatorStatus(validatorID, status);
        }
    }

    function _syncValidator(uint256 validatorID, bool syncPubkey) public {
        if (!_validatorExists(validatorID)) {
            revert ValidatorNotExists();
        }
        // emit special log for node
        uint256 weight = getValidator[validatorID].receivedStake;
        if (getValidator[validatorID].status != OK_STATUS) {
            weight = 0;
        }
        node.updateValidatorWeight(validatorID, weight);
        if (syncPubkey && weight != 0) {
            node.updateValidatorPubkey(validatorID, getValidatorPubkey[validatorID]);
        }
    }

    function _validatorExists(uint256 validatorID) internal view returns (bool) {
        return getValidator[validatorID].createdTime != 0;
    }

    function _calcValidatorCommission(uint256 rawReward, uint256 commission) internal pure returns (uint256) {
        return (rawReward * commission) / Decimal.unit();
    }

    function getLockedStake(address delegator, uint256 toValidatorID) public view returns (uint256) {
        if (!isLockedUp(delegator, toValidatorID)) {
            return 0;
        }
        return getLockupInfo[delegator][toValidatorID].lockedStake;
    }

    function isLockedUp(address delegator, uint256 toValidatorID) public view returns (bool) {
        return
            getLockupInfo[delegator][toValidatorID].endTime != 0 &&
            getLockupInfo[delegator][toValidatorID].lockedStake != 0 &&
            _now() <= getLockupInfo[delegator][toValidatorID].endTime;
    }

    function _now() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}
