pragma solidity ^0.5.0;

import "./SFC.sol";

// LegacySfcWrapper adds the legacy SFCv2 functions for backward compatibility
contract LegacySfcWrapper is SFC {
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

    function lockedDelegations(address delegator, uint256 toStakerID) public view returns (uint256 fromEpoch, uint256 endTime, uint256 duration) {
        LockedDelegation memory l = getLockupInfo[delegator][toStakerID];
        return (l.fromEpoch, l.endTime, l.duration);
    }

    function lockedStakes(uint256 stakerID) external view returns (uint256 fromEpoch, uint256 endTime, uint256 duration) {
        return lockedDelegations(getValidator[stakerID].auth, stakerID);
    }
}
