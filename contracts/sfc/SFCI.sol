pragma solidity ^0.5.0;

interface SFCI {
    event CreatedValidator(uint256 indexed validatorID, address indexed auth, uint256 createdEpoch, uint256 createdTime);
    event Delegated(address indexed delegator, uint256 indexed toValidatorID, uint256 amount);
    event Undelegated(address indexed delegator, uint256 indexed toValidatorID, uint256 indexed wrID, uint256 amount);
    event Withdrawn(address indexed delegator, uint256 indexed toValidatorID, uint256 indexed wrID, uint256 amount);
    event ClaimedRewards(address indexed delegator, uint256 indexed toValidatorID, uint256 lockupExtraReward, uint256 lockupBaseReward, uint256 unlockedReward);
    event RestakedRewards(address indexed delegator, uint256 indexed toValidatorID, uint256 lockupExtraReward, uint256 lockupBaseReward, uint256 unlockedReward);
    event BurntFTM(uint256 amount);
    event LockedUpStake(address indexed delegator, uint256 indexed validatorID, uint256 duration, uint256 amount);
    event UnlockedStake(address indexed delegator, uint256 indexed validatorID, uint256 amount, uint256 penalty);
    event UpdatedSlashingRefundRatio(uint256 indexed validatorID, uint256 refundRatio);
    event RefundedSlashedLegacyDelegation(address indexed delegator, uint256 indexed validatorID, uint256 amount);

    event DeactivatedValidator(uint256 indexed validatorID, uint256 deactivatedEpoch, uint256 deactivatedTime);
    event ChangedValidatorStatus(uint256 indexed validatorID, uint256 status);

    function currentSealedEpoch() external view returns (uint256);

    function getEpochSnapshot(uint256) external view returns (uint256 endTime, uint256 epochFee, uint256 totalBaseRewardWeight, uint256 totalTxRewardWeight, uint256 _baseRewardPerSecond, uint256 totalStake, uint256 totalSupply);

    function getLockupInfo(address, uint256) external view returns (uint256 lockedStake, uint256 fromEpoch, uint256 endTime, uint256 duration);

    function getStake(address, uint256) external view returns (uint256);

    function getStashedLockupRewards(address, uint256) external view returns (uint256 lockupExtraReward, uint256 lockupBaseReward, uint256 unlockedReward);

    function getValidator(uint256) external view returns (uint256 status, uint256 deactivatedTime, uint256 deactivatedEpoch, uint256 receivedStake, uint256 createdEpoch, uint256 createdTime, address auth);

    function getValidatorID(address) external view returns (uint256);

    function getValidatorPubkey(uint256) external view returns (bytes memory);

    function getWithdrawalRequest(address, uint256, uint256) external view returns (uint256 epoch, uint256 time, uint256 amount);

    function isOwner() external view returns (bool);

    function lastValidatorID() external view returns (uint256);

    function minGasPrice() external view returns (uint256);

    function owner() external view returns (address);

    function renounceOwnership() external;

    function slashingRefundRatio(uint256) external view returns (uint256);

    function stakeTokenizerAddress() external view returns (address);

    function stashedRewardsUntilEpoch(address, uint256) external view returns (uint256);

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

    function updateBaseRewardPerSecond(uint256 value) external;

    function updateOfflinePenaltyThreshold(uint256 blocksNum, uint256 time) external;

    function updateSlashingRefundRatio(uint256 validatorID, uint256 refundRatio) external;

    function updateStakeTokenizerAddress(address addr) external;

    function updateTreasuryAddress(address v) external;

    function burnFTM(uint256 amount) external;

    function sealEpoch(uint256[] calldata offlineTime, uint256[] calldata offlineBlocks, uint256[] calldata uptimes, uint256[] calldata originatedTxsFee, uint256 epochGas) external;

    function sealEpochValidators(uint256[] calldata nextValidatorIDs) external;

    function isLockedUp(address delegator, uint256 toValidatorID) external view returns (bool);

    function getUnlockedStake(address delegator, uint256 toValidatorID) external view returns (uint256);

    function lockStake(uint256 toValidatorID, uint256 lockupDuration, uint256 amount) external;

    function relockStake(uint256 toValidatorID, uint256 lockupDuration, uint256 amount) external;

    function unlockStake(uint256 toValidatorID, uint256 amount) external returns (uint256);

    function initialize(uint256 sealedEpoch, uint256 _totalSupply, address nodeDriver, address lib, address consts, address _owner) external;

    function setGenesisValidator(address auth, uint256 validatorID, bytes calldata pubkey, uint256 status, uint256 createdEpoch, uint256 createdTime, uint256 deactivatedEpoch, uint256 deactivatedTime) external;

    function setGenesisDelegation(address delegator, uint256 toValidatorID, uint256 stake, uint256 lockedStake, uint256 lockupFromEpoch, uint256 lockupEndTime, uint256 lockupDuration, uint256 earlyUnlockPenalty, uint256 rewards) external;

    function updateVoteBookAddress(address v) external;

    function voteBookAddress() external view returns (address);

    function liquidateSFTM(address delegator, uint256 toValidatorID, uint256 amount) external;

    function updateSFTMFinalizer(address v) external;
}
