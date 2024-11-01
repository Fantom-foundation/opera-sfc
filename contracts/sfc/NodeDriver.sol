// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {Initializable} from "../common/Initializable.sol";
import {NodeDriverAuth} from "./NodeDriverAuth.sol";
import {IEVMWriter} from "../interfaces/IEVMWriter.sol";

/**
 * @custom:security-contact security@fantom.foundation
 */
contract NodeDriver is Initializable {
    NodeDriverAuth internal backend;
    IEVMWriter internal evmWriter;

    error NotNode();
    error NotBackend();

    event UpdatedBackend(address indexed backend);

    function setBackend(address _backend) external onlyBackend {
        emit UpdatedBackend(_backend);
        backend = NodeDriverAuth(_backend);
    }

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

    function initialize(address _backend, address _evmWriterAddress) external initializer {
        backend = NodeDriverAuth(_backend);
        emit UpdatedBackend(_backend);
        evmWriter = IEVMWriter(_evmWriterAddress);
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
        if (msg.sender != address(0)) {
            revert NotNode();
        }
        _;
    }

    // Methods which are called only by the node

    function setGenesisValidator(
        address auth,
        uint256 validatorID,
        bytes calldata pubkey,
        uint256 createdTime
    ) external onlyNode {
        backend.setGenesisValidator(auth, validatorID, pubkey, createdTime);
    }

    function setGenesisDelegation(address delegator, uint256 toValidatorID, uint256 stake) external onlyNode {
        backend.setGenesisDelegation(delegator, toValidatorID, stake);
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
