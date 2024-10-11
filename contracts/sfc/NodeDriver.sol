// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Initializable} from "../common/Initializable.sol";
import {NodeDriverAuth} from "./NodeDriverAuth.sol";

interface EVMWriter {
    function setBalance(address acc, uint256 value) external;

    function copyCode(address acc, address from) external;

    function swapCode(address acc, address where) external;

    function setStorage(address acc, bytes32 key, bytes32 value) external;

    function incNonce(address acc, uint256 diff) external;
}

contract NodeDriver is Initializable {
    NodeDriverAuth internal backend;
    EVMWriter internal evmWriter;

    event UpdatedBackend(address indexed backend);

    function setBackend(address _backend) external onlyBackend {
        emit UpdatedBackend(_backend);
        backend = NodeDriverAuth(_backend);
    }

    modifier onlyBackend() {
        require(msg.sender == address(backend), "caller is not the backend");
        _;
    }

    event UpdateValidatorWeight(uint256 indexed validatorID, uint256 weight);
    event UpdateValidatorPubkey(uint256 indexed validatorID, bytes pubkey);

    event UpdateNetworkRules(bytes diff);
    event UpdateNetworkVersion(uint256 version);
    event AdvanceEpochs(uint256 num);

    function initialize(address _backend, address _evmWriterAddress) external initializer {
        backend = NodeDriverAuth(_backend);
        emit UpdatedBackend(_backend);
        evmWriter = EVMWriter(_evmWriterAddress);
    }

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

    function updateNetworkRules(bytes calldata diff) external onlyBackend {
        emit UpdateNetworkRules(diff);
    }

    function updateNetworkVersion(uint256 version) external onlyBackend {
        emit UpdateNetworkVersion(version);
    }

    function advanceEpochs(uint256 num) external onlyBackend {
        emit AdvanceEpochs(num);
    }

    function updateValidatorWeight(uint256 validatorID, uint256 value) external onlyBackend {
        emit UpdateValidatorWeight(validatorID, value);
    }

    function updateValidatorPubkey(uint256 validatorID, bytes calldata pubkey) external onlyBackend {
        emit UpdateValidatorPubkey(validatorID, pubkey);
    }

    modifier onlyNode() {
        require(msg.sender == address(0), "not callable");
        _;
    }

    // Methods which are called only by the node

    function setGenesisValidator(
        address _auth,
        uint256 validatorID,
        bytes calldata pubkey,
        uint256 status,
        uint256 createdEpoch,
        uint256 createdTime,
        uint256 deactivatedEpoch,
        uint256 deactivatedTime
    ) external onlyNode {
        backend.setGenesisValidator(
            _auth,
            validatorID,
            pubkey,
            status,
            createdEpoch,
            createdTime,
            deactivatedEpoch,
            deactivatedTime
        );
    }

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
    ) external onlyNode {
        backend.setGenesisDelegation(
            delegator,
            toValidatorID,
            stake,
            lockedStake,
            lockupFromEpoch,
            lockupEndTime,
            lockupDuration,
            earlyUnlockPenalty,
            rewards
        );
    }

    function deactivateValidator(uint256 validatorID, uint256 status) external onlyNode {
        backend.deactivateValidator(validatorID, status);
    }

    function sealEpochValidators(uint256[] calldata nextValidatorIDs) external onlyNode {
        backend.sealEpochValidators(nextValidatorIDs);
    }

    function sealEpoch(
        uint256[] calldata offlineTimes,
        uint256[] calldata offlineBlocks,
        uint256[] calldata uptimes,
        uint256[] calldata originatedTxsFee
    ) external onlyNode {
        backend.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFee, 841669690);
    }

    function sealEpochV1(
        uint256[] calldata offlineTimes,
        uint256[] calldata offlineBlocks,
        uint256[] calldata uptimes,
        uint256[] calldata originatedTxsFee,
        uint256 usedGas
    ) external onlyNode {
        backend.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFee, usedGas);
    }
}
