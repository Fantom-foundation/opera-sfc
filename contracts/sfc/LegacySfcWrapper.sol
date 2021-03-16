pragma solidity ^0.5.0;

import "./SFC.sol";

// LegacySfcWrapper adds the legacy SFCv2 functions for backward compatibility
contract LegacySfcWrapper is SFC {
    function minStake() public pure returns (uint256) {
        return minSelfStake();
    }

    function minStakeIncrease() public pure returns (uint256) {
        return 1;
    }

    function minStakeDecrease() public pure returns (uint256) {
        return 1;
    }

    function minDelegation() public pure returns (uint256) {
        return 1;
    }

    function minDelegationIncrease() public pure returns (uint256) {
        return 1;
    }

    function minDelegationDecrease() public pure returns (uint256) {
        return 1;
    }

    function stakeLockPeriodTime() public pure returns (uint256) {
        return withdrawalPeriodEpochs();
    }

    function stakeLockPeriodEpochs() public pure returns (uint256) {
        return withdrawalPeriodEpochs();
    }

    function delegationLockPeriodTime() public pure returns (uint256) {
        return withdrawalPeriodTime();
    }

    function delegationLockPeriodEpochs() public pure returns (uint256) {
        return withdrawalPeriodEpochs();
    }

    function delegations(address _from, uint256 _toStakerID) external view returns (uint256 createdEpoch, uint256 createdTime,
        uint256 deactivatedEpoch, uint256 deactivatedTime, uint256 amount, uint256 paidUntilEpoch, uint256 toStakerID) {
        uint256 stake = getStake[_from][_toStakerID];
        if (stake == 0) {
            return (0, 0, 0, 0, 0, 0, 0);
        }
        return (1, 1, 0, 0, stake, 1, _toStakerID);
    }

    function stakers(uint256 _stakerID) external view returns (uint256 status, uint256 createdEpoch, uint256 createdTime,
        uint256 deactivatedEpoch, uint256 deactivatedTime, uint256 stakeAmount, uint256 paidUntilEpoch, uint256 delegatedMe, address dagAddress, address sfcAddress) {
        Validator memory v = getValidator[_stakerID];
        if (v.status == OFFLINE_BIT) {
            v.status = 1 << 8;
        } else if (v.status == DOUBLESIGN_BIT) {
            v.status = 1;
        } else if (v.status == WITHDRAWN_BIT) {
            v.status = 0;
        }
        uint256 selfStake = getSelfStake(_stakerID);
        return (v.status, v.createdEpoch, v.createdTime, v.deactivatedEpoch, v.deactivatedTime, selfStake, 1, v.receivedStake.sub(selfStake), v.auth, v.auth);
    }

    function getStakerID(address _addr) external view returns (uint256) {
        return getValidatorID[_addr];
    }

    function stakeTotalAmount() public view returns (uint256) {
        // Note: estimate the total self stake, as it cannot be calculated cheaply in SFC v3
        return (totalStake * 24) / 100;
    }

    function delegationsTotalAmount() external view returns (uint256) {
        return totalStake - stakeTotalAmount();
    }

    function isDelegationLockedUp(address delegator, uint256 toStakerID) view public returns (bool) {
        return isLockedUp(delegator, toStakerID);
    }

    function isStakeLockedUp(uint256 stakerID) view public returns (bool) {
        return isLockedUp(getValidator[stakerID].auth, stakerID);
    }

    function stakersLastID() view public returns (uint256) {
        return lastValidatorID;
    }

    function stakersNum() view public returns (uint256) {
        return lastValidatorID;
    }

    function delegationsNum() pure public returns (uint256) {
        return 0;
    }

    function lockedDelegations(address delegator, uint256 toStakerID) public view returns (uint256 fromEpoch, uint256 endTime, uint256 duration) {
        LockedDelegation memory l = getLockupInfo[delegator][toStakerID];
        return (l.fromEpoch, l.endTime, l.duration);
    }

    function lockedStakes(uint256 stakerID) external view returns (uint256 fromEpoch, uint256 endTime, uint256 duration) {
        return lockedDelegations(getValidator[stakerID].auth, stakerID);
    }

    function createDelegation(uint256 toValidatorID) external payable {
        _delegate(msg.sender, toValidatorID, msg.value);
    }

    function calcDelegationRewards(address delegator, uint256 toStakerID, uint256 /*_fromEpoch*/, uint256 /*maxEpochs*/) public view returns (uint256, uint256, uint256) {
        uint256 rewards = pendingRewards(delegator, toStakerID);
        if (rewards == 0) {
            return (0, 1, 0);
        }
        return (rewards, currentSealedEpoch, currentSealedEpoch);
    }

    function calcValidatorRewards(uint256 stakerID, uint256 /*_fromEpoch*/, uint256 /*maxEpochs*/) public view returns (uint256, uint256, uint256) {
        uint256 rewards = pendingRewards(getValidator[stakerID].auth, stakerID);
        if (rewards == 0) {
            return (0, 1, 0);
        }
        return (rewards, currentSealedEpoch, currentSealedEpoch);
    }

    function claimDelegationRewards(uint256 /*maxEpochs*/, uint256 toStakerID) external {
        claimRewards(toStakerID);
    }

    function claimDelegationCompoundRewards(uint256 /*maxEpochs*/, uint256 toStakerID) external {
        restakeRewards(toStakerID);
    }

    function claimValidatorRewards(uint256 /*maxEpochs*/) external {
        uint256 validatorID = getValidatorID[msg.sender];
        claimRewards(validatorID);
    }

    function claimValidatorCompoundRewards(uint256 /*maxEpochs*/) external {
        uint256 validatorID = getValidatorID[msg.sender];
        restakeRewards(validatorID);
    }

    function prepareToWithdrawStake() external {
        if (false) {
            address(0).transfer(0);
        }
        revert("use SFCv3 undelegate() function");
    }

    function prepareToWithdrawStakePartial(uint256 wrID, uint256 amount) external {
        uint256 validatorID = getValidatorID[msg.sender];
        undelegate(validatorID, wrID, amount);
    }

    function withdrawStake() external {
        if (false) {
            address(0).transfer(0);
        }
        revert("use SFCv3 withdraw() function");
    }

    function prepareToWithdrawDelegation(uint256 /*toStakerID*/) external {
        if (false) {
            address(0).transfer(0);
        }
        revert("use SFCv3 undelegate() function");
    }

    function prepareToWithdrawDelegationPartial(uint256 wrID, uint256 toStakerID, uint256 amount) external {
        undelegate(toStakerID, wrID, amount);
    }

    function withdrawDelegation(uint256 /*toStakerID*/) external {
        if (false) {
            address(0).transfer(0);
        }
        revert("use SFCv3 withdraw() function");
    }

    function partialWithdrawByRequest(uint256) external {
        if (false) {
            address(0).transfer(0);
        }
        revert("use SFCv3 withdraw() function");
    }

    function lockUpStake(uint256 lockDuration) external {
        uint256 validatorID = getValidatorID[msg.sender];
        lockStake(validatorID, lockDuration, getSelfStake(validatorID));
    }

    function lockUpDelegation(uint256 lockDuration, uint256 toStakerID) external {
        lockStake(toStakerID, lockDuration, getStake[msg.sender][toStakerID]);
    }
}
