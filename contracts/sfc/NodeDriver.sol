pragma solidity ^0.5.0;

import "../common/Initializable.sol";
import "../ownership/Ownable.sol";
import "./SFC.sol";

contract NodeDriverAuth is Initializable, Ownable {
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
        driver.transferOwnership(newDriverAuth);
    }

    function incBalance(address acc, uint256 diff) external onlySFC {
        require(acc == address(sfc), "recipient is not the SFC contract");
        driver.incBalance(acc, diff);
    }

    function setBalance(address acc, uint256 value) external {
        if (false) {
            driver.setBalance(acc, value);
        }
        revert("method is disabled");
    }

    function subBalance(address acc, uint256 diff) external {
        if (false) {
            driver.subBalance(acc, diff);
        }
        revert("method is disabled");
    }

    function setCode(address acc, address from) external {
        if (false) {
            driver.setCode(acc, from);
        }
        revert("method is disabled");
    }

    function swapCode(address acc, address with) external {
        if (false) {
            driver.swapCode(acc, with);
        }
        revert("method is disabled");
    }

    function setStorage(address acc, uint256 key, uint256 value) external {
        if (false) {
            driver.setStorage(acc, key, value);
        }
        revert("method is disabled");
    }

    function updateNetworkRules(bytes calldata diff) external onlyOwner {
        driver.updateNetworkRules(diff);
    }

    function updateNetworkVersion(uint256 version) external onlyOwner {
        driver.updateNetworkVersion(version);
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
}

contract NodeDriver is Initializable, Ownable {
    SFC internal sfc;
    NodeDriver internal backend;

    function setBackend(address _backend) external onlyOwner {
        backend = NodeDriver(_backend);
    }

    event IncBalance(address indexed acc, uint256 value);
    event SetBalance(address indexed acc, uint256 value);
    event SubBalance(address indexed acc, uint256 value);
    event SetCode(address indexed acc, address indexed from);
    event SwapCode(address indexed acc, address indexed with);
    event SetStorage(address indexed acc, uint256 key, uint256 value);

    event UpdateValidatorWeight(uint256 indexed validatorID, uint256 weight);
    event UpdateValidatorPubkey(uint256 indexed validatorID, bytes pubkey);

    event UpdateNetworkRules(bytes diff);
    event UpdateNetworkVersion(uint256 version);

    function initialize(address _backend, address _owner) external initializer {
        Ownable.initialize(_owner);
        backend = NodeDriver(_backend);
    }

    function incBalance(address acc, uint256 diff) external onlyOwner {
        emit IncBalance(acc, diff);
    }

    function setBalance(address acc, uint256 value) external onlyOwner {
        emit SetBalance(acc, value);
    }

    function subBalance(address acc, uint256 diff) external onlyOwner {
        emit SubBalance(acc, diff);
    }

    function setCode(address acc, address from) external onlyOwner {
        emit SetCode(acc, from);
    }

    function swapCode(address acc, address with) external onlyOwner {
        emit SwapCode(acc, with);
    }

    function setStorage(address acc, uint256 key, uint256 value) external onlyOwner {
        emit SetStorage(acc, key, value);
    }

    function updateNetworkRules(bytes calldata diff) external onlyOwner {
        emit UpdateNetworkRules(diff);
    }

    function updateNetworkVersion(uint256 version) external onlyOwner {
        emit UpdateNetworkVersion(version);
    }

    function updateValidatorWeight(uint256 validatorID, uint256 value) external onlyOwner {
        emit UpdateValidatorWeight(validatorID, value);
    }

    function updateValidatorPubkey(uint256 validatorID, bytes calldata pubkey) external onlyOwner {
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
