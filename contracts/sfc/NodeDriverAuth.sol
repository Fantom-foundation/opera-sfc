// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ISFC} from "../interfaces/ISFC.sol";
import {NodeDriver} from "./NodeDriver.sol";
import {INodeDriverExecutable} from "../interfaces/INodeDriverExecutable.sol";

/**
 * @custom:security-contact security@fantom.foundation
 */
contract NodeDriverAuth is OwnableUpgradeable, UUPSUpgradeable {
    ISFC internal sfc;
    NodeDriver internal driver;

    error NotSFC();
    error NotDriver();
    error NotContract();
    error SelfCodeHashMismatch();
    error DriverCodeHashMismatch();
    error RecipientNotSFC();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Initialize NodeDriverAuth, NodeDriver and SFC in one call to allow fewer genesis transactions
    function initialize(address payable _sfc, address _driver, address _owner) external initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();
        driver = NodeDriver(_driver);
        sfc = ISFC(_sfc);
    }

    /// Override the upgrade authorization check to allow upgrades only from the owner.
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// Callable only by SFC contract.
    modifier onlySFC() {
        if (msg.sender != address(sfc)) {
            revert NotSFC();
        }
        _;
    }

    /// Callable only by NodeDriver (mediates messages from the network client)
    modifier onlyDriver() {
        if (msg.sender != address(driver)) {
            revert NotDriver();
        }
        _;
    }

    function _execute(address executable, address newOwner, bytes32 selfCodeHash, bytes32 driverCodeHash) internal {
        _transferOwnership(executable);
        INodeDriverExecutable(executable).execute();
        _transferOwnership(newOwner);
        //require(driver.backend() == address(this), "ownership of driver is lost");
        if (_getCodeHash(address(this)) != selfCodeHash) {
            revert SelfCodeHashMismatch();
        }
        if (_getCodeHash(address(driver)) != driverCodeHash) {
            revert DriverCodeHashMismatch();
        }
    }

    /// Execute a batch update of network configuration.
    /// Run given contract with a permission of the NodeDriverAuth owner.
    /// Does not allow changing NodeDriver and NodeDriverAuth code.
    function execute(address executable) external onlyOwner {
        _execute(executable, owner(), _getCodeHash(address(this)), _getCodeHash(address(driver)));
    }

    /// Execute a batch update of network configuration.
    /// Run given contract with a permission of the NodeDriverAuth owner.
    /// Allows changing NodeDriver and NodeDriverAuth code.
    function mutExecute(
        address executable,
        address newOwner,
        bytes32 selfCodeHash,
        bytes32 driverCodeHash
    ) external onlyOwner {
        _execute(executable, newOwner, selfCodeHash, driverCodeHash);
    }

    /// Mint native token. To be used by SFC for minting validators rewards.
    function incBalance(address acc, uint256 diff) external onlySFC {
        if (acc != address(sfc)) {
            revert RecipientNotSFC();
        }
        driver.setBalance(acc, address(acc).balance + diff);
    }

    /// Upgrade code of given contract by coping it from other deployed contract.
    /// Avoids setting code to an external address.
    function upgradeCode(address acc, address from) external onlyOwner {
        if (!isContract(acc) || !isContract(from)) {
            revert NotContract();
        }
        driver.copyCode(acc, from);
    }

    /// Upgrade code of given contract by coping it from other deployed contract.
    /// Does not avoid setting code to an external address. (DANGEROUS!)
    function copyCode(address acc, address from) external onlyOwner {
        driver.copyCode(acc, from);
    }

    /// Increment nonce of the given account.
    function incNonce(address acc, uint256 diff) external onlyOwner {
        driver.incNonce(acc, diff);
    }

    /// Update network rules by providing a JSON patch.
    function updateNetworkRules(bytes calldata diff) external onlyOwner {
        driver.updateNetworkRules(diff);
    }

    /// Update advertised network version.
    function updateNetworkVersion(uint256 version) external onlyOwner {
        driver.updateNetworkVersion(version);
    }

    /// Enforce sealing given number of epochs.
    function advanceEpochs(uint256 num) external onlyOwner {
        driver.advanceEpochs(num);
    }

    /// Update weight of a validator. Used to propagate a stake change from SFC to the client.
    function updateValidatorWeight(uint256 validatorID, uint256 value) external onlySFC {
        driver.updateValidatorWeight(validatorID, value);
    }

    /// Update public key of a validator. Used to propagate a change from SFC to the client.
    function updateValidatorPubkey(uint256 validatorID, bytes calldata pubkey) external onlySFC {
        driver.updateValidatorPubkey(validatorID, pubkey);
    }

    /// Set an initial validator into SFC. Called only as part of network initialization/genesis file generating.
    function setGenesisValidator(
        address auth,
        uint256 validatorID,
        bytes calldata pubkey,
        uint256 createdTime
    ) external onlyDriver {
        sfc.setGenesisValidator(auth, validatorID, pubkey, createdTime);
    }

    /// Set an initial delegation. Called only as part of network initialization/genesis file generating.
    function setGenesisDelegation(address delegator, uint256 toValidatorID, uint256 stake) external onlyDriver {
        sfc.setGenesisDelegation(delegator, toValidatorID, stake);
    }

    /// Deactivate a validator. Called by network node when a double-sign of the given validator is registered.
    /// Is called before sealEpoch() call.
    function deactivateValidator(uint256 validatorID, uint256 status) external onlyDriver {
        sfc.deactivateValidator(validatorID, status);
    }

    /// Seal epoch. Called BEFORE epoch sealing made by the client itself.
    function sealEpoch(
        uint256[] calldata offlineTimes,
        uint256[] calldata offlineBlocks,
        uint256[] calldata uptimes,
        uint256[] calldata originatedTxsFee
    ) external onlyDriver {
        sfc.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFee);
    }

    /// Seal epoch. Called AFTER epoch sealing made by the client itself.
    function sealEpochValidators(uint256[] calldata nextValidatorIDs) external onlyDriver {
        sfc.sealEpochValidators(nextValidatorIDs);
    }

    function isContract(address account) internal view returns (bool) {
        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function _getCodeHash(address addr) internal view returns (bytes32) {
        bytes32 codeHash;
        assembly {
            codeHash := extcodehash(addr)
        }
        return codeHash;
    }
}
