// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Ownable} from "../ownership/Ownable.sol";
import {Decimal} from "../common/Decimal.sol";
import {SFCBase} from "./SFCBase.sol";
import {NodeDriverAuth} from "./NodeDriverAuth.sol";
import {ConstantsManager} from "./ConstantsManager.sol";
import {GP} from "./GasPriceConstants.sol";
import {Version} from "../version/Version.sol";

/**
 * @dev Stakers contract defines data structure and methods for validators / validators.
 */
contract SFC is SFCBase, Version {
    function _delegate(address implementation) internal {
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    // solhint-disable-next-line no-complex-fallback
    fallback() external payable {
        if (msg.data.length == 0) {
            revert TransfersNotAllowed();
        }
        _delegate(libAddress);
    }

    receive() external payable {
        revert TransfersNotAllowed();
    }

    /*
    Getters
    */

    function getEpochValidatorIDs(uint256 epoch) public view returns (uint256[] memory) {
        return getEpochSnapshot[epoch].validatorIDs;
    }

    function getEpochReceivedStake(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].receivedStake[validatorID];
    }

    function getEpochAccumulatedRewardPerToken(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].accumulatedRewardPerToken[validatorID];
    }

    function getEpochAccumulatedUptime(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].accumulatedUptime[validatorID];
    }

    function getEpochAccumulatedOriginatedTxsFee(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].accumulatedOriginatedTxsFee[validatorID];
    }

    function getEpochOfflineTime(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].offlineTime[validatorID];
    }

    function getEpochOfflineBlocks(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].offlineBlocks[validatorID];
    }

    function getEpochEndBlock(uint256 epoch) public view returns (uint256) {
        return getEpochSnapshot[epoch].endBlock;
    }

    function rewardsStash(address delegator, uint256 validatorID) public view returns (uint256) {
        Rewards memory stash = _rewardsStash[delegator][validatorID];
        return stash.lockupBaseReward + stash.lockupExtraReward + stash.unlockedReward;
    }

    /*
    Constructor
    */

    function initialize(
        uint256 sealedEpoch,
        uint256 _totalSupply,
        address nodeDriver,
        address lib,
        address _c,
        address owner
    ) external initializer {
        Ownable.initialize(owner);
        currentSealedEpoch = sealedEpoch;
        node = NodeDriverAuth(nodeDriver);
        libAddress = lib;
        c = ConstantsManager(_c);
        totalSupply = _totalSupply;
        minGasPrice = GP.initialMinGasPrice();
        getEpochSnapshot[sealedEpoch].endTime = _now();
    }

    function updateLibAddress(address v) external onlyOwner {
        libAddress = v;
    }

    function updateTreasuryAddress(address v) external onlyOwner {
        treasuryAddress = v;
    }

    function updateConstsAddress(address v) external onlyOwner {
        c = ConstantsManager(v);
    }

    function constsAddress() external view returns (address) {
        return address(c);
    }

    function updateVoteBookAddress(address v) external onlyOwner {
        voteBookAddress = v;
    }

    function migrateValidatorPubkeyUniquenessFlag(uint256 start, uint256 end) external {
        for (uint256 vid = start; vid < end; vid++) {
            bytes memory pubkey = getValidatorPubkey[vid];
            if (pubkey.length > 0 && pubkeyHashToValidatorID[keccak256(pubkey)] != vid) {
                if (pubkeyHashToValidatorID[keccak256(pubkey)] != 0) {
                    revert PubkeyUsedByOtherValidator();
                }
                pubkeyHashToValidatorID[keccak256(pubkey)] = vid;
            }
        }
    }

    function updateValidatorPubkey(bytes calldata pubkey) external {
        if (pubkey.length != 66 || pubkey[0] != 0xc0) {
            revert MalformedPubkey();
        }
        uint256 validatorID = getValidatorID[msg.sender];
        if (!_validatorExists(validatorID)) {
            revert ValidatorNotExists();
        }
        if (keccak256(pubkey) == keccak256(getValidatorPubkey[validatorID])) {
            revert PubkeyNotChanged();
        }
        if (pubkeyHashToValidatorID[keccak256(pubkey)] != 0) {
            revert PubkeyUsedByOtherValidator();
        }
        if (validatorPubkeyChanges[validatorID] != 0) {
            revert TooManyPubkeyUpdates();
        }

        validatorPubkeyChanges[validatorID]++;
        pubkeyHashToValidatorID[keccak256(pubkey)] = validatorID;
        getValidatorPubkey[validatorID] = pubkey;
        _syncValidator(validatorID, true);
    }

    function setRedirectionAuthorizer(address v) external onlyOwner {
        if (redirectionAuthorizer == v) {
            revert SameRedirectionAuthorizer();
        }
        redirectionAuthorizer = v;
    }

    event AnnouncedRedirection(address indexed from, address indexed to);

    function announceRedirection(address to) external {
        emit AnnouncedRedirection(msg.sender, to);
    }

    function initiateRedirection(address from, address to) external {
        if (msg.sender != redirectionAuthorizer) {
            revert NotAuthorized();
        }
        if (getRedirection[from] == to) {
            revert AlreadyRedirected();
        }
        if (from == to) {
            revert SameAddress();
        }
        getRedirectionRequest[from] = to;
    }

    function redirect(address to) external {
        address from = msg.sender;
        if (to == address(0)) {
            revert ZeroAddress();
        }
        if (getRedirectionRequest[from] != to) {
            revert RequestNotExists();
        }
        getRedirection[from] = to;
        getRedirectionRequest[from] = address(0);
    }

    /*
    Epoch callbacks
    */

    function _sealEpochOffline(
        EpochSnapshot storage snapshot,
        uint256[] memory validatorIDs,
        uint256[] memory offlineTime,
        uint256[] memory offlineBlocks
    ) internal {
        // mark offline nodes
        for (uint256 i = 0; i < validatorIDs.length; i++) {
            if (
                offlineBlocks[i] > c.offlinePenaltyThresholdBlocksNum() &&
                offlineTime[i] >= c.offlinePenaltyThresholdTime()
            ) {
                _setValidatorDeactivated(validatorIDs[i], OFFLINE_BIT);
                _syncValidator(validatorIDs[i], false);
            }
            // log data
            snapshot.offlineTime[validatorIDs[i]] = offlineTime[i];
            snapshot.offlineBlocks[validatorIDs[i]] = offlineBlocks[i];
        }
    }

    struct SealEpochRewardsCtx {
        uint256[] baseRewardWeights;
        uint256 totalBaseRewardWeight;
        uint256[] txRewardWeights;
        uint256 totalTxRewardWeight;
        uint256 epochFee;
    }

    function _sealEpochRewards(
        uint256 epochDuration,
        EpochSnapshot storage snapshot,
        EpochSnapshot storage prevSnapshot,
        uint256[] memory validatorIDs,
        uint256[] memory uptimes,
        uint256[] memory accumulatedOriginatedTxsFee
    ) internal {
        SealEpochRewardsCtx memory ctx = SealEpochRewardsCtx(
            new uint256[](validatorIDs.length),
            0,
            new uint256[](validatorIDs.length),
            0,
            0
        );

        for (uint256 i = 0; i < validatorIDs.length; i++) {
            uint256 prevAccumulatedTxsFee = prevSnapshot.accumulatedOriginatedTxsFee[validatorIDs[i]];
            uint256 originatedTxsFee = 0;
            if (accumulatedOriginatedTxsFee[i] > prevAccumulatedTxsFee) {
                originatedTxsFee = accumulatedOriginatedTxsFee[i] - prevAccumulatedTxsFee;
            }
            // txRewardWeight = {originatedTxsFee} * {uptime}
            // originatedTxsFee is roughly proportional to {uptime} * {stake}, so the whole formula is roughly
            // {stake} * {uptime} ^ 2
            ctx.txRewardWeights[i] = (originatedTxsFee * uptimes[i]) / epochDuration;
            ctx.totalTxRewardWeight = ctx.totalTxRewardWeight + ctx.txRewardWeights[i];
            ctx.epochFee = ctx.epochFee + originatedTxsFee;
        }

        for (uint256 i = 0; i < validatorIDs.length; i++) {
            // baseRewardWeight = {stake} * {uptime ^ 2}
            ctx.baseRewardWeights[i] =
                (((snapshot.receivedStake[validatorIDs[i]] * uptimes[i]) / epochDuration) * uptimes[i]) /
                epochDuration;
            ctx.totalBaseRewardWeight = ctx.totalBaseRewardWeight + ctx.baseRewardWeights[i];
        }

        for (uint256 i = 0; i < validatorIDs.length; i++) {
            uint256 rawReward = _calcRawValidatorEpochBaseReward(
                epochDuration,
                c.baseRewardPerSecond(),
                ctx.baseRewardWeights[i],
                ctx.totalBaseRewardWeight
            );
            rawReward =
                rawReward +
                _calcRawValidatorEpochTxReward(ctx.epochFee, ctx.txRewardWeights[i], ctx.totalTxRewardWeight);

            uint256 validatorID = validatorIDs[i];
            address validatorAddr = getValidator[validatorID].auth;
            // accounting validator's commission
            uint256 commissionRewardFull = _calcValidatorCommission(rawReward, c.validatorCommission());
            uint256 selfStake = getStake[validatorAddr][validatorID];
            if (selfStake != 0) {
                uint256 lCommissionRewardFull = (commissionRewardFull * getLockedStake(validatorAddr, validatorID)) /
                    selfStake;
                uint256 uCommissionRewardFull = commissionRewardFull - lCommissionRewardFull;
                Rewards memory lCommissionReward = _scaleLockupReward(
                    lCommissionRewardFull,
                    getLockupInfo[validatorAddr][validatorID].duration
                );
                Rewards memory uCommissionReward = _scaleLockupReward(uCommissionRewardFull, 0);
                _rewardsStash[validatorAddr][validatorID] = sumRewards(
                    _rewardsStash[validatorAddr][validatorID],
                    lCommissionReward,
                    uCommissionReward
                );
                getStashedLockupRewards[validatorAddr][validatorID] = sumRewards(
                    getStashedLockupRewards[validatorAddr][validatorID],
                    lCommissionReward,
                    uCommissionReward
                );
            }
            // accounting reward per token for delegators
            uint256 delegatorsReward = rawReward - commissionRewardFull;
            // note: use latest stake for the sake of rewards distribution accuracy, not snapshot.receivedStake
            uint256 receivedStake = getValidator[validatorID].receivedStake;
            uint256 rewardPerToken = 0;
            if (receivedStake != 0) {
                rewardPerToken = (delegatorsReward * Decimal.unit()) / receivedStake;
            }
            snapshot.accumulatedRewardPerToken[validatorID] =
                prevSnapshot.accumulatedRewardPerToken[validatorID] +
                rewardPerToken;

            snapshot.accumulatedOriginatedTxsFee[validatorID] = accumulatedOriginatedTxsFee[i];
            snapshot.accumulatedUptime[validatorID] = prevSnapshot.accumulatedUptime[validatorID] + uptimes[i];
        }

        snapshot.epochFee = ctx.epochFee;
        if (totalSupply > snapshot.epochFee) {
            totalSupply -= snapshot.epochFee;
        } else {
            totalSupply = 0;
        }

        // transfer 10% of fees to treasury
        if (treasuryAddress != address(0)) {
            uint256 feeShare = (ctx.epochFee * c.treasuryFeeShare()) / Decimal.unit();
            _mintNativeToken(feeShare);
            (bool success, ) = treasuryAddress.call{value: feeShare, gas: 1000000}("");
            if (!success) {
                revert TransferFailed();
            }
        }
    }

    function _sealEpochMinGasPrice(uint256 epochDuration, uint256 epochGas) internal {
        // change minGasPrice proportionally to the difference between target and received epochGas
        uint256 targetEpochGas = epochDuration * c.targetGasPowerPerSecond() + 1;
        uint256 gasPriceDeltaRatio = (epochGas * Decimal.unit()) / targetEpochGas;
        uint256 counterweight = c.gasPriceBalancingCounterweight();
        // scale down the change speed (estimate gasPriceDeltaRatio ^ (epochDuration / counterweight))
        gasPriceDeltaRatio =
            (epochDuration * gasPriceDeltaRatio + counterweight * Decimal.unit()) /
            (epochDuration + counterweight);
        // limit the max/min possible delta in one epoch
        gasPriceDeltaRatio = GP.trimGasPriceChangeRatio(gasPriceDeltaRatio);

        // apply the ratio
        uint256 newMinGasPrice = (minGasPrice * gasPriceDeltaRatio) / Decimal.unit();
        // limit the max/min possible minGasPrice
        newMinGasPrice = GP.trimMinGasPrice(newMinGasPrice);
        // apply new minGasPrice
        minGasPrice = newMinGasPrice;
    }

    function _sealEpochAverageUptime(
        uint256 epochDuration,
        EpochSnapshot storage snapshot,
        EpochSnapshot storage prevSnapshot,
        uint256[] memory validatorIDs,
        uint256[] memory uptimes
    ) internal {
        for (uint256 i = 0; i < validatorIDs.length; i++) {
            uint256 validatorID = validatorIDs[i];
            uint256 normalisedUptime = uptimes[i] * (1 << 30)/ epochDuration;
            if (normalisedUptime < 0) {
                normalisedUptime = 0;
            } else if (normalisedUptime > 1 << 30) {
                normalisedUptime = 1 << 30;
            }
            // Assumes that if in the previous snapshot the validator
            // does not exist, the map returns zero.
            int32 n = prevSnapshot.numEpochsAlive[validatorID];
            int64 tmp;
            if (n > 0) { 
                tmp = int64(n-1) * int64(snapshot.averageUptime[validatorID]) + int64(uint64(normalisedUptime));
                if (n > 1)  {
                    tmp += (int64(n) * int64(prevSnapshot.averageUptimeError[validatorID])) / int64(n-1);
                }
                snapshot.averageUptimeError[validatorID] = int32(tmp % int64(n));
                tmp /= int64(n);
            } else {
                tmp = int64(uint64(normalisedUptime));
            }
            if (tmp < 0) {
               tmp = 0;
            } else if (tmp > 1 << 30){
               tmp = 1 << 30;
            }
            snapshot.averageUptime[validatorID] = int32(tmp);
            if (n < c.numEpochsAliveThreshold()) {
                snapshot.numEpochsAlive[validatorID] = n + 1;
            }
        }
    }

    function sealEpoch(
        uint256[] calldata offlineTime,
        uint256[] calldata offlineBlocks,
        uint256[] calldata uptimes,
        uint256[] calldata originatedTxsFee,
        uint256 epochGas
    ) external onlyDriver {
        EpochSnapshot storage snapshot = getEpochSnapshot[currentEpoch()];
        uint256[] memory validatorIDs = snapshot.validatorIDs;

        _sealEpochOffline(snapshot, validatorIDs, offlineTime, offlineBlocks);
        {
            EpochSnapshot storage prevSnapshot = getEpochSnapshot[currentSealedEpoch];
            uint256 epochDuration = 1;
            if (_now() > prevSnapshot.endTime) {
                epochDuration = _now() - prevSnapshot.endTime;
            }
            _sealEpochRewards(epochDuration, snapshot, prevSnapshot, validatorIDs, uptimes, originatedTxsFee);
            _sealEpochMinGasPrice(epochDuration, epochGas);
            _sealEpochAverageUptime(epochDuration, snapshot, prevSnapshot, validatorIDs, uptimes);
        }

        currentSealedEpoch = currentEpoch();
        snapshot.endTime = _now();
        snapshot.endBlock = block.number;
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
            snapshot.totalStake = snapshot.totalStake + receivedStake;
        }
        snapshot.validatorIDs = nextValidatorIDs;
        node.updateMinGasPrice(minGasPrice);
    }
}
