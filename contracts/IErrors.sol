// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IErrors {
    // auth
    error NotOwner();
    error NotBackend();
    error NotNode();
    error NotSFC();
    error NotDriver();
    error NotDriverAuth();
    error NotContract();
    error NotAuthorized();

    // initialization
    error ContractInitialized();

    // reentrancy
    error ReentrantCall();

    // addresses
    error ZeroAddress();
    error SameAddress();
    error RecipientNotSFC();

    // values
    error ZeroAmount();
    error ZeroRewards();

    // pubkeys
    error PubkeyExists();
    error MalformedPubkey();
    error SamePubkey();
    error EmptyPubkey();
    error PubkeyAllowedOnlyOnce();

    // redirections
    error SameRedirectionAuthorizer();
    error Redirected();

    // validators
    error ValidatorNotExists();
    error ValidatorExists();
    error ValidatorNotActive();
    error ValidatorDelegationLimitExceeded();
    error WrongValidatorStatus();

    // requests
    error RequestedCompleted();
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

    // node driver
    error SelfCodeHashMismatch();
    error DriverCodeHashMismatch();

    // governance
    error GovVotesRecountFailed();

    // staking
    error LockedStakeGreaterThanTotalStake();
    error InsufficientSelfStake();
    error NotEnoughUnlockedStake();
    error NotEnoughLockedStake();
    error NotEnoughTimePassed();
    error NotEnoughEpochsPassed();
    error StakeIsFullySlashed();
    error IncorrectDuration();
    error ValidatorLockupTooShort();
    error TooManyReLocks();
    error TooFrequentReLocks();
    error LockupDurationDecreased();
    error AlreadyLockedUp();
    error NotLockedUp();

    // stashing
    error NothingToStash();

    // slashing
    error ValidatorNotSlashed();
    error RefundRatioTooHigh();
}
