// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

/**
 * @title Stake Subscriber Interface
 * @notice Used to recount votes from delegators in the governance contract
 * @custom:security-contact security@fantom.foundation
 */
interface IStakeSubscriber {
    function announceStakeChange(address delegator, address validator) external;
}
