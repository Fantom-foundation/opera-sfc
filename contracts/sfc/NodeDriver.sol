// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {NodeDriverAuth} from "./NodeDriverAuth.sol";
import {IEVMWriter} from "../interfaces/IEVMWriter.sol";
import {INodeDriver} from "../interfaces/INodeDriver.sol";

/**
 * @title Node Driver Contract
 * @notice Ensures interaction of on-chain contracts with the Sonic client itself.
 * @dev Methods with onlyNode modifier are called by Sonic internal txs during epoch sealing.
 * @custom:security-contact security@fantom.foundation
 */
contract NodeDriver is OwnableUpgradeable, UUPSUpgradeable, INodeDriver {
    NodeDriverAuth internal backend;
    IEVMWriter internal evmWriter;

    error NotNode();
    error NotBackend();

    /// Callable only by NodeDriverAuth (which mediates calls from SFC and from admins)
    modifier onlyBackend() {
        if (msg.sender != address(backend)) {
            revert NotBackend();
        }
        _;
    }

    event UpdateValidatorWeight(uint256 indexed validatorID, uint256 weight);
    event UpdateValidatorPubkey(uint256 indexed validatorID, bytes pubkey);

    event UpdateNetworkRules(bytes diff);
    event UpdateNetworkVersion(uint256 version);
    event AdvanceEpochs(uint256 num);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// Initialization is called only once, after the contract deployment.
    /// Because the contract code is written directly into genesis, constructor cannot be used.
    function initialize(address _backend, address _evmWriterAddress, address _owner) external initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();
        backend = NodeDriverAuth(_backend);
        evmWriter = IEVMWriter(_evmWriterAddress);
    }

    /// Override the upgrade authorization check to allow upgrades only from the owner.
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setBalance(address acc, uint256 value) external onlyBackend {
        evmWriter.setBalance(acc, value);
    }

    function copyCode(address acc, address from) external onlyBackend {
        evmWriter.copyCode(acc, from);
    }

    function swapCode(address acc, address where) external onlyBackend {
        evmWriter.swapCode(acc, where);
    }

    function setStorage(address acc, bytes32 key, bytes32 value) external onlyBackend {
        evmWriter.setStorage(acc, key, value);
    }

    function incNonce(address acc, uint256 diff) external onlyBackend {
        evmWriter.incNonce(acc, diff);
    }

    /// Update network rules configuring the chain.
    /// Emitted event is being observed by Sonic client.
    function updateNetworkRules(bytes calldata diff) external onlyBackend {
        emit UpdateNetworkRules(diff);
    }

    /// Update advertised version of the network.
    /// Emitted event is being observed by Sonic client.
    function updateNetworkVersion(uint256 version) external onlyBackend {
        emit UpdateNetworkVersion(version);
    }

    /// Enforce sealing given number of epochs.
    /// Emitted event is being observed by Sonic client.
    function advanceEpochs(uint256 num) external onlyBackend {
        emit AdvanceEpochs(num);
    }

    /// Update weight of a validator. Used to propagate a stake change from SFC to the client.
    /// Emitted event is being observed by Sonic client.
    function updateValidatorWeight(uint256 validatorID, uint256 value) external onlyBackend {
        emit UpdateValidatorWeight(validatorID, value);
    }

    /// Update public key of a validator. Used to propagate a change from SFC to the client.
    /// Emitted event is being observed by Sonic client.
    function updateValidatorPubkey(uint256 validatorID, bytes calldata pubkey) external onlyBackend {
        emit UpdateValidatorPubkey(validatorID, pubkey);
    }

    /// Callable only from Sonic client itself as an internal tx.
    /// Used for propagating network event (validator doublesign, epoch sealing) from node to SFC.
    modifier onlyNode() {
        if (msg.sender != address(0)) {
            revert NotNode();
        }
        _;
    }

    // Methods which are called only by the node

    /// Set an initial validator. Called only as part of network initialization/genesis file generating.
    function setGenesisValidator(
        address auth,
        uint256 validatorID,
        bytes calldata pubkey,
        uint256 createdTime
    ) external onlyNode {
        backend.setGenesisValidator(auth, validatorID, pubkey, createdTime);
    }

    /// Set an initial delegation. Called only as part of network initialization/genesis file generating.
    function setGenesisDelegation(address delegator, uint256 toValidatorID, uint256 stake) external onlyNode {
        backend.setGenesisDelegation(delegator, toValidatorID, stake);
    }

    /// Deactivate a validator. Called by network node when a double-sign of the given validator is registered.
    /// Is called before sealEpoch() call.
    function deactivateValidator(uint256 validatorID, uint256 status) external onlyNode {
        backend.deactivateValidator(validatorID, status);
    }

    /// Seal epoch. Called BEFORE epoch sealing made by the client itself.
    function sealEpoch(
        uint256[] calldata offlineTimes,
        uint256[] calldata offlineBlocks,
        uint256[] calldata uptimes,
        uint256[] calldata originatedTxsFee
    ) external onlyNode {
        backend.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFee);
    }

    /// Seal epoch. Called AFTER epoch sealing made by the client itself.
    function sealEpochValidators(uint256[] calldata nextValidatorIDs) external onlyNode {
        backend.sealEpochValidators(nextValidatorIDs);
    }

    uint256[50] private __gap;
}
