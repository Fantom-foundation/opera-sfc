// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Ownable} from "../ownership/Ownable.sol";
import {Decimal} from "../common/Decimal.sol";

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
    // The ratio of the reward rate, e.g., 30%
    uint256 public rewardRatio;
    // the number of epochs that undelegated stake is locked for
    uint256 public withdrawalPeriodEpochs;
    // the number of seconds that undelegated stake is locked for
    uint256 public withdrawalPeriodTime;

    uint256 public baseRewardPerSecond;
    uint256 public offlinePenaltyThresholdBlocksNum;
    uint256 public offlinePenaltyThresholdTime;
    uint256 public targetGasPowerPerSecond;
    uint256 public gasPriceBalancingCounterweight;

    /**
     * @dev Given value is too small
     */
    error ValueTooSmall();

    /**
     * @dev Given value is too large
     */
    error ValueTooLarge();

    function initialize() external initializer {
        Ownable.initialize(msg.sender);
    }

    function updateMinSelfStake(uint256 v) external virtual onlyOwner {
        if (v < 100000 * 1e18) {
            revert ValueTooSmall();
        }
        if (v > 10000000 * 1e18) {
            revert ValueTooLarge();
        }
        minSelfStake = v;
    }

    function updateMaxDelegatedRatio(uint256 v) external virtual onlyOwner {
        if (v < Decimal.unit()) {
            revert ValueTooSmall();
        }
        if (v > 31 * Decimal.unit()) {
            revert ValueTooLarge();
        }
        maxDelegatedRatio = v;
    }

    function updateValidatorCommission(uint256 v) external virtual onlyOwner {
        if (v > Decimal.unit() / 2) {
            revert ValueTooLarge();
        }
        validatorCommission = v;
    }

    function updateBurntFeeShare(uint256 v) external virtual onlyOwner {
        if (v > Decimal.unit() / 2) {
            revert ValueTooLarge();
        }
        burntFeeShare = v;
    }

    function updateTreasuryFeeShare(uint256 v) external virtual onlyOwner {
        if (v > Decimal.unit() / 2) {
            revert ValueTooLarge();
        }
        treasuryFeeShare = v;
    }

    function updateRewardRatio(uint256 v) external virtual onlyOwner {
        if (v < (5 * Decimal.unit()) / 100) {
            revert ValueTooSmall();
        }
        if (v > Decimal.unit() / 2) {
            revert ValueTooLarge();
        }
        rewardRatio = v;
    }

    function updateWithdrawalPeriodEpochs(uint256 v) external virtual onlyOwner {
        if (v < 2) {
            revert ValueTooSmall();
        }
        if (v > 100) {
            revert ValueTooLarge();
        }
        withdrawalPeriodEpochs = v;
    }

    function updateWithdrawalPeriodTime(uint256 v) external virtual onlyOwner {
        if (v < 86400) {
            revert ValueTooSmall();
        }
        if (v > 30 * 86400) {
            revert ValueTooLarge();
        }
        withdrawalPeriodTime = v;
    }

    function updateBaseRewardPerSecond(uint256 v) external virtual onlyOwner {
        if (v < 0.5 * 1e18) {
            revert ValueTooSmall();
        }
        if (v > 32 * 1e18) {
            revert ValueTooLarge();
        }
        baseRewardPerSecond = v;
    }

    function updateOfflinePenaltyThresholdTime(uint256 v) external virtual onlyOwner {
        if (v < 86400) {
            revert ValueTooSmall();
        }
        if (v > 10 * 86400) {
            revert ValueTooLarge();
        }
        offlinePenaltyThresholdTime = v;
    }

    function updateOfflinePenaltyThresholdBlocksNum(uint256 v) external virtual onlyOwner {
        if (v < 100) {
            revert ValueTooSmall();
        }
        if (v > 1000000) {
            revert ValueTooLarge();
        }
        offlinePenaltyThresholdBlocksNum = v;
    }

    function updateTargetGasPowerPerSecond(uint256 v) external virtual onlyOwner {
        if (v < 1000000) {
            revert ValueTooSmall();
        }
        if (v > 500000000) {
            revert ValueTooLarge();
        }
        targetGasPowerPerSecond = v;
    }

    function updateGasPriceBalancingCounterweight(uint256 v) external virtual onlyOwner {
        if (v < 100) {
            revert ValueTooSmall();
        }
        if (v > 10 * 86400) {
            revert ValueTooLarge();
        }
        gasPriceBalancingCounterweight = v;
    }
}
