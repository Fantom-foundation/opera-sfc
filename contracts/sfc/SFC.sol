// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Decimal} from "../common/Decimal.sol";
import {NodeDriverAuth} from "./NodeDriverAuth.sol";
import {ConstantsManager} from "./ConstantsManager.sol";
import {Version} from "../version/Version.sol";

/**
 * @title Special Fee Contract for Sonic network
 * @notice The SFC maintains a list of validators and delegators and distributes rewards to them.
 * @custom:security-contact security@fantom.foundation
 */
contract SFC is OwnableUpgradeable, UUPSUpgradeable, Version {
    uint256 internal constant OK_STATUS = 0;
    uint256 internal constant WITHDRAWN_BIT = 1;
    uint256 internal constant OFFLINE_BIT = 1 << 3;
    uint256 internal constant OFFLINE_AVG_BIT = 1 << 4;
    uint256 internal constant DOUBLESIGN_BIT = 1 << 7;
    uint256 internal constant CHEATER_MASK = DOUBLESIGN_BIT;

    /**
     * @dev The staking for validation
     */
    struct Validator {
        uint256 status;
        uint256 receivedStake; // from all delegators (weight of the validator)
        address auth; // self-stake delegator
        uint256 createdEpoch;
        uint256 createdTime;
        uint256 deactivatedTime;
        uint256 deactivatedEpoch;
    }

    NodeDriverAuth internal node;

    // last sealed epoch (currentEpoch - 1)
    uint256 public currentSealedEpoch;
    mapping(uint256 validatorID => Validator) public getValidator;
    mapping(address auth => uint256 validatorID) public getValidatorID;
    mapping(uint256 validatorID => bytes pubkey) public getValidatorPubkey;

    uint256 public lastValidatorID;

    // total stake of all validators - includes slashed/offline validators
    uint256 public totalStake;

    // total stake of active (OK_STATUS) validators (total weight)
    uint256 public totalActiveStake;

    // unresolved fees that failed to be send to the treasury
    uint256 public unresolvedTreasuryFees;

    // delegator => validator ID => stashed rewards (to be claimed/restaked)
    mapping(address delegator => mapping(uint256 validatorID => uint256 stashedRewards)) internal _rewardsStash;

    // delegator => validator ID => last epoch number for which were rewards stashed
    mapping(address delegator => mapping(uint256 validatorID => uint256 epoch)) public stashedRewardsUntilEpoch;

    struct WithdrawalRequest {
        uint256 epoch; // epoch where undelegated
        uint256 time; // when undelegated
        uint256 amount;
    }

    // delegator => validator ID => withdrawal ID => withdrawal request
    mapping(address delegator => mapping(uint256 validatorID => mapping(uint256 wrID => WithdrawalRequest)))
        public getWithdrawalRequest;

    // delegator => validator ID => current stake
    mapping(address delegator => mapping(uint256 validatorID => uint256 stake)) public getStake;

    // data structure to compute average uptime for each active validator
    struct AverageUptime {
        // average uptime ratio as a value between 0 and 1e18
        uint64 averageUptime;
        // remainder from the division in the average calculation
        uint32 remainder;
        // number of epochs in the average (at most averageUptimeEpochsWindow)
        uint32 epochs;
    }

    struct EpochSnapshot {
        // validator ID => validator weight in the epoch
        mapping(uint256 => uint256) receivedStake;
        // validator ID => accumulated ( delegatorsReward * 1e18 / receivedStake )
        mapping(uint256 => uint256) accumulatedRewardPerToken;
        // validator ID => accumulated online time
        mapping(uint256 => uint256) accumulatedUptime;
        // validator ID => average uptime as a percentage
        mapping(uint256 => AverageUptime) averageUptime;
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
    mapping(uint256 epoch => EpochSnapshot) public getEpochSnapshot;

    // validator ID -> slashing refund ratio (allows to withdraw slashed stake)
    mapping(uint256 validatorID => uint256 refundRatio) public slashingRefundRatio;

    // the treasure contract (receives unlock penalties and a part of epoch fees)
    address public treasuryAddress;

    ConstantsManager internal c;

    // the contract subscribed to stake changes notifications
    address public stakeSubscriberAddress;

    // address derived from the validator pubkey => validator id
    mapping(address pubkeyAddress => uint256 validatorID) public pubkeyAddressToValidatorID;

    // address authorized to initiate redirection
    address public redirectionAuthorizer;

    // delegator => withdrawals receiver
    mapping(address delegator => address receiver) public getRedirectionRequest;

    // delegator => withdrawals receiver
    mapping(address delegator => address receiver) public getRedirection;

    struct SealEpochRewardsCtx {
        uint256[] baseRewardWeights;
        uint256 totalBaseRewardWeight;
        uint256[] txRewardWeights;
        uint256 totalTxRewardWeight;
        uint256 epochFee;
    }

    // auth
    error NotDriverAuth();
    error NotAuthorized();

    // addresses
    error ZeroAddress();
    error SameAddress();

    // values
    error ZeroAmount();
    error ZeroRewards();

    // pubkeys
    error PubkeyUsedByOtherValidator();
    error MalformedPubkey();

    // redirections
    error AlreadyRedirected();
    error SameRedirectionAuthorizer();
    error Redirected();

    // validators
    error ValidatorNotExists();
    error ValidatorExists();
    error ValidatorNotActive();
    error ValidatorDelegationLimitExceeded();
    error NotDeactivatedStatus();

    // requests
    error RequestExists();
    error RequestNotExists();

    // transfers
    error TransfersNotAllowed();
    error TransferFailed();

    // stake changes subscriber
    error StakeSubscriberFailed();

    // staking
    error InsufficientSelfStake();
    error NotEnoughTimePassed();
    error NotEnoughEpochsPassed();
    error StakeIsFullySlashed();

    // stashing
    error NothingToStash();

    // slashing
    error ValidatorNotSlashed();
    error RefundRatioTooHigh();

    // treasury
    error TreasuryNotSet();
    error NoUnresolvedTreasuryFees();

    event DeactivatedValidator(uint256 indexed validatorID, uint256 deactivatedEpoch, uint256 deactivatedTime);
    event ChangedValidatorStatus(uint256 indexed validatorID, uint256 status);
    event CreatedValidator(
        uint256 indexed validatorID,
        address indexed auth,
        uint256 createdEpoch,
        uint256 createdTime
    );
    event Delegated(address indexed delegator, uint256 indexed toValidatorID, uint256 amount);
    event Undelegated(address indexed delegator, uint256 indexed toValidatorID, uint256 indexed wrID, uint256 amount);
    event Withdrawn(
        address indexed delegator,
        uint256 indexed toValidatorID,
        uint256 indexed wrID,
        uint256 amount,
        uint256 penalty
    );
    event ClaimedRewards(address indexed delegator, uint256 indexed toValidatorID, uint256 rewards);
    event RestakedRewards(address indexed delegator, uint256 indexed toValidatorID, uint256 rewards);
    event BurntFTM(uint256 amount);
    event UpdatedSlashingRefundRatio(uint256 indexed validatorID, uint256 refundRatio);
    event RefundedSlashedLegacyDelegation(address indexed delegator, uint256 indexed validatorID, uint256 amount);
    event AnnouncedRedirection(address indexed from, address indexed to);
    event TreasuryFeesResolved(uint256 amount);

    modifier onlyDriver() {
        if (!isNode(msg.sender)) {
            revert NotDriverAuth();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// Initialization is called only once, after the contract deployment.
    /// Because the contract code is written directly into genesis, constructor cannot be used.
    function initialize(
        uint256 sealedEpoch,
        uint256 _totalSupply,
        address nodeDriver,
        address _c,
        address owner
    ) external initializer {
        __Ownable_init(owner);
        __UUPSUpgradeable_init();
        currentSealedEpoch = sealedEpoch;
        node = NodeDriverAuth(nodeDriver);
        c = ConstantsManager(_c);
        totalSupply = _totalSupply;
        getEpochSnapshot[sealedEpoch].endTime = _now();
    }

    /// Override the upgrade authorization check to allow upgrades only from the owner.
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// Receive fallback to revert transfers.
    receive() external payable {
        revert TransfersNotAllowed();
    }

    /// Set admin address responsible for initiating redirections.
    function setRedirectionAuthorizer(address v) external onlyOwner {
        if (redirectionAuthorizer == v) {
            revert SameRedirectionAuthorizer();
        }
        redirectionAuthorizer = v;
    }

    /// Announce redirection of address to be called by validator whose auth key was compromised.
    /// Produced events are used to notify redirect authorizer about redirection request.
    /// Redirect authorizer then initiates creating of appropriate redirect by calling initiateRedirection().
    function announceRedirection(address to) external {
        emit AnnouncedRedirection(msg.sender, to);
    }

    /// Initiate redirection of withdrawals/claims for a compromised validator account.
    /// Needs to be accepted by validator key holder before the redirect is active.
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

    /// Accept redirection proposal.
    /// Redirection must by accepted by the validator key holder before it start to be applied.
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

    /// Seal current epoch - deactivate validators who were offline too long, create an epoch snapshot
    /// for the current epoch (provides information for rewards calculation), calculate new minimal gas price.
    /// This method is called BEFORE the epoch sealing made by the client itself.
    function sealEpoch(
        uint256[] calldata offlineTime,
        uint256[] calldata offlineBlocks,
        uint256[] calldata uptimes,
        uint256[] calldata originatedTxsFee
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
            _sealEpochAverageUptime(epochDuration, snapshot, prevSnapshot, validatorIDs, uptimes);
        }

        currentSealedEpoch = currentEpoch();
        snapshot.endTime = _now();
        snapshot.endBlock = block.number;
        snapshot.baseRewardPerSecond = c.baseRewardPerSecond();
        snapshot.totalSupply = totalSupply;
    }

    /// Finish epoch sealing - store validators of the new epoch into a snapshot.
    /// This method is called AFTER the epoch sealing made by the client itself.
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
    }

    /// Set an initial validator.
    /// Called only as part of network initialization/genesis file generating.
    function setGenesisValidator(
        address auth,
        uint256 validatorID,
        bytes calldata pubkey,
        uint256 createdTime
    ) external onlyDriver {
        _rawCreateValidator(
            auth,
            validatorID,
            pubkey,
            OK_STATUS,
            0, // createdEpoch
            createdTime,
            0, // deactivatedEpoch - not deactivated
            0 // deactivatedTime - not deactivated
        );
        if (validatorID > lastValidatorID) {
            lastValidatorID = validatorID;
        }
    }

    /// Set an initial delegation.
    /// Called only as part of network initialization/genesis file generating.
    function setGenesisDelegation(address delegator, uint256 toValidatorID, uint256 stake) external onlyDriver {
        _rawDelegate(delegator, toValidatorID, stake, false);
        _mintNativeToken(stake);
    }

    /// Create a validator with a given public key while using attached value as the validator's self-stake.
    function createValidator(bytes calldata pubkey) external payable {
        if (msg.value < c.minSelfStake()) {
            revert InsufficientSelfStake();
        }
        if (pubkey.length != 66 || pubkey[0] != 0xc0) {
            revert MalformedPubkey();
        }
        if (pubkeyAddressToValidatorID[_pubkeyToAddress(pubkey)] != 0) {
            revert PubkeyUsedByOtherValidator();
        }
        _createValidator(msg.sender, pubkey);
        _delegate(msg.sender, lastValidatorID, msg.value);
    }

    /// Update slashing refund ratio for a validator.
    /// The refund ratio is used to calculate the amount of stake that can be withdrawn after slashing.
    function updateSlashingRefundRatio(uint256 validatorID, uint256 refundRatio) external onlyOwner {
        if (!isSlashed(validatorID)) {
            revert ValidatorNotSlashed();
        }
        if (refundRatio > Decimal.unit()) {
            revert RefundRatioTooHigh();
        }
        slashingRefundRatio[validatorID] = refundRatio;
        emit UpdatedSlashingRefundRatio(validatorID, refundRatio);
    }

    /// Delegate stake to a validator.
    function delegate(uint256 toValidatorID) external payable {
        _delegate(msg.sender, toValidatorID, msg.value);
    }

    /// Withdraw stake from a validator after its un-delegation.
    /// Un-delegated stake is locked for a certain period of time.
    function withdraw(uint256 toValidatorID, uint256 wrID) public {
        _withdraw(msg.sender, toValidatorID, wrID, _receiverOf(msg.sender));
    }

    /// Deactivate a validator.
    /// Called by the chain client when a client misbehavior is observed.
    function deactivateValidator(uint256 validatorID, uint256 status) external onlyDriver {
        if (status == OK_STATUS) {
            revert NotDeactivatedStatus();
        }

        _setValidatorDeactivated(validatorID, status);
        _syncValidator(validatorID, false);
        address validatorAddr = getValidator[validatorID].auth;
        _notifyStakeSubscriber(validatorAddr, validatorAddr, false);
    }

    /// Stash rewards for a delegator.
    function stashRewards(address delegator, uint256 toValidatorID) external {
        if (!_stashRewards(delegator, toValidatorID)) {
            revert NothingToStash();
        }
    }

    /// Resolve failed treasury transfers and send the unresolved fees to the treasury address.
    function resolveTreasuryFees() external {
        if (treasuryAddress == address(0)) {
            revert TreasuryNotSet();
        }
        if (unresolvedTreasuryFees == 0) {
            revert NoUnresolvedTreasuryFees();
        }

        // zero the fees before sending to prevent re-entrancy
        uint256 fees = unresolvedTreasuryFees;
        unresolvedTreasuryFees = 0;

        (bool success, ) = treasuryAddress.call{value: fees, gas: 1000000}("");
        if (!success) {
            revert TransferFailed();
        }

        emit TreasuryFeesResolved(fees);
    }

    /// burnFTM allows SFC to burn an arbitrary amount of FTM tokens.
    function burnFTM(uint256 amount) external onlyOwner {
        _burnFTM(amount);
    }

    /// Issue tokens to the issued tokens recipient as a counterparty to the burnt FTM tokens.
    function issueTokens(uint256 amount) external onlyOwner {
        if (c.issuedTokensRecipient() == address(0)) {
            revert ZeroAddress();
        }
        node.incBalance(c.issuedTokensRecipient(), amount);
        totalSupply += amount;
    }

    /// Update treasury address.
    function updateTreasuryAddress(address v) external onlyOwner {
        treasuryAddress = v;
    }

    /// Update consts address.
    function updateConstsAddress(address v) external onlyOwner {
        c = ConstantsManager(v);
    }

    /// Update voteBook address.
    function updateStakeSubscriberAddress(address v) external onlyOwner {
        stakeSubscriberAddress = v;
    }

    /// Get consts address.
    function constsAddress() external view returns (address) {
        return address(c);
    }

    /// Claim rewards for stake delegated to a validator.
    function claimRewards(uint256 toValidatorID) public {
        address delegator = msg.sender;
        uint256 rewards = _claimRewards(delegator, toValidatorID);
        // It's important that we transfer after erasing (protection against Re-Entrancy)
        (bool sent, ) = _receiverOf(delegator).call{value: rewards}("");
        if (!sent) {
            revert TransferFailed();
        }

        emit ClaimedRewards(delegator, toValidatorID, rewards);
    }

    /// Get amount of currently stashed rewards.
    function rewardsStash(address delegator, uint256 validatorID) public view returns (uint256) {
        return _rewardsStash[delegator][validatorID];
    }

    /// Un-delegate stake from a validator.
    function undelegate(uint256 toValidatorID, uint256 wrID, uint256 amount) public {
        address delegator = msg.sender;

        _stashRewards(delegator, toValidatorID);

        if (amount == 0) {
            revert ZeroAmount();
        }

        if (getWithdrawalRequest[delegator][toValidatorID][wrID].amount != 0) {
            revert RequestExists();
        }

        _rawUndelegate(delegator, toValidatorID, amount, true, false, true);

        getWithdrawalRequest[delegator][toValidatorID][wrID].amount = amount;
        getWithdrawalRequest[delegator][toValidatorID][wrID].epoch = currentEpoch();
        getWithdrawalRequest[delegator][toValidatorID][wrID].time = _now();

        _syncValidator(toValidatorID, false);

        emit Undelegated(delegator, toValidatorID, wrID, amount);
    }

    /// Re-stake rewards - claim rewards for staking and delegate it immediately
    /// to the same validator - add it to the current stake.
    function restakeRewards(uint256 toValidatorID) public {
        address delegator = msg.sender;
        uint256 rewards = _claimRewards(delegator, toValidatorID);

        _delegate(delegator, toValidatorID, rewards);
        emit RestakedRewards(delegator, toValidatorID, rewards);
    }

    /// Get the current epoch number.
    function currentEpoch() public view returns (uint256) {
        return currentSealedEpoch + 1;
    }

    /// Get self-stake of a validator.
    function getSelfStake(uint256 validatorID) public view returns (uint256) {
        return getStake[getValidator[validatorID].auth][validatorID];
    }

    /// Get validator IDs for given epoch.
    function getEpochValidatorIDs(uint256 epoch) public view returns (uint256[] memory) {
        return getEpochSnapshot[epoch].validatorIDs;
    }

    /// Get received stake for a validator in a given epoch.
    function getEpochReceivedStake(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].receivedStake[validatorID];
    }

    /// Get accumulated reward per token for a validator in a given epoch.
    function getEpochAccumulatedRewardPerToken(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].accumulatedRewardPerToken[validatorID];
    }

    /// Get accumulated uptime for a validator in a given epoch.
    function getEpochAccumulatedUptime(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].accumulatedUptime[validatorID];
    }

    /// Get average uptime for a validator in a given epoch.
    function getEpochAverageUptime(uint256 epoch, uint256 validatorID) public view returns (uint64) {
        return getEpochSnapshot[epoch].averageUptime[validatorID].averageUptime;
    }

    /// Get accumulated originated txs fee for a validator in a given epoch.
    function getEpochAccumulatedOriginatedTxsFee(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].accumulatedOriginatedTxsFee[validatorID];
    }

    /// Get offline time for a validator in a given epoch.
    function getEpochOfflineTime(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].offlineTime[validatorID];
    }

    /// Get offline blocks for a validator in a given epoch.
    function getEpochOfflineBlocks(uint256 epoch, uint256 validatorID) public view returns (uint256) {
        return getEpochSnapshot[epoch].offlineBlocks[validatorID];
    }

    /// Get end block for a given epoch.
    function getEpochEndBlock(uint256 epoch) public view returns (uint256) {
        return getEpochSnapshot[epoch].endBlock;
    }

    /// Check whether the given validator is slashed - the stake (or its part) cannot
    /// be withdrawn because of misbehavior (double-sign) of the validator.
    function isSlashed(uint256 validatorID) public view returns (bool) {
        return getValidator[validatorID].status & CHEATER_MASK != 0;
    }

    /// Get the amount of rewards which can be currently claimed by the given delegator for the given validator.
    function pendingRewards(address delegator, uint256 toValidatorID) public view returns (uint256) {
        uint256 reward = _newRewards(delegator, toValidatorID);
        return _rewardsStash[delegator][toValidatorID] + reward;
    }

    /// Check whether the self-stake covers the required fraction of all delegations for the given validator.
    function _checkDelegatedStakeLimit(uint256 validatorID) internal view returns (bool) {
        return
            getValidator[validatorID].receivedStake <=
            (getSelfStake(validatorID) * c.maxDelegatedRatio()) / Decimal.unit();
    }

    /// Check if an address is the NodeDriverAuth contract.
    function isNode(address addr) internal view virtual returns (bool) {
        return addr == address(node);
    }

    /// Delegate stake to a validator.
    function _delegate(address delegator, uint256 toValidatorID, uint256 amount) internal {
        if (!_validatorExists(toValidatorID)) {
            revert ValidatorNotExists();
        }
        if (getValidator[toValidatorID].status != OK_STATUS) {
            revert ValidatorNotActive();
        }
        _rawDelegate(delegator, toValidatorID, amount, true);
        if (!_checkDelegatedStakeLimit(toValidatorID)) {
            revert ValidatorDelegationLimitExceeded();
        }
    }

    /// Delegate stake to a validator without checking delegation limit.
    function _rawDelegate(address delegator, uint256 toValidatorID, uint256 amount, bool strict) internal {
        if (amount == 0) {
            revert ZeroAmount();
        }

        _stashRewards(delegator, toValidatorID);

        getStake[delegator][toValidatorID] = getStake[delegator][toValidatorID] + amount;
        uint256 origStake = getValidator[toValidatorID].receivedStake;
        getValidator[toValidatorID].receivedStake = origStake + amount;
        totalStake = totalStake + amount;
        if (getValidator[toValidatorID].status == OK_STATUS) {
            totalActiveStake = totalActiveStake + amount;
        }

        _syncValidator(toValidatorID, origStake == 0);

        emit Delegated(delegator, toValidatorID, amount);

        _notifyStakeSubscriber(delegator, getValidator[toValidatorID].auth, strict);
    }

    /// Un-delegate stake from a validator.
    function _rawUndelegate(
        address delegator,
        uint256 toValidatorID,
        uint256 amount,
        bool strict,
        bool forceful,
        bool checkDelegatedStake
    ) internal {
        getStake[delegator][toValidatorID] -= amount;
        getValidator[toValidatorID].receivedStake = getValidator[toValidatorID].receivedStake - amount;
        totalStake = totalStake - amount;
        if (getValidator[toValidatorID].status == OK_STATUS) {
            totalActiveStake = totalActiveStake - amount;
        }

        uint256 selfStakeAfterwards = getSelfStake(toValidatorID);
        if (selfStakeAfterwards != 0 && getValidator[toValidatorID].status == OK_STATUS) {
            if (!(selfStakeAfterwards >= c.minSelfStake())) {
                if (forceful) {
                    revert InsufficientSelfStake();
                } else {
                    _setValidatorDeactivated(toValidatorID, WITHDRAWN_BIT);
                }
            }
            if (checkDelegatedStake && !_checkDelegatedStakeLimit(toValidatorID)) {
                revert ValidatorDelegationLimitExceeded();
            }
        } else {
            _setValidatorDeactivated(toValidatorID, WITHDRAWN_BIT);
        }

        _notifyStakeSubscriber(delegator, getValidator[toValidatorID].auth, strict);
    }

    /// Get slashing penalty for a stake.
    function getSlashingPenalty(
        uint256 amount,
        bool isCheater,
        uint256 refundRatio
    ) internal pure returns (uint256 penalty) {
        if (!isCheater || refundRatio >= Decimal.unit()) {
            return 0;
        }
        // round penalty upwards (ceiling) to prevent dust amount attacks
        penalty = (amount * (Decimal.unit() - refundRatio)) / Decimal.unit() + 1;
        if (penalty > amount) {
            return amount;
        }
        return penalty;
    }

    /// Withdraw stake from a validator.
    /// The stake must be undelegated first.
    function _withdraw(address delegator, uint256 toValidatorID, uint256 wrID, address payable receiver) private {
        WithdrawalRequest memory request = getWithdrawalRequest[delegator][toValidatorID][wrID];
        if (request.epoch == 0) {
            revert RequestNotExists();
        }

        uint256 requestTime = request.time;
        uint256 requestEpoch = request.epoch;
        if (
            getValidator[toValidatorID].deactivatedTime != 0 &&
            getValidator[toValidatorID].deactivatedTime < requestTime
        ) {
            requestTime = getValidator[toValidatorID].deactivatedTime;
            requestEpoch = getValidator[toValidatorID].deactivatedEpoch;
        }

        if (_now() < requestTime + c.withdrawalPeriodTime()) {
            revert NotEnoughTimePassed();
        }

        if (currentEpoch() < requestEpoch + c.withdrawalPeriodEpochs()) {
            revert NotEnoughEpochsPassed();
        }

        uint256 amount = getWithdrawalRequest[delegator][toValidatorID][wrID].amount;
        bool isCheater = isSlashed(toValidatorID);
        uint256 penalty = getSlashingPenalty(amount, isCheater, slashingRefundRatio[toValidatorID]);
        delete getWithdrawalRequest[delegator][toValidatorID][wrID];

        if (amount <= penalty) {
            revert StakeIsFullySlashed();
        }
        // It's important that we transfer after erasing (protection against Re-Entrancy)
        (bool sent, ) = receiver.call{value: amount - penalty}("");
        if (!sent) {
            revert TransferFailed();
        }
        _burnFTM(penalty);

        emit Withdrawn(delegator, toValidatorID, wrID, amount - penalty, penalty);
    }

    /// Get highest epoch for which can be claimed rewards for the given validator.
    // If the validator is deactivated, the highest payable epoch is the deactivation epoch
    // or the current epoch, whichever is lower
    function _highestPayableEpoch(uint256 validatorID) internal view returns (uint256) {
        if (getValidator[validatorID].deactivatedEpoch != 0) {
            if (currentSealedEpoch < getValidator[validatorID].deactivatedEpoch) {
                return currentSealedEpoch;
            }
            return getValidator[validatorID].deactivatedEpoch;
        }
        return currentSealedEpoch;
    }

    /// Get new rewards for a delegator.
    /// The rewards are calculated from the last stashed epoch until the highest payable epoch.
    function _newRewards(address delegator, uint256 toValidatorID) internal view returns (uint256) {
        uint256 stashedUntil = stashedRewardsUntilEpoch[delegator][toValidatorID];
        uint256 payableUntil = _highestPayableEpoch(toValidatorID);
        uint256 wholeStake = getStake[delegator][toValidatorID];
        uint256 fullReward = _newRewardsOf(wholeStake, toValidatorID, stashedUntil, payableUntil);
        return fullReward;
    }

    /// Get new rewards for a delegator for a given stake amount and epoch range.
    function _newRewardsOf(
        uint256 stakeAmount,
        uint256 toValidatorID,
        uint256 fromEpoch,
        uint256 toEpoch
    ) internal view returns (uint256) {
        if (fromEpoch >= toEpoch) {
            return 0;
        }
        uint256 stashedRate = getEpochSnapshot[fromEpoch].accumulatedRewardPerToken[toValidatorID];
        uint256 currentRate = getEpochSnapshot[toEpoch].accumulatedRewardPerToken[toValidatorID];
        return ((currentRate - stashedRate) * stakeAmount) / Decimal.unit();
    }

    /// Stash rewards for a delegator.
    function _stashRewards(address delegator, uint256 toValidatorID) internal returns (bool updated) {
        uint256 nonStashedReward = _newRewards(delegator, toValidatorID);
        stashedRewardsUntilEpoch[delegator][toValidatorID] = _highestPayableEpoch(toValidatorID);
        _rewardsStash[delegator][toValidatorID] += nonStashedReward;
        return nonStashedReward != 0;
    }

    /// Claim rewards for a delegator.
    function _claimRewards(address delegator, uint256 toValidatorID) internal returns (uint256) {
        _stashRewards(delegator, toValidatorID);
        uint256 rewards = _rewardsStash[delegator][toValidatorID];
        if (rewards == 0) {
            revert ZeroRewards();
        }
        delete _rewardsStash[delegator][toValidatorID];
        // It's important that we mint after erasing (protection against Re-Entrancy)
        _mintNativeToken(rewards);
        return rewards;
    }

    /// Burn FTM tokens.
    /// The tokens are sent to the zero address.
    function _burnFTM(uint256 amount) internal {
        if (amount != 0) {
            payable(address(0)).transfer(amount);
            emit BurntFTM(amount);
        }
    }

    /// Get epoch end time.
    function epochEndTime(uint256 epoch) internal view returns (uint256) {
        return getEpochSnapshot[epoch].endTime;
    }

    /// Check if an address is redirected.
    function _redirected(address addr) internal view returns (bool) {
        return getRedirection[addr] != address(0);
    }

    /// Get address which should receive rewards and withdrawn stake for the given delegator.
    /// The delegator is usually the receiver, unless a redirection is created.
    function _receiverOf(address addr) internal view returns (address payable) {
        address to = getRedirection[addr];
        if (to == address(0)) {
            return payable(address(uint160(addr)));
        }
        return payable(address(uint160(to)));
    }

    /// Seal epoch - sync validators.
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

    /// Seal epoch - calculate rewards.
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
                _rewardsStash[validatorAddr][validatorID] += commissionRewardFull;
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
            // solhint-disable-next-line no-empty-blocks
            if (!success) {
                // ignore treasury transfer failure
                // the treasury failure must not endanger the epoch sealing

                // store the unresolved treasury fees to be resolved later
                unresolvedTreasuryFees += feeShare;
            }
        }
    }

    /// Seal epoch - recalculate average uptime time of validators
    function _sealEpochAverageUptime(
        uint256 epochDuration,
        EpochSnapshot storage snapshot,
        EpochSnapshot storage prevSnapshot,
        uint256[] memory validatorIDs,
        uint256[] memory uptimes
    ) internal {
        for (uint256 i = 0; i < validatorIDs.length; i++) {
            uint256 validatorID = validatorIDs[i];
            // compute normalised uptime as a percentage in the fixed-point format
            uint256 normalisedUptime = (uptimes[i] * Decimal.unit()) / epochDuration;
            if (normalisedUptime > Decimal.unit()) {
                normalisedUptime = Decimal.unit();
            }
            AverageUptime memory previous = prevSnapshot.averageUptime[validatorID];
            AverageUptime memory current = _addElementIntoAverageUptime(uint64(normalisedUptime), previous);
            snapshot.averageUptime[validatorID] = current;

            // remove validator if average uptime drops below min average uptime
            // (by setting minAverageUptime to zero, this check is ignored)
            if (current.averageUptime < c.minAverageUptime() && current.epochs >= c.averageUptimeEpochWindow()) {
                _setValidatorDeactivated(validatorID, OFFLINE_AVG_BIT);
                _syncValidator(validatorID, false);
            }
        }
    }

    function _addElementIntoAverageUptime(
        uint64 newValue,
        AverageUptime memory prev
    ) private view returns (AverageUptime memory) {
        AverageUptime memory cur;
        if (prev.epochs == 0) {
            cur.averageUptime = newValue; // the only element for the average
            cur.epochs = 1;
            return cur;
        }

        // the number of elements the average is calculated from
        uint128 n = prev.epochs + 1;
        // add new value into the average
        uint128 tmp = (n - 1) * uint128(prev.averageUptime) + uint128(newValue) + prev.remainder;

        cur.averageUptime = uint64(tmp / n);
        cur.remainder = uint32(tmp % n);

        if (cur.averageUptime > Decimal.unit()) {
            cur.averageUptime = uint64(Decimal.unit());
            cur.remainder = 0; // reset the remainder when capping the averageUptime
        }
        if (prev.epochs < c.averageUptimeEpochWindow()) {
            cur.epochs = prev.epochs + 1;
        } else {
            cur.epochs = prev.epochs;
        }
        return cur;
    }

    /// Create a new validator.
    function _createValidator(address auth, bytes calldata pubkey) internal {
        uint256 validatorID = ++lastValidatorID;
        _rawCreateValidator(auth, validatorID, pubkey, OK_STATUS, currentEpoch(), _now(), 0, 0);
    }

    /// Create a new validator without incrementing lastValidatorID.
    function _rawCreateValidator(
        address auth,
        uint256 validatorID,
        bytes calldata pubkey,
        uint256 status,
        uint256 createdEpoch,
        uint256 createdTime,
        uint256 deactivatedEpoch,
        uint256 deactivatedTime
    ) internal {
        if (getValidatorID[auth] != 0) {
            revert ValidatorExists();
        }
        getValidatorID[auth] = validatorID;
        getValidator[validatorID].status = status;
        getValidator[validatorID].createdEpoch = createdEpoch;
        getValidator[validatorID].createdTime = createdTime;
        getValidator[validatorID].deactivatedTime = deactivatedTime;
        getValidator[validatorID].deactivatedEpoch = deactivatedEpoch;
        getValidator[validatorID].auth = auth;
        getValidatorPubkey[validatorID] = pubkey;
        pubkeyAddressToValidatorID[_pubkeyToAddress(pubkey)] = validatorID;

        emit CreatedValidator(validatorID, auth, createdEpoch, createdTime);
        if (deactivatedEpoch != 0) {
            emit DeactivatedValidator(validatorID, deactivatedEpoch, deactivatedTime);
        }
        if (status != 0) {
            emit ChangedValidatorStatus(validatorID, status);
        }
    }

    /// Calculate raw validator epoch transaction reward.
    function _calcRawValidatorEpochTxReward(
        uint256 epochFee,
        uint256 txRewardWeight,
        uint256 totalTxRewardWeight
    ) internal view returns (uint256) {
        if (txRewardWeight == 0) {
            return 0;
        }
        uint256 txReward = (epochFee * txRewardWeight) / totalTxRewardWeight;
        // fee reward except burntFeeShare and treasuryFeeShare
        return (txReward * (Decimal.unit() - c.burntFeeShare() - c.treasuryFeeShare())) / Decimal.unit();
    }

    /// Calculate raw validator epoch base reward.
    function _calcRawValidatorEpochBaseReward(
        uint256 epochDuration,
        uint256 _baseRewardPerSecond,
        uint256 baseRewardWeight,
        uint256 totalBaseRewardWeight
    ) internal pure returns (uint256) {
        if (baseRewardWeight == 0) {
            return 0;
        }
        uint256 totalReward = epochDuration * _baseRewardPerSecond;
        return (totalReward * baseRewardWeight) / totalBaseRewardWeight;
    }

    /// Mint native token.
    function _mintNativeToken(uint256 amount) internal {
        // balance will be increased after the transaction is processed
        node.incBalance(address(this), amount);
        totalSupply = totalSupply + amount;
    }

    /// Notify stake subscriber about staking changes.
    /// Used to recount votes from delegators in the governance contract.
    function _notifyStakeSubscriber(address delegator, address validatorAuth, bool strict) internal {
        if (stakeSubscriberAddress != address(0)) {
            // Don't allow announceStakeChange to use up all the gas
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = stakeSubscriberAddress.call{gas: 8000000}(
                abi.encodeWithSignature("announceStakeChange(address,address)", delegator, validatorAuth)
            );
            // Don't revert if announceStakeChange failed unless strict mode enabled
            if (!success && strict) {
                revert StakeSubscriberFailed();
            }
        }
    }

    /// Set validator deactivated status.
    function _setValidatorDeactivated(uint256 validatorID, uint256 status) internal {
        if (getValidator[validatorID].status == OK_STATUS && status != OK_STATUS) {
            totalActiveStake = totalActiveStake - getValidator[validatorID].receivedStake;
        }
        // status as a number is proportional to severity
        if (status > getValidator[validatorID].status) {
            getValidator[validatorID].status = status;
            if (getValidator[validatorID].deactivatedEpoch == 0) {
                getValidator[validatorID].deactivatedEpoch = currentEpoch();
                getValidator[validatorID].deactivatedTime = _now();
                emit DeactivatedValidator(
                    validatorID,
                    getValidator[validatorID].deactivatedEpoch,
                    getValidator[validatorID].deactivatedTime
                );
            }
            emit ChangedValidatorStatus(validatorID, status);
        }
    }

    /// Sync validator with node.
    function _syncValidator(uint256 validatorID, bool syncPubkey) public {
        if (!_validatorExists(validatorID)) {
            revert ValidatorNotExists();
        }
        // emit special log for node
        uint256 weight = getValidator[validatorID].receivedStake;
        if (getValidator[validatorID].status != OK_STATUS) {
            weight = 0;
        }
        node.updateValidatorWeight(validatorID, weight);
        if (syncPubkey && weight != 0) {
            node.updateValidatorPubkey(validatorID, getValidatorPubkey[validatorID]);
        }
    }

    /// Check if a validator exists.
    function _validatorExists(uint256 validatorID) internal view returns (bool) {
        return getValidator[validatorID].createdTime != 0;
    }

    /// Calculate validator commission.
    function _calcValidatorCommission(uint256 rawReward, uint256 commission) internal pure returns (uint256) {
        return (rawReward * commission) / Decimal.unit();
    }

    /// Derive address from validator private key
    function _pubkeyToAddress(bytes calldata pubkey) private pure returns (address) {
        return address(uint160(uint256(keccak256(pubkey[2:]))));
    }

    /// Get current time.
    function _now() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    uint256[50] private __gap;
}
