// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Decimal} from "../common/Decimal.sol";

/**
 * @custom:security-contact security@fantom.foundation
 */
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
    // the number of epochs that undelegated stake is locked for
    uint256 public withdrawalPeriodEpochs;
    // the number of seconds that undelegated stake is locked for
    uint256 public withdrawalPeriodTime;

    uint256 public baseRewardPerSecond;
    uint256 public offlinePenaltyThresholdBlocksNum;
    uint256 public offlinePenaltyThresholdTime;

    // The number of epochs to calculate the average uptime ratio from, acceptable bound [10, 87600].
    // Is also the minimum number of epochs necessary for deactivation of offline validators.
    uint32 public averageUptimeEpochWindow;

    // Minimum average uptime ratio in fixed-point format; acceptable bounds [0,0.9].
    // Zero to disable validators deactivation by this metric.
    uint64 public minAverageUptime;

    // The address of the recipient that receives issued tokens
    // as a counterparty to the burnt FTM tokens
    address public issuedTokensRecipient;

    /**
     * @dev Given value is too small
     */
    error ValueTooSmall();

    /**
     * @dev Given value is too large
     */
    error ValueTooLarge();

    constructor(address owner) Ownable(owner) {}

    function updateMinSelfStake(uint256 v) external virtual onlyOwner {
        if (v < 100000 * Decimal.unit()) {
            revert ValueTooSmall();
        }
        if (v > 10000000 * Decimal.unit()) {
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
        if (v + treasuryFeeShare > Decimal.unit()) {
            revert ValueTooLarge();
        }
        burntFeeShare = v;
    }

    function updateTreasuryFeeShare(uint256 v) external virtual onlyOwner {
        if (v + burntFeeShare > Decimal.unit()) {
            revert ValueTooLarge();
        }
        treasuryFeeShare = v;
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
        if (v > 32 * Decimal.unit()) {
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

    function updateAverageUptimeEpochWindow(uint32 v) external virtual onlyOwner {
        if (v < 10) {
            // needs to be long enough to allow permissible downtime for validators maintenance
            revert ValueTooSmall();
        }
        if (v > 87600) {
            revert ValueTooLarge();
        }
        averageUptimeEpochWindow = v;
    }

    function updateMinAverageUptime(uint64 v) external virtual onlyOwner {
        if (v > ((Decimal.unit() * 9) / 10)) {
            revert ValueTooLarge();
        }
        minAverageUptime = v;
    }

    function updateIssuedTokensRecipient(address v) external virtual onlyOwner {
        issuedTokensRecipient = v;
    }
}
