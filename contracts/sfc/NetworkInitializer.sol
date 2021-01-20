pragma solidity ^0.5.0;

import "./SFC.sol";
import "./NodeDriver.sol";

contract NetworkInitializer {
    // Initialize NodeDriverAuth, NodeDriver and SFC in one call to allow fewer genesis transactions
    function initializeAll(uint256 sealedEpoch, uint256 totalSupply, address _sfc, address _auth, address _driver, address _owner) external {
        NodeDriver(_driver).initialize(_auth, _auth);
        NodeDriverAuth(_auth).initialize(_sfc, _driver, _owner);
        SFC(_sfc).initialize(sealedEpoch, totalSupply, _auth, _owner);
        selfdestruct(address(0));
    }
}
