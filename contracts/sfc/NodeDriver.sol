pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../common/Initializable.sol";
import "../ownership/Ownable.sol";
import "./SFC.sol";

contract NodeDriverAuth is Initializable, Ownable {
    using SafeMath for uint256;

    SFC internal sfc;
    NodeDriver internal driver;

    // Initialize NodeDriverAuth, NodeDriver and SFC in one call to allow fewer genesis transactions
    function initialize(address _sfc, address _driver, address _owner) external initializer {
        Ownable.initialize(_owner);
        driver = NodeDriver(_driver);
        sfc = SFC(_sfc);
    }

    modifier onlySFC() {
        require(msg.sender == address(sfc), "caller is not the SFC contract");
        _;
    }

    modifier onlyDriver() {
        require(msg.sender == address(driver), "caller is not the NodeDriver contract");
        _;
    }

    function migrateTo(address newDriverAuth) external onlyOwner {
        driver.setBackend(newDriverAuth);
    }

    function incBalance(address acc, uint256 diff) external onlySFC {
        require(acc == address(sfc), "recipient is not the SFC contract");
        driver.setBalance(acc, address(acc).balance.add(diff));
    }

    function upgradeCode(address acc, address from) external onlyOwner {
        require(isContract(acc) && isContract(from), "not a contract");
        driver.copyCode(acc, from);
    }

    function copyCode(address acc, address from) external onlyOwner {
        driver.copyCode(acc, from);
    }

    function incNonce(address acc, uint256 diff) external onlyOwner {
        driver.incNonce(acc, diff);
    }

    function updateNetworkRules(bytes calldata diff) external onlyOwner {
        driver.updateNetworkRules(diff);
    }

    function updateNetworkVersion(uint256 version) external onlyOwner {
        driver.updateNetworkVersion(version);
    }

    function advanceEpochs(uint256 num) external onlyOwner {
        driver.advanceEpochs(num);
    }

    function updateValidatorWeight(uint256 validatorID, uint256 value) external onlySFC {
        driver.updateValidatorWeight(validatorID, value);
    }

    function updateValidatorPubkey(uint256 validatorID, bytes calldata pubkey) external onlySFC {
        driver.updateValidatorPubkey(validatorID, pubkey);
    }

    function setGenesisValidator(address _auth, uint256 validatorID, bytes calldata pubkey, uint256 status, uint256 createdEpoch, uint256 createdTime, uint256 deactivatedEpoch, uint256 deactivatedTime) external onlyDriver {
        sfc.setGenesisValidator(_auth, validatorID, pubkey, status, createdEpoch, createdTime, deactivatedEpoch, deactivatedTime);
    }

    function setGenesisDelegation(address delegator, uint256 toValidatorID, uint256 stake, uint256 lockedStake, uint256 lockupFromEpoch, uint256 lockupEndTime, uint256 lockupDuration, uint256 earlyUnlockPenalty, uint256 rewards) external onlyDriver {
        sfc.setGenesisDelegation(delegator, toValidatorID, stake, lockedStake, lockupFromEpoch, lockupEndTime, lockupDuration, earlyUnlockPenalty, rewards);
    }

    function deactivateValidator(uint256 validatorID, uint256 status) external onlyDriver {
        sfc.deactivateValidator(validatorID, status);
    }

    function sealEpochValidators(uint256[] calldata nextValidatorIDs) external onlyDriver {
        sfc.sealEpochValidators(nextValidatorIDs);
    }

    function sealEpoch(uint256[] calldata offlineTimes, uint256[] calldata offlineBlocks, uint256[] calldata uptimes, uint256[] calldata originatedTxsFee) external onlyDriver {
        sfc.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFee);
    }

    function isContract(address account) internal view returns (bool) {
        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }
}

contract NodeDriver is Initializable {
    SFC internal sfc;
    NodeDriver internal backend;
    EVMWriter internal evmWriter;

    event UpdatedBackend(address indexed backend);

    function setBackend(address _backend) external onlyBackend {
        emit UpdatedBackend(_backend);
        backend = NodeDriver(_backend);
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
        backend = NodeDriver(_backend);
        emit UpdatedBackend(_backend);
        evmWriter = EVMWriter(_evmWriterAddress);
    }

    function setBalance(address acc, uint256 value) external onlyBackend {
        evmWriter.setBalance(acc, value);
    }

    function copyCode(address acc, address from) external onlyBackend {
        evmWriter.copyCode(acc, from);
    }

    function swapCode(address acc, address with) external onlyBackend {
        evmWriter.swapCode(acc, with);
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

    function setGenesisValidator(address _auth, uint256 validatorID, bytes calldata pubkey, uint256 status, uint256 createdEpoch, uint256 createdTime, uint256 deactivatedEpoch, uint256 deactivatedTime) external onlyNode {
        backend.setGenesisValidator(_auth, validatorID, pubkey, status, createdEpoch, createdTime, deactivatedEpoch, deactivatedTime);
    }

    function setGenesisDelegation(address delegator, uint256 toValidatorID, uint256 stake, uint256 lockedStake, uint256 lockupFromEpoch, uint256 lockupEndTime, uint256 lockupDuration, uint256 earlyUnlockPenalty, uint256 rewards) external onlyNode {
        backend.setGenesisDelegation(delegator, toValidatorID, stake, lockedStake, lockupFromEpoch, lockupEndTime, lockupDuration, earlyUnlockPenalty, rewards);
    }

    function deactivateValidator(uint256 validatorID, uint256 status) external onlyNode {
        backend.deactivateValidator(validatorID, status);
    }

    function sealEpochValidators(uint256[] calldata nextValidatorIDs) external onlyNode {
        backend.sealEpochValidators(nextValidatorIDs);
    }

    function sealEpoch(uint256[] calldata offlineTimes, uint256[] calldata offlineBlocks, uint256[] calldata uptimes, uint256[] calldata originatedTxsFee) external onlyNode {
        backend.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFee);
    }
}

interface EVMWriter {
    function setBalance(address acc, uint256 value) external;

    function copyCode(address acc, address from) external;

    function swapCode(address acc, address with) external;

    function setStorage(address acc, bytes32 key, bytes32 value) external;

    function incNonce(address acc, uint256 diff) external;
}
