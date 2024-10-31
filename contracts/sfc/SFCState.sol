// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Ownable} from "../ownership/Ownable.sol";
import {Initializable} from "../common/Initializable.sol";
import {NodeDriverAuth} from "./NodeDriverAuth.sol";
import {ConstantsManager} from "./ConstantsManager.sol";

contract SFCState is Initializable, Ownable {
    /**
     * @dev The staking for validation
     */
    struct Validator {
        uint256 status;
        uint256 deactivatedTime;
        uint256 deactivatedEpoch;
        uint256 receivedStake; // from all delegators (weight of the validator)
        uint256 createdEpoch;
        uint256 createdTime;
        address auth; // self-stake delegator
    }

    NodeDriverAuth internal node;

    struct Rewards {
        uint256 lockupExtraReward;
        uint256 lockupBaseReward;
        uint256 unlockedReward;
    }

    // last sealed epoch (currentEpoch - 1)
    uint256 public currentSealedEpoch;
    mapping(uint256 => Validator) public getValidator;
    mapping(address => uint256) public getValidatorID;
    mapping(uint256 => bytes) public getValidatorPubkey;

    uint256 public lastValidatorID;

    // total stake of all validators - includes slashed/offline validators
    uint256 public totalStake;
    // total stake of active (OK_STATUS) validators (total weight)
    uint256 public totalActiveStake;

    // delegator => validator ID => stashed rewards (to be claimed/restaked)
    mapping(address => mapping(uint256 => Rewards)) internal _rewardsStash;

    // delegator => validator ID => last epoch number for which were rewards stashed
    mapping(address => mapping(uint256 => uint256)) public stashedRewardsUntilEpoch;

    struct WithdrawalRequest {
        uint256 epoch; // epoch where undelegated
        uint256 time; // when undelegated
        uint256 amount;
    }

    // delegator => validator ID => withdrawal ID => withdrawal request
    mapping(address => mapping(uint256 => mapping(uint256 => WithdrawalRequest))) public getWithdrawalRequest;

    struct LockedDelegation {
        uint256 lockedStake;
        uint256 fromEpoch;
        uint256 endTime;
        uint256 duration;
    }

    // delegator => validator ID => current stake (locked+unlocked)
    mapping(address => mapping(uint256 => uint256)) public getStake;

    // delegator => validator ID => locked stake info
    mapping(address => mapping(uint256 => LockedDelegation)) public getLockupInfo;

    mapping(address => mapping(uint256 => Rewards)) public getStashedLockupRewards;

    // data structure to compute average uptime for each active validator
    struct AverageData {
        // average uptime
        int32 averageUptime;
        // average uptime error term
        int32 averageUptimeError;
        // number of alive epochs (counts only up to numEpochsAliveThreshold)
        int32 numEpochsAlive;
    }

    struct EpochSnapshot {
        // validator ID => validator weight in the epoch
        mapping(uint256 => uint256) receivedStake;
        // validator ID => accumulated ( delegatorsReward * 1e18 / receivedStake )
        mapping(uint256 => uint256) accumulatedRewardPerToken;
        // validator ID => accumulated online time
        mapping(uint256 => uint256) accumulatedUptime;
        // validator ID => average uptime as a percentage
        mapping(uint256 => AverageData) averageData;
        // validator ID => gas fees from txs originated by the validator
        mapping(uint256 => uint256) accumulatedOriginatedTxsFee;
        mapping(uint256 => uint256) offlineTime;
        mapping(uint256 => uint256) offlineBlocks;
        uint256[] validatorIDs;
        uint256 endTime;
        uint256 endBlock;
        uint256 epochFee; // gas fees from txs in the epoch
        uint256 baseRewardPerSecond; // the base reward to divide among validators for each second of the epoch
        uint256 totalStake; // total weight of all validators
        uint256 totalSupply; // total supply of native tokens
    }

    // the total supply of native tokens in the chain
    uint256 public totalSupply;
    // epoch id => epoch snapshot
    mapping(uint256 => EpochSnapshot) public getEpochSnapshot;

    // validator ID -> slashing refund ratio (allows to withdraw slashed stake)
    mapping(uint256 => uint256) public slashingRefundRatio;

    // the minimal gas price calculated for the current epoch
    uint256 public minGasPrice;

    // the treasure contract (receives unlock penalties and a part of epoch fees)
    address public treasuryAddress;

    // the SFCLib contract
    address internal libAddress;

    ConstantsManager internal c;

    // the governance contract (to recalculate votes when the stake changes)
    address public voteBookAddress;

    struct Penalty {
        uint256 amount;
        uint256 end;
    }
    // delegator => validatorID => penalties info
    mapping(address => mapping(uint256 => Penalty[])) public getStashedPenalties;

    // validator ID => amount of pubkey updates
    mapping(uint256 => uint256) internal validatorPubkeyChanges;

    // keccak256(pubkey bytes) => validator ID (prevents using the same key by multiple validators)
    mapping(bytes32 => uint256) internal pubkeyHashToValidatorID;

    // address authorized to initiate redirection
    address public redirectionAuthorizer;

    // delegator => withdrawals receiver
    mapping(address => address) public getRedirectionRequest;

    // delegator => withdrawals receiver
    mapping(address => address) public getRedirection;
}
