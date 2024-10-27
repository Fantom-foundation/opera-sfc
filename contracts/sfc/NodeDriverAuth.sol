// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Initializable} from "../common/Initializable.sol";
import {Ownable} from "../ownership/Ownable.sol";
import {ISFC} from "../interfaces/ISFC.sol";
import {NodeDriver} from "./NodeDriver.sol";
import {INodeDriverExecutable} from "../interfaces/INodeDriverExecutable.sol";

contract NodeDriverAuth is Initializable, Ownable {
    ISFC internal sfc;
    NodeDriver internal driver;

    error NotSFC();
    error NotDriver();
    error NotContract();
    error SelfCodeHashMismatch();
    error DriverCodeHashMismatch();
    error RecipientNotSFC();

    // Initialize NodeDriverAuth, NodeDriver and SFC in one call to allow fewer genesis transactions
    function initialize(address payable _sfc, address _driver, address _owner) external initializer {
        Ownable.initialize(_owner);
        driver = NodeDriver(_driver);
        sfc = ISFC(_sfc);
    }

    modifier onlySFC() {
        if (msg.sender != address(sfc)) {
            revert NotSFC();
        }
        _;
    }

    modifier onlyDriver() {
        if (msg.sender != address(driver)) {
            revert NotDriver();
        }
        _;
    }

    function migrateTo(address newDriverAuth) external onlyOwner {
        driver.setBackend(newDriverAuth);
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

    function execute(address executable) external onlyOwner {
        _execute(executable, owner(), _getCodeHash(address(this)), _getCodeHash(address(driver)));
    }

    function mutExecute(
        address executable,
        address newOwner,
        bytes32 selfCodeHash,
        bytes32 driverCodeHash
    ) external onlyOwner {
        _execute(executable, newOwner, selfCodeHash, driverCodeHash);
    }

    function incBalance(address acc, uint256 diff) external onlySFC {
        if (acc != address(sfc)) {
            revert RecipientNotSFC();
        }
        driver.setBalance(acc, address(acc).balance + diff);
    }

    function upgradeCode(address acc, address from) external onlyOwner {
        if (!isContract(acc) || !isContract(from)) {
            revert NotContract();
        }
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

    function updateMinGasPrice(uint256 minGasPrice) external onlySFC {
        // prettier-ignore
        driver.updateNetworkRules(bytes(strConcat("{\"Economy\":{\"MinGasPrice\":", uint256ToStr(minGasPrice), "}}")));
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

    function setGenesisValidator(
        address _auth,
        uint256 validatorID,
        bytes calldata pubkey,
        uint256 status,
        uint256 createdEpoch,
        uint256 createdTime,
        uint256 deactivatedEpoch,
        uint256 deactivatedTime
    ) external onlyDriver {
        sfc.setGenesisValidator(
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
    ) external onlyDriver {
        sfc.setGenesisDelegation(
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

    function deactivateValidator(uint256 validatorID, uint256 status) external onlyDriver {
        sfc.deactivateValidator(validatorID, status);
    }

    function sealEpochValidators(uint256[] calldata nextValidatorIDs) external onlyDriver {
        sfc.sealEpochValidators(nextValidatorIDs);
    }

    function sealEpoch(
        uint256[] calldata offlineTimes,
        uint256[] calldata offlineBlocks,
        uint256[] calldata uptimes,
        uint256[] calldata originatedTxsFee,
        uint256 usedGas
    ) external onlyDriver {
        sfc.sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFee, usedGas);
    }

    function isContract(address account) internal view returns (bool) {
        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function decimalsNum(uint256 num) internal pure returns (uint256) {
        uint256 decimals;
        while (num != 0) {
            decimals++;
            num /= 10;
        }
        return decimals;
    }

    function uint256ToStr(uint256 num) internal pure returns (string memory) {
        if (num == 0) {
            return "0";
        }
        uint256 decimals = decimalsNum(num);
        bytes memory bstr = new bytes(decimals);
        uint256 strIdx = decimals - 1;
        while (num != 0) {
            bstr[strIdx] = bytes1(uint8(48 + (num % 10)));
            num /= 10;
            if (strIdx > 0) {
                strIdx--;
            }
        }
        return string(bstr);
    }

    function strConcat(string memory _a, string memory _b, string memory _c) internal pure returns (string memory) {
        bytes memory _ba = bytes(_a);
        bytes memory _bb = bytes(_b);
        bytes memory _bc = bytes(_c);
        string memory abc = new string(_ba.length + _bb.length + _bc.length);
        bytes memory babc = bytes(abc);
        uint256 k = 0;
        uint256 i = 0;
        for (i = 0; i < _ba.length; i++) {
            babc[k++] = _ba[i];
        }
        for (i = 0; i < _bb.length; i++) {
            babc[k++] = _bb[i];
        }
        for (i = 0; i < _bc.length; i++) {
            babc[k++] = _bc[i];
        }
        return string(babc);
    }

    function _getCodeHash(address addr) internal view returns (bytes32) {
        bytes32 codeHash;
        assembly {
            codeHash := extcodehash(addr)
        }
        return codeHash;
    }
}
