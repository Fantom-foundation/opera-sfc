pragma solidity ^0.5.0;

import "./SFC.sol";

contract NodeInterfaceAuth is Initializable {
    address public sfc;
    address public owner;

    function initialize(address _sfc, address _owner) external initializer {
        owner = _owner;
        sfc = _sfc;
    }

    function authorizeIncBalance(address sender, address acc, uint256 /*diff*/) external {
        silenceMutabilityWarning();
        require(sender == sfc, "caller is not the SFC contract");
        require(acc == sfc, "recipient is not the SFC contract");
    }

    function authorizeSetBalance(address /*sender*/, address /*acc*/, uint256 /*value*/) external {
        silenceMutabilityWarning();
        revert("method is disabled");
    }

    function authorizeSubBalance(address /*sender*/, address /*acc*/, uint256 /*diff*/) external {
        silenceMutabilityWarning();
        revert("method is disabled");
    }

    function authorizeSetCode(address /*sender*/, address /*acc*/, address /*from*/) external {
        silenceMutabilityWarning();
        revert("method is disabled");
    }

    function authorizeSwapCode(address /*sender*/, address /*acc*/, address /*with*/) external {
        silenceMutabilityWarning();
        revert("method is disabled");
    }

    function authorizeSetStorage(address /*sender*/, address /*acc*/, uint256 /*key*/, uint256 /*value*/) external {
        silenceMutabilityWarning();
        revert("method is disabled");
    }

    function authorizeUpdateGasPowerAllocationRate(address sender, uint256 short, uint256 long) external {
        silenceMutabilityWarning();
        require(sender == owner, "caller is not the owner");
        require(long <= 280000000, "too large long gas power allocation rate");
        require(short <= 280000000 * 5, "too large short gas power allocation rate");
        require(long >= 280000, "too small long gas power allocation rate");
        require(short >= 280000 * 5, "too small short gas power allocation rate");
    }

    function authorizeUpdateMinGasPrice(address sender, uint256 value) external {
        silenceMutabilityWarning();
        require(sender == owner, "caller is not the owner");
        require(value <= 32.967977168935185184 * 1e18, "too large reward per second");
    }

    function authorizeUpdateValidatorWeight(address sender, uint256 /*validatorID*/, uint256 /*value*/) external {
        silenceMutabilityWarning();
        require(sender == sfc, "caller is not the SFC contract");
    }

    function authorizeUpdateValidatorPubkey(address sender, uint256 /*validatorID*/, bytes calldata /*pubkey*/) external {
        silenceMutabilityWarning();
        require(sender == sfc, "caller is not the SFC contract");
    }

    function silenceMutabilityWarning() internal {
        if (false) {
            address(0).transfer(1);
        }
    }
}

contract NodeInterface is Initializable, Ownable {

    NodeInterfaceAuth internal auth;

    SFC internal sfc;

    function setAuth(address _auth) external onlyOwner {
        auth = NodeInterfaceAuth(_auth);
    }

    function setSFC(address _sfc) external onlyOwner {
        sfc = SFC(_sfc);
    }

    event IncBalance(address indexed acc, uint256 value);
    event SetBalance(address indexed acc, uint256 value);
    event SubBalance(address indexed acc, uint256 value);
    event SetCode(address indexed acc, address indexed from);
    event SwapCode(address indexed acc, address indexed with);
    event SetStorage(address indexed acc, uint256 key, uint256 value);

    event UpdateValidatorWeight(uint256 indexed validatorID, uint256 weight);
    event UpdateValidatorPubkey(uint256 indexed validatorID, bytes pubkey);

    event UpdateGasPowerAllocationRate(uint256 short, uint256 long);
    event UpdateMinGasPrice(uint256 minGasPrice);

    function incBalance(address acc, uint256 diff) external {
        auth.authorizeIncBalance(msg.sender, acc, diff);
        emit IncBalance(acc, diff);
    }

    function setBalance(address acc, uint256 value) external {
        auth.authorizeSetBalance(msg.sender, acc, value);
        emit SetBalance(acc, value);
    }

    function subBalance(address acc, uint256 diff) external {
        auth.authorizeSubBalance(msg.sender, acc, diff);
        emit SubBalance(acc, diff);
    }

    function setCode(address acc, address from) external {
        auth.authorizeSetCode(msg.sender, acc, from);
        emit SetCode(acc, from);
    }

    function swapCode(address acc, address with) external {
        auth.authorizeSwapCode(msg.sender, acc, with);
        emit SwapCode(acc, with);
    }

    function setStorage(address acc, uint256 key, uint256 value) external {
        auth.authorizeSetStorage(msg.sender, acc, key, value);
        emit SetStorage(acc, key, value);
    }

    function updateGasPowerAllocationRate(uint256 short, uint256 long) external {
        auth.authorizeUpdateGasPowerAllocationRate(msg.sender, short, long);
        emit UpdateGasPowerAllocationRate(short, long);
    }

    function updateMinGasPrice(uint256 value) external {
        auth.authorizeUpdateMinGasPrice(msg.sender, value);
        emit UpdateMinGasPrice(value);
    }

    function updateValidatorWeight(uint256 validatorID, uint256 value) external {
        auth.authorizeUpdateValidatorWeight(msg.sender, validatorID, value);
        emit UpdateValidatorWeight(validatorID, value);
    }

    function updateValidatorPubkey(uint256 validatorID, bytes calldata pubkey) external {
        auth.authorizeUpdateValidatorPubkey(msg.sender, validatorID, pubkey);
        emit UpdateValidatorPubkey(validatorID, pubkey);
    }

    modifier onlyNode() {
        require(msg.sender == address(0), "not callable");
        _;
    }

    // Methods which are called only by the node

    function initialize(uint256 sealedEpoch, address _sfc, address _auth, address _owner) external initializer {
        Ownable.initialize(_owner);
        auth = NodeInterfaceAuth(_auth);
        auth.initialize(_sfc, _owner);
        sfc = SFC(_sfc);
        sfc.initialize(sealedEpoch, address(this), _owner);
    }

    function setGenesisValidator(address _auth, uint256 validatorID, bytes calldata pubkey, uint256 status, uint256 createdEpoch, uint256 createdTime, uint256 deactivatedEpoch, uint256 deactivatedTime) external onlyNode {
        sfc._setGenesisValidator(_auth, validatorID, pubkey, status, createdEpoch, createdTime, deactivatedEpoch, deactivatedTime);
    }

    function setGenesisDelegation(address delegator, uint256 toValidatorID, uint256 amount, uint256 rewards) external onlyNode {
        sfc._setGenesisDelegation(delegator, toValidatorID, amount, rewards);
    }

    function deactivateValidator(uint256 validatorID, uint256 status) external onlyNode {
        sfc._deactivateValidator(validatorID, status);
    }

    function sealEpochValidators(uint256[] calldata nextValidatorIDs) external onlyNode {
        sfc._sealEpochValidators(nextValidatorIDs);
    }

    function sealEpoch(uint256[] calldata offlineTimes, uint256[] calldata offlineBlocks, uint256[] calldata uptimes, uint256[] calldata originatedTxsFee) external onlyNode {
        sfc._sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFee);
    }
}
