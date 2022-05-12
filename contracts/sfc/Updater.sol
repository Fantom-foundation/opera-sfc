pragma solidity ^0.5.0;

import "./NodeDriver.sol";
import "./SFC.sol";

contract Updater is Ownable {
    function initialize() external initializer {
        Ownable.initialize(msg.sender);
    }

    function execute(address sfcFrom, address nodeFrom, address nodeAuthFrom) external onlyOwner {
        address sfcTo = 0xFC00FACE00000000000000000000000000000000;
        address nodeTo = 0xd100A01E00000000000000000000000000000000;
        address nodeAuthTo = 0xD100ae0000000000000000000000000000000000;
        require(Version(sfcTo).version() != "303", "already updated");
        NodeDriverAuth nodeAuth = NodeDriverAuth(nodeAuthTo);
        nodeAuth.upgradeCode(sfcTo, sfcFrom);
        nodeAuth.upgradeCode(nodeTo, nodeFrom);
        nodeAuth.upgradeCode(nodeAuthTo, nodeAuthFrom);
        nodeAuth.transferOwnership(msg.sender);
    }

    function transferOwnershipOf(address target, address newOwner) external onlyOwner {
        Ownable(target).transferOwnership(newOwner);
    }

    function call(address target, bytes calldata data) external onlyOwner {
        (bool success, bytes memory result) = target.call(data);
        require(success);
        result;
    }
}
