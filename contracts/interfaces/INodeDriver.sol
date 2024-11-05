// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

/**
 * @title Node Driver Contract Interface
 * @notice Ensures interaction of on-chain contracts with the Sonic client itself.
 * @dev Methods with onlyNode modifier are called by Sonic internal txs during epoch sealing.
 * @custom:security-contact security@fantom.foundation
 */
interface INodeDriver {
    /// Set an initial validator. Called only as part of network initialization/genesis file generating.
    function setGenesisValidator(
        address auth,
        uint256 validatorID,
        bytes calldata pubkey,
        uint256 createdTime
    ) external;

    /// Set an initial delegation. Called only as part of network initialization/genesis file generating.
    function setGenesisDelegation(address delegator, uint256 toValidatorID, uint256 stake) external;

    /// Deactivate a validator. Called by network node when a double-sign of the given validator is registered.
    /// Is called before sealEpoch() call.
    function deactivateValidator(uint256 validatorID, uint256 status) external;

    /// Seal epoch. Called BEFORE epoch sealing made by the client itself.
    function sealEpoch(
        uint256[] calldata offlineTimes,
        uint256[] calldata offlineBlocks,
        uint256[] calldata uptimes,
        uint256[] calldata originatedTxsFee
    ) external;

    /// Seal epoch. Called AFTER epoch sealing made by the client itself.
    function sealEpochValidators(uint256[] calldata nextValidatorIDs) external;
}
