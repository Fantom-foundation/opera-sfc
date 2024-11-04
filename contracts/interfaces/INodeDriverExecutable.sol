// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

/**
 * @title Node Driver Executable
 * @notice A batch of operations to be executed with NodeDriver permissions.
 * @notice Contracts implementing this interface should be executed using NodeDriverAuth.execute() or mutExecute().
 * @custom:security-contact security@fantom.foundation
 */
interface INodeDriverExecutable {
    function execute() external;
}
