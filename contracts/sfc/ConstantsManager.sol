pragma solidity ^0.5.0;

import "../ownership/Ownable.sol";
import "../common/Decimal.sol";

contract ConstantsManager is Ownable {
    // Minimum amount of stake for a validator, i.e., 500000 FTM
    uint256 public minSelfStake;
    // Maximum ratio of delegations a validator can have, say, 15 times of self-stake
    uint256 public maxDelegatedRatio;
    // The commission fee in percentage a validator will get from a delegation, e.g., 15%
    uint256 public validatorCommission;
    // The percentage of fees to burn, e.g., 20%
    uint256 public burntFeeShare;
    // The percentage of fees to transfer to treasury address, e.g., 10%
    uint256 public treasuryFeeShare;
    // The ratio of the reward rate at base rate (no lock), e.g., 30%
    uint256 public unlockedRewardRatio;
    // The minimum duration of a stake/delegation lockup, e.g. 2 weeks
    uint256 public minLockupDuration;
    // The maximum duration of a stake/delegation lockup, e.g. 1 year
    uint256 public maxLockupDuration;
    // the number of epochs that undelegated stake is locked for
    uint256 public withdrawalPeriodEpochs;
    // the number of seconds that undelegated stake is locked for
    uint256 public withdrawalPeriodTime;

    uint256 public baseRewardPerSecond;
    uint256 public offlinePenaltyThresholdBlocksNum;
    uint256 public offlinePenaltyThresholdTime;
    uint256 public targetGasPowerPerSecond;
    uint256 public gasPriceBalancingCounterweight;

    function initialize() external initializer {
        Ownable.initialize(msg.sender);
    }

    function updateMinSelfStake(uint256 v) onlyOwner external {
        require(v <= 1000000000 * 1e18, "too large value");
        minSelfStake = v;
    }

    function updateMaxDelegatedRatio(uint256 v) onlyOwner external {
        require(v >= Decimal.unit(), "too small value");
        require(v <= 1000000 * Decimal.unit(), "too large value");
        maxDelegatedRatio = v;
    }

    function updateValidatorCommission(uint256 v) onlyOwner external {
        require(v <= Decimal.unit(), "too large value");
        validatorCommission = v;
    }

    function updateBurntFeeShare(uint256 v) onlyOwner external {
        require(v <= Decimal.unit(), "too large value");
        burntFeeShare = v;
    }

    function updateTreasuryFeeShare(uint256 v) onlyOwner external {
        require(v <= Decimal.unit(), "too large value");
        treasuryFeeShare = v;
    }

    function updateUnlockedRewardRatio(uint256 v) onlyOwner external {
        require(v <= Decimal.unit(), "too large value");
        unlockedRewardRatio = v;
    }

    function updateMinLockupDuration(uint256 v) onlyOwner external {
        require(v >= 43200, "too small value");
        require(v <= 2147483648, "too large value");
        minLockupDuration = v;
    }

    function updateMaxLockupDuration(uint256 v) onlyOwner external {
        require(v >= minLockupDuration, "too small value");
        require(v <= 2147483648, "too large value");
        maxLockupDuration = v;
    }

    function updateWithdrawalPeriodEpochs(uint256 v) onlyOwner external {
        require(v >= 1, "too small value");
        require(v <= 100000000, "too large value");
        withdrawalPeriodEpochs = v;
    }

    function updateWithdrawalPeriodTime(uint256 v) onlyOwner external {
        require(v >= 3600, "too small value");
        require(v <= 2147483648, "too large value");
        withdrawalPeriodTime = v;
    }

    function updateBaseRewardPerSecond(uint256 v) onlyOwner external {
        require(v <= 32.967977168935185184 * 1e18, "too large reward per second");
        baseRewardPerSecond = v;
    }

    function updateOfflinePenaltyThresholdTime(uint256 v) onlyOwner external {
        require(v >= 60 minutes, "too small value");
        offlinePenaltyThresholdTime = v;
    }

    function updateOfflinePenaltyThresholdBlocksNum(uint256 v) onlyOwner external {
        require(v >= 10, "too small value");
        offlinePenaltyThresholdBlocksNum = v;
    }

    function updateTargetGasPowerPerSecond(uint256 v) onlyOwner external {
        require(v >= 1000, "too small value");
        require(v <= 500000000, "too large value");
        targetGasPowerPerSecond = v;
    }

    function updateGasPriceBalancingCounterweight(uint256 v) onlyOwner external {
        require(v >= 1, "too small value");
        require(v <= 1000000000, "too large value");
        gasPriceBalancingCounterweight = v;
    }
}
