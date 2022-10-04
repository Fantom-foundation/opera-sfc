pragma solidity ^0.5.0;

import "./GasPriceConstants.sol";
import "../version/Version.sol";
import "./SFCBase.sol";

/**
 * @dev Stakers contract defines data structure and methods for validators / validators.
 */
contract SFC is SFCBase, Version {
    function _delegate(address implementation) internal {
        assembly {
        // Copy msg.data. We take full control of memory in this inline assembly
        // block because it will not return to Solidity code. We overwrite the
        // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize)

        // Call the implementation.
        // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas, implementation, 0, calldatasize, 0, 0)

        // Copy the returned data.
            returndatacopy(0, 0, returndatasize)

            switch result
            // delegatecall returns 0 on error.
            case 0 {revert(0, returndatasize)}
            default {return (0, returndatasize)}
        }
    }

    function() payable external {
        _delegate(libAddress);
    }

    event UpdatedBaseRewardPerSec(uint256 value);
    event UpdatedOfflinePenaltyThreshold(uint256 blocksNum, uint256 period);

    /*
    Constructor
    */

    function initialize(uint256 sealedEpoch, uint256 _totalSupply, address nodeDriver, address lib, address _c, address owner) external initializer {
        Ownable.initialize(owner);
        currentSealedEpoch = sealedEpoch;
        node = NodeDriverAuth(nodeDriver);
        libAddress = lib;
        c = ConstantsManager(_c);
        totalSupply = _totalSupply;
        minGasPrice = GP.initialMinGasPrice();
        getEpochSnapshot[sealedEpoch].endTime = _now();
    }

    function updateStakeTokenizerAddress(address addr) onlyOwner external {
        stakeTokenizerAddress = addr;
    }

    function updateLibAddress(address v) onlyOwner external {
        libAddress = v;
    }

    function updateTreasuryAddress(address v) onlyOwner external {
        treasuryAddress = v;
    }

    function updateConstsAddress(address v) onlyOwner external {
        c = ConstantsManager(v);
    }

    function constsAddress() external view returns (address) {
        return address(c);
    }

    /*
    Epoch callbacks
    */

    function _sealEpoch_offline(EpochSnapshot storage snapshot, uint256[] memory validatorIDs, uint256[] memory offlineTime, uint256[] memory offlineBlocks) internal {
        // mark offline nodes
        for (uint256 i = 0; i < validatorIDs.length; i++) {
            if (offlineBlocks[i] > c.offlinePenaltyThresholdBlocksNum() && offlineTime[i] >= c.offlinePenaltyThresholdTime()) {
                _setValidatorDeactivated(validatorIDs[i], OFFLINE_BIT);
                _syncValidator(validatorIDs[i], false);
            }
            // log data
            snapshot.offlineTime[validatorIDs[i]] = offlineTime[i];
            snapshot.offlineBlocks[validatorIDs[i]] = offlineBlocks[i];
        }
    }

    struct _SealEpochRewardsCtx {
        uint256[] baseRewardWeights;
        uint256 totalBaseRewardWeight;
        uint256[] txRewardWeights;
        uint256 totalTxRewardWeight;
        uint256 epochFee;
    }

    function _sealEpoch_rewards(uint256 epochDuration, EpochSnapshot storage snapshot, EpochSnapshot storage prevSnapshot, uint256[] memory validatorIDs, uint256[] memory uptimes, uint256[] memory accumulatedOriginatedTxsFee) internal {
        _SealEpochRewardsCtx memory ctx = _SealEpochRewardsCtx(new uint[](validatorIDs.length), 0, new uint[](validatorIDs.length), 0, 0);

        for (uint256 i = 0; i < validatorIDs.length; i++) {
            uint256 prevAccumulatedTxsFee = prevSnapshot.accumulatedOriginatedTxsFee[validatorIDs[i]];
            uint256 originatedTxsFee = 0;
            if (accumulatedOriginatedTxsFee[i] > prevAccumulatedTxsFee) {
                originatedTxsFee = accumulatedOriginatedTxsFee[i] - prevAccumulatedTxsFee;
            }
            // txRewardWeight = {originatedTxsFee} * {uptime}
            // originatedTxsFee is roughly proportional to {uptime} * {stake}, so the whole formula is roughly
            // {stake} * {uptime} ^ 2
            ctx.txRewardWeights[i] = originatedTxsFee * uptimes[i] / epochDuration;
            ctx.totalTxRewardWeight = ctx.totalTxRewardWeight.add(ctx.txRewardWeights[i]);
            ctx.epochFee = ctx.epochFee.add(originatedTxsFee);
        }

        for (uint256 i = 0; i < validatorIDs.length; i++) {
            // baseRewardWeight = {stake} * {uptime ^ 2}
            ctx.baseRewardWeights[i] = (((snapshot.receivedStake[validatorIDs[i]] * uptimes[i]) / epochDuration) * uptimes[i]) / epochDuration;
            ctx.totalBaseRewardWeight = ctx.totalBaseRewardWeight.add(ctx.baseRewardWeights[i]);
        }

        for (uint256 i = 0; i < validatorIDs.length; i++) {
            uint256 rawReward = _calcRawValidatorEpochBaseReward(epochDuration, c.baseRewardPerSecond(), ctx.baseRewardWeights[i], ctx.totalBaseRewardWeight);
            rawReward = rawReward.add(_calcRawValidatorEpochTxReward(ctx.epochFee, ctx.txRewardWeights[i], ctx.totalTxRewardWeight));

            uint256 validatorID = validatorIDs[i];
            address validatorAddr = getValidator[validatorID].auth;
            // accounting validator's commission
            uint256 commissionRewardFull = _calcValidatorCommission(rawReward, c.validatorCommission());
            uint256 selfStake = getStake[validatorAddr][validatorID];
            if (selfStake != 0) {
                uint256 lCommissionRewardFull = (commissionRewardFull * getLockedStake(validatorAddr, validatorID)) / selfStake;
                uint256 uCommissionRewardFull = commissionRewardFull - lCommissionRewardFull;
                Rewards memory lCommissionReward = _scaleLockupReward(lCommissionRewardFull, getLockupInfo[validatorAddr][validatorID].duration);
                Rewards memory uCommissionReward = _scaleLockupReward(uCommissionRewardFull, 0);
                _rewardsStash[validatorAddr][validatorID] = sumRewards(_rewardsStash[validatorAddr][validatorID], lCommissionReward, uCommissionReward);
                getStashedLockupRewards[validatorAddr][validatorID] = sumRewards(getStashedLockupRewards[validatorAddr][validatorID], lCommissionReward, uCommissionReward);
            }
            // accounting reward per token for delegators
            uint256 delegatorsReward = rawReward - commissionRewardFull;
            // note: use latest stake for the sake of rewards distribution accuracy, not snapshot.receivedStake
            uint256 receivedStake = getValidator[validatorID].receivedStake;
            uint256 rewardPerToken = 0;
            if (receivedStake != 0) {
                rewardPerToken = (delegatorsReward * Decimal.unit()) / receivedStake;
            }
            snapshot.accumulatedRewardPerToken[validatorID] = prevSnapshot.accumulatedRewardPerToken[validatorID] + rewardPerToken;

            snapshot.accumulatedOriginatedTxsFee[validatorID] = accumulatedOriginatedTxsFee[i];
            snapshot.accumulatedUptime[validatorID] = prevSnapshot.accumulatedUptime[validatorID] + uptimes[i];
        }

        snapshot.epochFee = ctx.epochFee;
        snapshot.totalBaseRewardWeight = ctx.totalBaseRewardWeight;
        snapshot.totalTxRewardWeight = ctx.totalTxRewardWeight;
        if (totalSupply > snapshot.epochFee) {
            totalSupply -= snapshot.epochFee;
        } else {
            totalSupply = 0;
        }

        // transfer 10% of fees to treasury
        if (treasuryAddress != address(0)) {
            uint256 feeShare = ctx.epochFee * c.treasuryFeeShare() / Decimal.unit();
            _mintNativeToken(feeShare);
            treasuryAddress.call.value(feeShare)("");
        }
    }


    function _sealEpoch_minGasPrice(uint256 epochDuration, uint256 epochGas) internal {
        // change minGasPrice proportionally to the difference between target and received epochGas
        uint256 targetEpochGas = epochDuration * c.targetGasPowerPerSecond() + 1;
        uint256 gasPriceDeltaRatio = epochGas * Decimal.unit() / targetEpochGas;
        uint256 counterweight = c.gasPriceBalancingCounterweight();
        // scale down the change speed (estimate gasPriceDeltaRatio ^ (epochDuration / counterweight))
        gasPriceDeltaRatio = (epochDuration * gasPriceDeltaRatio + counterweight * Decimal.unit()) / (epochDuration + counterweight);
        // limit the max/min possible delta in one epoch
        gasPriceDeltaRatio = GP.trimGasPriceChangeRatio(gasPriceDeltaRatio);

        // apply the ratio
        uint256 newMinGasPrice = minGasPrice * gasPriceDeltaRatio / Decimal.unit();
        // limit the max/min possible minGasPrice
        newMinGasPrice = GP.trimMinGasPrice(newMinGasPrice);
        // apply new minGasPrice
        minGasPrice = newMinGasPrice;
    }

    function sealEpoch(uint256[] calldata offlineTime, uint256[] calldata offlineBlocks, uint256[] calldata uptimes, uint256[] calldata originatedTxsFee, uint256 epochGas) external onlyDriver {
        EpochSnapshot storage snapshot = getEpochSnapshot[currentEpoch()];
        uint256[] memory validatorIDs = snapshot.validatorIDs;

        _sealEpoch_offline(snapshot, validatorIDs, offlineTime, offlineBlocks);
        {
            EpochSnapshot storage prevSnapshot = getEpochSnapshot[currentSealedEpoch];
            uint256 epochDuration = 1;
            if (_now() > prevSnapshot.endTime) {
                epochDuration = _now() - prevSnapshot.endTime;
            }
            _sealEpoch_rewards(epochDuration, snapshot, prevSnapshot, validatorIDs, uptimes, originatedTxsFee);
            _sealEpoch_minGasPrice(epochDuration, epochGas);
        }

        currentSealedEpoch = currentEpoch();
        snapshot.endTime = _now();
        snapshot.baseRewardPerSecond = c.baseRewardPerSecond();
        snapshot.totalSupply = totalSupply;
    }

    function sealEpochValidators(uint256[] calldata nextValidatorIDs) external onlyDriver {
        EpochSnapshot storage snapshot = getEpochSnapshot[currentEpoch()];
        // fill data for the next snapshot
        for (uint256 i = 0; i < nextValidatorIDs.length; i++) {
            uint256 validatorID = nextValidatorIDs[i];
            uint256 receivedStake = getValidator[validatorID].receivedStake;
            snapshot.receivedStake[validatorID] = receivedStake;
            snapshot.totalStake = snapshot.totalStake.add(receivedStake);
        }
        snapshot.validatorIDs = nextValidatorIDs;
        node.updateMinGasPrice(minGasPrice);
    }
}
