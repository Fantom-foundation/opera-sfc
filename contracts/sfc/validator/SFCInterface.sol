pragma solidity ^0.5.0;

interface SFCInterface {

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
        bytes pubkey;
    }

    struct UnstakingRequest {
        uint256 epoch;
        uint256 time;
        uint256 amount;
    }

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

    struct _SealEpochRewardsCtx {
        uint256[] baseRewardWeights;
        uint256 totalBaseRewardWeight;
        uint256[] txRewardWeights;
        uint256 totalTxRewardWeight;
        uint256 epochDuration;
        uint256 epochFee;
    }
}
