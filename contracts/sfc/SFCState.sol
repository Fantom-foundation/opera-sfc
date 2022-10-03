pragma solidity ^0.5.0;

import "./NodeDriver.sol";
import "../ownership/Ownable.sol";
import "./ConstantsManager.sol";

contract SFCState is Initializable, Ownable {
    using SafeMath for uint256;
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
    }

    NodeDriverAuth internal node;

    struct Rewards {
        uint256 lockupExtraReward;
        uint256 lockupBaseReward;
        uint256 unlockedReward;
    }

    uint256 public currentSealedEpoch;
    mapping(uint256 => Validator) public getValidator;
    mapping(address => uint256) public getValidatorID;
    mapping(uint256 => bytes) public getValidatorPubkey;

    uint256 public lastValidatorID;
    uint256 public totalStake;
    uint256 public totalActiveStake;
    uint256 public totalSlashedStake;

    mapping(address => mapping(uint256 => Rewards)) internal _rewardsStash; // addr, validatorID -> Rewards

    mapping(address => mapping(uint256 => uint256)) public stashedRewardsUntilEpoch;

    struct WithdrawalRequest {
        uint256 epoch;
        uint256 time;

        uint256 amount;
    }

    mapping(address => mapping(uint256 => mapping(uint256 => WithdrawalRequest))) public getWithdrawalRequest;

    struct LockedDelegation {
        uint256 lockedStake;
        uint256 fromEpoch;
        uint256 endTime;
        uint256 duration;
    }

    mapping(address => mapping(uint256 => uint256)) public getStake;

    mapping(address => mapping(uint256 => LockedDelegation)) public getLockupInfo;

    mapping(address => mapping(uint256 => Rewards)) public getStashedLockupRewards;

    struct EpochSnapshot {
        mapping(uint256 => uint256) receivedStake;
        mapping(uint256 => uint256) accumulatedRewardPerToken;
        mapping(uint256 => uint256) accumulatedUptime;
        mapping(uint256 => uint256) accumulatedOriginatedTxsFee;
        mapping(uint256 => uint256) offlineTime;
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

    uint256 private erased0;
    uint256 public totalSupply;
    mapping(uint256 => EpochSnapshot) public getEpochSnapshot;

    uint256 private erased1;
    uint256 private erased2;

    mapping(uint256 => uint256) public slashingRefundRatio; // validator ID -> (slashing refund ratio)

    address public stakeTokenizerAddress;

    uint256 private erased3;
    uint256 private erased4;
    uint256 public minGasPrice;

    address public treasuryAddress;

    address internal libAddress;

    ConstantsManager internal c;
}
