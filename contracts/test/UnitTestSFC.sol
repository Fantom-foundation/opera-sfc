// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Decimal} from "../common/Decimal.sol";
import {SFC} from "../sfc/SFC.sol";
import {SFCBase} from "../sfc/SFCBase.sol";
import {SFCLib} from "../sfc/SFCLib.sol";
import {IErrors} from "../IErrors.sol";
import {NodeDriverAuth} from "../sfc/NodeDriverAuth.sol";
import {NodeDriver} from "../sfc/NodeDriver.sol";
import {UnitTestConstantsManager} from "./UnitTestConstantsManager.sol";

contract UnitTestSFCBase {
    uint256 internal time;
    bool public allowedNonNodeCalls;

    function rebaseTime() external {
        time = block.timestamp;
    }

    function advanceTime(uint256 diff) external {
        time += diff;
    }

    function getTime() external view returns (uint256) {
        return time;
    }

    function getBlockTime() external view returns (uint256) {
        return block.timestamp;
    }

    function enableNonNodeCalls() external {
        allowedNonNodeCalls = true;
    }

    function disableNonNodeCalls() external {
        allowedNonNodeCalls = false;
    }
}

contract UnitTestSFC is SFC, UnitTestSFCBase {
    function _now() internal view override returns (uint256) {
        return time;
    }

    function isNode(address addr) internal view override returns (bool) {
        if (allowedNonNodeCalls) {
            return true;
        }
        return SFCBase.isNode(addr);
    }
}

contract UnitTestSFCLib is SFCLib, UnitTestSFCBase {
    function highestLockupEpoch(address delegator, uint256 validatorID) external view returns (uint256) {
        return _highestLockupEpoch(delegator, validatorID);
    }

    function _now() internal view override returns (uint256) {
        return time;
    }

    function isNode(address addr) internal view override returns (bool) {
        if (allowedNonNodeCalls) {
            return true;
        }
        return SFCBase.isNode(addr);
    }

    function _getAvgEpochStep(uint256) internal pure override returns (uint256) {
        return 1;
    }

    function _getAvgUptime(uint256, uint256 duration, uint256) internal pure override returns (uint256) {
        return duration;
    }
}

contract UnitTestNetworkInitializer {
    function initializeAll(
        uint256 sealedEpoch,
        uint256 totalSupply,
        address payable _sfc,
        address _lib,
        address _auth,
        address _driver,
        address _evmWriter,
        address _owner
    ) external {
        NodeDriver(_driver).initialize(_auth, _evmWriter);
        NodeDriverAuth(_auth).initialize(_sfc, _driver, _owner);

        UnitTestConstantsManager consts = new UnitTestConstantsManager();
        consts.initialize();
        consts.updateMinSelfStake(0.3175000 * 1e18);
        consts.updateMaxDelegatedRatio(16 * Decimal.unit());
        consts.updateValidatorCommission((15 * Decimal.unit()) / 100);
        consts.updateBurntFeeShare((20 * Decimal.unit()) / 100);
        consts.updateTreasuryFeeShare((10 * Decimal.unit()) / 100);
        consts.updateUnlockedRewardRatio((30 * Decimal.unit()) / 100);
        consts.updateMinLockupDuration(86400 * 14);
        consts.updateMaxLockupDuration(86400 * 365);
        consts.updateWithdrawalPeriodEpochs(3);
        consts.updateWithdrawalPeriodTime(60 * 60 * 24 * 7);
        consts.updateBaseRewardPerSecond(6183414351851851852);
        consts.updateOfflinePenaltyThresholdTime(3 days);
        consts.updateOfflinePenaltyThresholdBlocksNum(1000);
        consts.updateTargetGasPowerPerSecond(2000000);
        consts.updateGasPriceBalancingCounterweight(6 * 60 * 60);
        consts.transferOwnership(_owner);

        SFCUnitTestI(_sfc).initialize(sealedEpoch, totalSupply, _auth, _lib, address(consts), _owner);
    }
}

interface SFCUnitTestI is IErrors {
    function currentSealedEpoch() external view returns (uint256);

    function getEpochSnapshot(
        uint256
    )
        external
        view
        returns (
            uint256 endTime,
            uint256 endBlock,
            uint256 epochFee,
            uint256 totalBaseRewardWeight,
            uint256 totalTxRewardWeight,
            uint256 _baseRewardPerSecond,
            uint256 totalStake,
            uint256 totalSupply
        );

    function getLockupInfo(
        address,
        uint256
    ) external view returns (uint256 lockedStake, uint256 fromEpoch, uint256 endTime, uint256 duration);

    function getStake(address, uint256) external view returns (uint256);

    function getStashedLockupRewards(
        address,
        uint256
    ) external view returns (uint256 lockupExtraReward, uint256 lockupBaseReward, uint256 unlockedReward);

    function getValidator(
        uint256
    )
        external
        view
        returns (
            uint256 status,
            uint256 deactivatedTime,
            uint256 deactivatedEpoch,
            uint256 receivedStake,
            uint256 createdEpoch,
            uint256 createdTime,
            address auth
        );

    function getValidatorID(address) external view returns (uint256);

    function getValidatorPubkey(uint256) external view returns (bytes memory);

    function getWithdrawalRequest(
        address,
        uint256,
        uint256
    ) external view returns (uint256 epoch, uint256 time, uint256 amount);

    function isOwner() external view returns (bool);

    function lastValidatorID() external view returns (uint256);

    function minGasPrice() external view returns (uint256);

    function owner() external view returns (address);

    function renounceOwnership() external;

    function slashingRefundRatio(uint256) external view returns (uint256);

    function stashedRewardsUntilEpoch(address, uint256) external view returns (uint256);

    function targetGasPowerPerSecond() external view returns (uint256);

    function totalActiveStake() external view returns (uint256);

    function totalSlashedStake() external view returns (uint256);

    function totalStake() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function transferOwnership(address newOwner) external;

    function treasuryAddress() external view returns (address);

    function version() external pure returns (bytes3);

    function currentEpoch() external view returns (uint256);

    function updateConstsAddress(address v) external;

    function constsAddress() external view returns (address);

    function getEpochValidatorIDs(uint256 epoch) external view returns (uint256[] memory);

    function getEpochReceivedStake(uint256 epoch, uint256 validatorID) external view returns (uint256);

    function getEpochAccumulatedRewardPerToken(uint256 epoch, uint256 validatorID) external view returns (uint256);

    function getEpochAccumulatedUptime(uint256 epoch, uint256 validatorID) external view returns (uint256);

    function getEpochAccumulatedOriginatedTxsFee(uint256 epoch, uint256 validatorID) external view returns (uint256);

    function getEpochOfflineTime(uint256 epoch, uint256 validatorID) external view returns (uint256);

    function getEpochOfflineBlocks(uint256 epoch, uint256 validatorID) external view returns (uint256);

    function getEpochEndBlock(uint256 epoch) external view returns (uint256);

    function rewardsStash(address delegator, uint256 validatorID) external view returns (uint256);

    function getLockedStake(address delegator, uint256 toValidatorID) external view returns (uint256);

    function createValidator(bytes calldata pubkey) external payable;

    function getSelfStake(uint256 validatorID) external view returns (uint256);

    function delegate(uint256 toValidatorID) external payable;

    function undelegate(uint256 toValidatorID, uint256 wrID, uint256 amount) external;

    function isSlashed(uint256 validatorID) external view returns (bool);

    function withdraw(uint256 toValidatorID, uint256 wrID) external;

    function deactivateValidator(uint256 validatorID, uint256 status) external;

    function pendingRewards(address delegator, uint256 toValidatorID) external view returns (uint256);

    function stashRewards(address delegator, uint256 toValidatorID) external;

    function claimRewards(uint256 toValidatorID) external;

    function restakeRewards(uint256 toValidatorID) external;

    function offlinePenaltyThreshold() external view returns (uint256 blocksNum, uint256 time);

    function updateBaseRewardPerSecond(uint256 value) external;

    function updateOfflinePenaltyThreshold(uint256 blocksNum, uint256 time) external;

    function updateSlashingRefundRatio(uint256 validatorID, uint256 refundRatio) external;

    function updateTreasuryAddress(address v) external;

    function burnFTM(uint256 amount) external;

    function sealEpoch(
        uint256[] calldata offlineTime,
        uint256[] calldata offlineBlocks,
        uint256[] calldata uptimes,
        uint256[] calldata originatedTxsFee,
        uint256 epochGas
    ) external;

    function sealEpochValidators(uint256[] calldata nextValidatorIDs) external;

    function isLockedUp(address delegator, uint256 toValidatorID) external view returns (bool);

    function getUnlockedStake(address delegator, uint256 toValidatorID) external view returns (uint256);

    function lockStake(uint256 toValidatorID, uint256 lockupDuration, uint256 amount) external;

    function relockStake(uint256 toValidatorID, uint256 lockupDuration, uint256 amount) external;

    function unlockStake(uint256 toValidatorID, uint256 amount) external returns (uint256);

    function initialize(
        uint256 sealedEpoch,
        uint256 _totalSupply,
        address nodeDriver,
        address lib,
        address consts,
        address _owner
    ) external;

    function setGenesisValidator(
        address auth,
        uint256 validatorID,
        bytes calldata pubkey,
        uint256 status,
        uint256 createdEpoch,
        uint256 createdTime,
        uint256 deactivatedEpoch,
        uint256 deactivatedTime
    ) external;

    function setGenesisDelegation(
        address delegator,
        uint256 toValidatorID,
        uint256 stake,
        uint256 lockedStake,
        uint256 lockupFromEpoch,
        uint256 lockupEndTime,
        uint256 lockupDuration,
        uint256 earlyUnlockPenalty,
        uint256 rewards
    ) external;

    function _syncValidator(uint256 validatorID, bool syncPubkey) external;

    function getTime() external view returns (uint256);

    function getBlockTime() external view returns (uint256);

    function rebaseTime() external;

    function advanceTime(uint256) external;

    function highestLockupEpoch(address, uint256) external view returns (uint256);

    function enableNonNodeCalls() external;

    function disableNonNodeCalls() external;

    function allowedNonNodeCalls() external view returns (bool);

    function updateVoteBookAddress(address v) external;

    function voteBookAddress() external view returns (address);
}
