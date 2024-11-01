// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Ownable} from "../ownership/Ownable.sol";
import {Initializable} from "../common/Initializable.sol";
import {Decimal} from "../common/Decimal.sol";
import {NodeDriverAuth} from "./NodeDriverAuth.sol";
import {ConstantsManager} from "./ConstantsManager.sol";
import {GP} from "./GasPriceConstants.sol";
import {Version} from "../version/Version.sol";

/**
 * @dev SFC contract for Sonic network.
 */
contract SFC is Initializable, Ownable, Version {
    uint256 internal constant OK_STATUS = 0;
    uint256 internal constant WITHDRAWN_BIT = 1;
    uint256 internal constant OFFLINE_BIT = 1 << 3;
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
    mapping(uint256 => Validator) public getValidator;
    mapping(address => uint256) public getValidatorID;
    mapping(uint256 => bytes) public getValidatorPubkey;

    uint256 public lastValidatorID;

    // total stake of all validators - includes slashed/offline validators
    uint256 public totalStake;

    // total stake of active (OK_STATUS) validators (total weight)
    uint256 public totalActiveStake;

    // delegator => validator ID => stashed rewards (to be claimed/restaked)
    mapping(address => mapping(uint256 => uint256)) internal _rewardsStash;

    // delegator => validator ID => last epoch number for which were rewards stashed
    mapping(address => mapping(uint256 => uint256)) public stashedRewardsUntilEpoch;

    struct WithdrawalRequest {
        uint256 epoch; // epoch where undelegated
        uint256 time; // when undelegated
        uint256 amount;
    }

    // delegator => validator ID => withdrawal ID => withdrawal request
    mapping(address => mapping(uint256 => mapping(uint256 => WithdrawalRequest))) public getWithdrawalRequest;

    // delegator => validator ID => current stake (locked+unlocked)
    mapping(address => mapping(uint256 => uint256)) public getStake;

    struct EpochSnapshot {
        // validator ID => validator weight in the epoch
        mapping(uint256 => uint256) receivedStake;
        // validator ID => accumulated ( delegatorsReward * 1e18 / receivedStake )
        mapping(uint256 => uint256) accumulatedRewardPerToken;
        // validator ID => accumulated online time
        mapping(uint256 => uint256) accumulatedUptime;
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

    ConstantsManager internal c;

    // the governance contract (to recalculate votes when the stake changes)
    address public voteBookAddress;

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
    error PubkeyNotChanged();
    error EmptyPubkey();
    error TooManyPubkeyUpdates();

    // redirections
    error AlreadyRedirected();
    error SameRedirectionAuthorizer();
    error Redirected();

    // validators
    error ValidatorNotExists();
    error ValidatorExists();
    error ValidatorNotActive();
    error ValidatorDelegationLimitExceeded();
    error WrongValidatorStatus();

    // requests
    error RequestExists();
    error RequestNotExists();

    // transfers
    error TransfersNotAllowed();
    error TransferFailed();

    // updater
    error SFCAlreadyUpdated();
    error SFCWrongVersion();
    error SFCGovAlreadyUpdated();
    error SFCWrongGovVersion();

    // governance
    error GovVotesRecountFailed();

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
    event Withdrawn(address indexed delegator, uint256 indexed toValidatorID, uint256 indexed wrID, uint256 amount);
    event ClaimedRewards(address indexed delegator, uint256 indexed toValidatorID, uint256 rewards);
    event RestakedRewards(address indexed delegator, uint256 indexed toValidatorID, uint256 rewards);
    event BurntFTM(uint256 amount);
    event UpdatedSlashingRefundRatio(uint256 indexed validatorID, uint256 refundRatio);
    event RefundedSlashedLegacyDelegation(address indexed delegator, uint256 indexed validatorID, uint256 amount);
    event AnnouncedRedirection(address indexed from, address indexed to);

    modifier onlyDriver() {
        if (!isNode(msg.sender)) {
            revert NotDriverAuth();
        }
        _;
    }

    /*
     * Initializer
     */
    function initialize(
        uint256 sealedEpoch,
        uint256 _totalSupply,
        address nodeDriver,
        address _c,
        address owner
    ) external initializer {
        Ownable.initialize(owner);
        currentSealedEpoch = sealedEpoch;
        node = NodeDriverAuth(nodeDriver);
        c = ConstantsManager(_c);
        totalSupply = _totalSupply;
        minGasPrice = GP.initialMinGasPrice();
        getEpochSnapshot[sealedEpoch].endTime = _now();
    }

    receive() external payable {
        revert TransfersNotAllowed();
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

    function setGenesisValidator(address auth, uint256 validatorID, bytes calldata pubkey, uint256 createdTime) external onlyDriver {
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

    function setGenesisDelegation(address delegator, uint256 toValidatorID, uint256 stake) external onlyDriver {
        _rawDelegate(delegator, toValidatorID, stake, false);
        _mintNativeToken(stake);
    }

    function createValidator(bytes calldata pubkey) external payable {
        if (msg.value < c.minSelfStake()) {
            revert InsufficientSelfStake();
        }
        if (pubkey.length == 0) {
            revert EmptyPubkey();
        }
        if (pubkeyHashToValidatorID[keccak256(pubkey)] != 0) {
            revert PubkeyUsedByOtherValidator();
        }
        _createValidator(msg.sender, pubkey);
        _delegate(msg.sender, lastValidatorID, msg.value);
    }

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

    function recountVotes(address delegator, address validatorAuth, bool strict, uint256 gas) external {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = voteBookAddress.call{gas: gas}(
            abi.encodeWithSignature("recountVotes(address,address)", delegator, validatorAuth)
        );
        if (!success && strict) {
            revert GovVotesRecountFailed();
        }
    }

    function delegate(uint256 toValidatorID) external payable {
        _delegate(msg.sender, toValidatorID, msg.value);
    }

    function withdraw(uint256 toValidatorID, uint256 wrID) public {
        _withdraw(msg.sender, toValidatorID, wrID, _receiverOf(msg.sender));
    }

    function deactivateValidator(uint256 validatorID, uint256 status) external onlyDriver {
        if (status == OK_STATUS) {
            revert WrongValidatorStatus();
        }

        _setValidatorDeactivated(validatorID, status);
        _syncValidator(validatorID, false);
        address validatorAddr = getValidator[validatorID].auth;
        _recountVotes(validatorAddr, validatorAddr, false);
    }

    function stashRewards(address delegator, uint256 toValidatorID) external {
        if (!_stashRewards(delegator, toValidatorID)) {
            revert NothingToStash();
        }
    }

    // burnFTM allows SFC to burn an arbitrary amount of FTM tokens
    function burnFTM(uint256 amount) external onlyOwner {
        _burnFTM(amount);
    }

    function updateTreasuryAddress(address v) external onlyOwner {
        treasuryAddress = v;
    }

    function updateConstsAddress(address v) external onlyOwner {
        c = ConstantsManager(v);
    }

    function updateVoteBookAddress(address v) external onlyOwner {
        voteBookAddress = v;
    }

    function constsAddress() external view returns (address) {
        return address(c);
    }

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

    function rewardsStash(address delegator, uint256 validatorID) public view returns (uint256) {
        return _rewardsStash[delegator][validatorID];
    }

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

    function restakeRewards(uint256 toValidatorID) public {
        address delegator = msg.sender;
        uint256 rewards = _claimRewards(delegator, toValidatorID);

        _delegate(delegator, toValidatorID, rewards);
        emit RestakedRewards(delegator, toValidatorID, rewards);
    }

    function currentEpoch() public view returns (uint256) {
        return currentSealedEpoch + 1;
    }

    function getSelfStake(uint256 validatorID) public view returns (uint256) {
        return getStake[getValidator[validatorID].auth][validatorID];
    }

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

    function isSlashed(uint256 validatorID) public view returns (bool) {
        return getValidator[validatorID].status & CHEATER_MASK != 0;
    }

    function pendingRewards(address delegator, uint256 toValidatorID) public view returns (uint256) {
        uint256 reward = _newRewards(delegator, toValidatorID);
        return _rewardsStash[delegator][toValidatorID] + reward;
    }

    function _checkDelegatedStakeLimit(uint256 validatorID) internal view returns (bool) {
        return
            getValidator[validatorID].receivedStake <=
            (getSelfStake(validatorID) * c.maxDelegatedRatio()) / Decimal.unit();
    }

    function isNode(address addr) internal view virtual returns (bool) {
        return addr == address(node);
    }

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

        _recountVotes(delegator, getValidator[toValidatorID].auth, strict);
    }

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

        _recountVotes(delegator, getValidator[toValidatorID].auth, strict);
    }

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

        emit Withdrawn(delegator, toValidatorID, wrID, amount);
    }

    function _highestPayableEpoch(uint256 validatorID) internal view returns (uint256) {
        if (getValidator[validatorID].deactivatedEpoch != 0) {
            if (currentSealedEpoch < getValidator[validatorID].deactivatedEpoch) {
                return currentSealedEpoch;
            }
            return getValidator[validatorID].deactivatedEpoch;
        }
        return currentSealedEpoch;
    }

    function _newRewards(address delegator, uint256 toValidatorID) internal view returns (uint256) {
        uint256 stashedUntil = stashedRewardsUntilEpoch[delegator][toValidatorID];
        uint256 payableUntil = _highestPayableEpoch(toValidatorID);
        uint256 wholeStake = getStake[delegator][toValidatorID];
        uint256 fullReward = _newRewardsOf(wholeStake, toValidatorID, stashedUntil, payableUntil);
        return fullReward;
    }

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

    function _stashRewards(address delegator, uint256 toValidatorID) internal returns (bool updated) {
        uint256 nonStashedReward = _newRewards(delegator, toValidatorID);
        stashedRewardsUntilEpoch[delegator][toValidatorID] = _highestPayableEpoch(toValidatorID);
        _rewardsStash[delegator][toValidatorID] += nonStashedReward;
        return nonStashedReward != 0;
    }

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

    function _burnFTM(uint256 amount) internal {
        if (amount != 0) {
            payable(address(0)).transfer(amount);
            emit BurntFTM(amount);
        }
    }

    function epochEndTime(uint256 epoch) internal view returns (uint256) {
        return getEpochSnapshot[epoch].endTime;
    }

    function _redirected(address addr) internal view returns (bool) {
        return getRedirection[addr] != address(0);
    }

    function _receiverOf(address addr) internal view returns (address payable) {
        address to = getRedirection[addr];
        if (to == address(0)) {
            return payable(address(uint160(addr)));
        }
        return payable(address(uint160(to)));
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

    function _createValidator(address auth, bytes memory pubkey) internal {
        uint256 validatorID = ++lastValidatorID;
        _rawCreateValidator(auth, validatorID, pubkey, OK_STATUS, currentEpoch(), _now(), 0, 0);
    }

    function _rawCreateValidator(
        address auth,
        uint256 validatorID,
        bytes memory pubkey,
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
        pubkeyHashToValidatorID[keccak256(pubkey)] = validatorID;

        emit CreatedValidator(validatorID, auth, createdEpoch, createdTime);
        if (deactivatedEpoch != 0) {
            emit DeactivatedValidator(validatorID, deactivatedEpoch, deactivatedTime);
        }
        if (status != 0) {
            emit ChangedValidatorStatus(validatorID, status);
        }
    }

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

    function _mintNativeToken(uint256 amount) internal {
        // balance will be increased after the transaction is processed
        node.incBalance(address(this), amount);
        totalSupply = totalSupply + amount;
    }

    function _recountVotes(address delegator, address validatorAuth, bool strict) internal {
        if (voteBookAddress != address(0)) {
            // Don't allow recountVotes to use up all the gas
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = voteBookAddress.call{gas: 8000000}(
                abi.encodeWithSignature("recountVotes(address,address)", delegator, validatorAuth)
            );
            // Don't revert if recountVotes failed unless strict mode enabled
            if (!success && strict) {
                revert GovVotesRecountFailed();
            }
        }
    }

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

    function _validatorExists(uint256 validatorID) internal view returns (bool) {
        return getValidator[validatorID].createdTime != 0;
    }

    function _calcValidatorCommission(uint256 rawReward, uint256 commission) internal pure returns (uint256) {
        return (rawReward * commission) / Decimal.unit();
    }

    function _now() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}
