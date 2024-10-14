// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface ISFCErrors {
    error TransfersNotAllowed();

    // pubkeys
    error PubkeyExists();
    error NotMainNet();
    error MalformedPubkey();
    error NotLegacyValidator();
    error ValidatorDoesNotExist();
    error SamePubkey();
    error PubkeyAllowedOnlyOnce();

    // redirections
    error SameRedirectionAuthorizer();
    error NotAuthorized();
    error AlreadyCompleted();
    error SameAddress();
    error ZeroAddress();
    error NoRequest();
}