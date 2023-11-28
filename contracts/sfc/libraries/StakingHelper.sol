pragma solidity ^0.5.0;

import "../SFCState.sol";
library StakingHelper {
    using SafeMath for uint256;
    
    function _getStashedPenaltyForUnlock(
        mapping(address => mapping(uint256 => SFCState.Penalty[])) storage getPenaltyInfo,
        address delegator,
        uint256 toValidatorID,
        uint256 unlockAmount
    ) internal returns(uint256 stashedPenalty) {
        SFCState.Penalty[] storage penalties = getPenaltyInfo[delegator][toValidatorID];
        uint256 length = penalties.length;
        for(uint256 i=0; i<length; i++) {
            if(penalties[i].amountLockedForPenalty <= unlockAmount) {
                stashedPenalty = stashedPenalty.add(penalties[i].penalty);
                penalties[i].penalty = 0;
                penalties[i].amountLockedForPenalty = 0;
            } else {
                uint256 penaltyShare = penalties[i].penalty.mul(unlockAmount).div(penalties[i].amountLockedForPenalty);
                stashedPenalty = stashedPenalty.add(penaltyShare);
                penalties[i].penalty = penalties[i].penalty.sub(penaltyShare);
                penalties[i].amountLockedForPenalty = penalties[i].amountLockedForPenalty.sub(unlockAmount);
            }
        }
    }

    function _movePenalties(
        mapping(address => mapping(uint256 => SFCState.Penalty[])) storage getPenaltyInfo,
        address delegator,
        uint256 toValidatorID,
        SFCState.Penalty[] memory penalties
    ) internal {
        uint256 length = penalties.length;
        for(uint256 i=0; i<length; i++) {
            getPenaltyInfo[delegator][toValidatorID].push(penalties[i]);
        }
    }

    function _splitPenalties(
        SFCState.Penalty[] memory penalties,
        uint256 splitAmount
    ) internal returns(SFCState.Penalty[] memory results) {
        uint256 length = penalties.length;
        results = new SFCState.Penalty[](length);
        for(uint256 i=0; i<length; i++) {
            SFCState.Penalty memory penalty = penalties[i];
            if(penalty.amountLockedForPenalty <= splitAmount) {
                results[i].amountLockedForPenalty = splitAmount;
                results[i].penalty = penalty.penalty;
            } else {
                results[i].amountLockedForPenalty = penalty.amountLockedForPenalty.sub(splitAmount);
                results[i].penalty = penalty.penalty.mul(splitAmount).div(penalty.amountLockedForPenalty);
            }
            results[i].penaltyEnd = penalty.penaltyEnd;
        }
    }
}

