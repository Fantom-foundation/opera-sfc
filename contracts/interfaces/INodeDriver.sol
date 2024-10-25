// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface INodeDriver {
    function setGenesisValidator(
        address _auth,
        uint256 validatorID,
        bytes calldata pubkey,
        uint256 status,
        uint256 createdEpoch,
        uint256 createdTime,
        uint256 deactivatedEpoch,
        uint256 deactivatedTime
    ) external;

    function setGenesisDelegation(
        address delegator,
        uint256 toValidatorID,
        uint256 stake,
        uint256 lockedStake,
        uint256 lockupFromEpoch,
        uint256 lockupEndTime,
        uint256 lockupDuration,
        uint256 earlyUnlockPenalty,
        uint256 rewards
    ) external;

    function deactivateValidator(uint256 validatorID, uint256 status) external;

    function sealEpochValidators(uint256[] calldata nextValidatorIDs) external;

    function sealEpoch(
        uint256[] calldata offlineTimes,
        uint256[] calldata offlineBlocks,
        uint256[] calldata uptimes,
        uint256[] calldata originatedTxsFee,
        uint256 usedGas
    ) external;
}
