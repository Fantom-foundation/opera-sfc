// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Decimal} from "../common/Decimal.sol";

/**
 * @custom:security-contact security@fantom.foundation
 */
contract ConstantsManager is OwnableUpgradeable {
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
    // The number of epochs that undelegated stake is locked for
    uint256 public withdrawalPeriodEpochs;
    // The number of seconds that undelegated stake is locked for
    uint256 public withdrawalPeriodTime;
    // The base reward per second for validators
    uint256 public baseRewardPerSecond;
    // The number of blocks a validator can be offline before being deactivated
    uint256 public offlinePenaltyThresholdBlocksNum;
    // The number of seconds a validator can be offline before being deactivated
    uint256 public offlinePenaltyThresholdTime;
    // The target gas power per second
    uint256 public targetGasPowerPerSecond;
    // The counterweight for gas price balancing
    uint256 public gasPriceBalancingCounterweight;

    // The number of epochs to calculate the average uptime ratio from, acceptable bound [10, 87600].
    // Is also the minimum number of epochs necessary for deactivation of offline validators.
    uint32 public averageUptimeEpochWindow;

    // Minimum average uptime ratio in fixed-point format; acceptable bounds [0,0.9].
    // Zero to disable validators deactivation by this metric.
    // 0.9 to deactivate validators with average uptime ratio below 90%.
    uint64 public minAverageUptime;

    event MinSelfStakeUpdated(uint256 v);
    event MaxDelegatedRatioUpdated(uint256 v);
    event ValidatorCommissionUpdated(uint256 v);
    event BurntFeeShareUpdated(uint256 v);
    event TreasuryFeeShareUpdated(uint256 v);
    event WithdrawalPeriodEpochsUpdated(uint256 v);
    event WithdrawalPeriodTimeUpdated(uint256 v);
    event BaseRewardPerSecondUpdated(uint256 v);
    event OfflinePenaltyThresholdBlocksNumUpdated(uint256 v);
    event OfflinePenaltyThresholdTimeUpdated(uint256 v);
    event TargetGasPowerPerSecondUpdated(uint256 v);
    event GasPriceBalancingCounterweightUpdated(uint256 v);
    event AverageUptimeEpochWindowUpdated(uint32 v);
    event MinAverageUptimeUpdated(uint64 v);

    /**
     * @dev Given value is too small
     */
    error ValueTooSmall();

    /**
     * @dev Given value is too large
     */
    error ValueTooLarge();

    constructor(address owner) initializer {
        __Ownable_init(owner);
    }

    function updateMinSelfStake(uint256 v) external virtual onlyOwner {
        if (v < 100000 * 1e18) {
            revert ValueTooSmall();
        }
        if (v > 10000000 * 1e18) {
            revert ValueTooLarge();
        }
        minSelfStake = v;
        emit MinSelfStakeUpdated(v);
    }

    function updateMaxDelegatedRatio(uint256 v) external virtual onlyOwner {
        if (v < Decimal.unit()) {
            revert ValueTooSmall();
        }
        if (v > 31 * Decimal.unit()) {
            revert ValueTooLarge();
        }
        maxDelegatedRatio = v;
        emit MaxDelegatedRatioUpdated(v);
    }

    function updateValidatorCommission(uint256 v) external virtual onlyOwner {
        if (v > Decimal.unit() / 2) {
            revert ValueTooLarge();
        }
        validatorCommission = v;
        emit ValidatorCommissionUpdated(v);
    }

    function updateBurntFeeShare(uint256 v) external virtual onlyOwner {
        if (v > Decimal.unit() / 2) {
            revert ValueTooLarge();
        }
        burntFeeShare = v;
        emit BurntFeeShareUpdated(v);
    }

    function updateTreasuryFeeShare(uint256 v) external virtual onlyOwner {
        if (v > Decimal.unit() / 2) {
            revert ValueTooLarge();
        }
        treasuryFeeShare = v;
        emit TreasuryFeeShareUpdated(v);
    }

    function updateWithdrawalPeriodEpochs(uint256 v) external virtual onlyOwner {
        if (v < 2) {
            revert ValueTooSmall();
        }
        if (v > 100) {
            revert ValueTooLarge();
        }
        withdrawalPeriodEpochs = v;
        emit WithdrawalPeriodEpochsUpdated(v);
    }

    function updateWithdrawalPeriodTime(uint256 v) external virtual onlyOwner {
        if (v < 86400) {
            revert ValueTooSmall();
        }
        if (v > 30 * 86400) {
            revert ValueTooLarge();
        }
        withdrawalPeriodTime = v;
        emit WithdrawalPeriodTimeUpdated(v);
    }

    function updateBaseRewardPerSecond(uint256 v) external virtual onlyOwner {
        if (v < 0.5 * 1e18) {
            revert ValueTooSmall();
        }
        if (v > 32 * 1e18) {
            revert ValueTooLarge();
        }
        baseRewardPerSecond = v;
        emit BaseRewardPerSecondUpdated(v);
    }

    function updateOfflinePenaltyThresholdTime(uint256 v) external virtual onlyOwner {
        if (v < 86400) {
            revert ValueTooSmall();
        }
        if (v > 10 * 86400) {
            revert ValueTooLarge();
        }
        offlinePenaltyThresholdTime = v;
        emit OfflinePenaltyThresholdTimeUpdated(v);
    }

    function updateOfflinePenaltyThresholdBlocksNum(uint256 v) external virtual onlyOwner {
        if (v < 100) {
            revert ValueTooSmall();
        }
        if (v > 1000000) {
            revert ValueTooLarge();
        }
        offlinePenaltyThresholdBlocksNum = v;
        emit OfflinePenaltyThresholdBlocksNumUpdated(v);
    }

    function updateTargetGasPowerPerSecond(uint256 v) external virtual onlyOwner {
        if (v < 1000000) {
            revert ValueTooSmall();
        }
        if (v > 500000000) {
            revert ValueTooLarge();
        }
        targetGasPowerPerSecond = v;
        emit TargetGasPowerPerSecondUpdated(v);
    }

    function updateGasPriceBalancingCounterweight(uint256 v) external virtual onlyOwner {
        if (v < 100) {
            revert ValueTooSmall();
        }
        if (v > 10 * 86400) {
            revert ValueTooLarge();
        }
        gasPriceBalancingCounterweight = v;
        emit GasPriceBalancingCounterweightUpdated(v);
    }

    function updateAverageUptimeEpochWindow(uint32 v) external virtual onlyOwner {
        if (v < 10) {
            // needs to be long enough to allow permissible downtime for validators maintenance
            revert ValueTooSmall();
        }
        if (v > 87600) {
            revert ValueTooLarge();
        }
        averageUptimeEpochWindow = v;
        emit AverageUptimeEpochWindowUpdated(v);
    }

    function updateMinAverageUptime(uint64 v) external virtual onlyOwner {
        if (v > ((Decimal.unit() * 9) / 10)) {
            revert ValueTooLarge();
        }
        minAverageUptime = v;
        emit MinAverageUptimeUpdated(v);
    }
}
