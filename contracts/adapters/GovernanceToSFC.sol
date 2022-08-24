pragma solidity ^0.5.0;

import "../ownership/Ownable.sol";

/**
* @dev `GovernanceToSFC.sol` is a contract module which provides a bridge from the governance 
* contract to SFC to pull proposal data.
*/

interface Governance {
    function getActiveProposals() external view returns (uint256);
}

contract GovernanceToSFC is Ownable {
    Governance internal governance;

    //event GovernanceUpdated(address indexed previousAddress, address indexed newAddress);

    /**
     * @dev Updates the currently bridged governance contract.
     */
    function updateGovernanceContract(address _governance) public onlyOwner {
        //emit GovernanceUpdated(address(governance), _governance);
        governance = Governance(_governance);
    }
}
