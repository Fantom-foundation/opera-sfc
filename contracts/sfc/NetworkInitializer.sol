pragma solidity ^0.5.0;

import "./SFCI.sol";
import "./NodeDriver.sol";
import "./SFCLib.sol";

contract NetworkInitializer {
    // Initialize NodeDriverAuth, NodeDriver and SFC in one call to allow fewer genesis transactions
    function initializeAll(uint256 sealedEpoch, uint256 totalSupply, address payable _sfc, address _auth, address _driver, address _evmWriter, address _owner) external {
        NodeDriver(_driver).initialize(_auth, _evmWriter);
        NodeDriverAuth(_auth).initialize(_sfc, _driver, _owner);
        SFCI(_sfc).initialize(sealedEpoch, totalSupply, _auth, address(new SFCLib()), _owner);
        selfdestruct(address(0));
    }
}
