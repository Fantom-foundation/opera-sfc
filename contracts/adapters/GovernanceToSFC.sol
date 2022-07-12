pragma solidity ^0.5.0;

import "../ownership/Ownable.sol";
import "../common/Initializable.sol";

/**
* @dev `GovernanceToSFC.sol` is a contract module which provides a bridge from the governance 
* contract to SFC to pull proposal data.
*/

interface Governance {
    function getActiveProposals() external view returns (uint256);
}

contract GovernanceToSFC is Ownable {
    Governance internal governance;

    event GovernanceUpdated(address indexed previousAddress, address indexed newAddress);

    /**
     * @dev Initializes the contract setting the default governance contract.
     */
    function initialize(address _governance) internal initializer {
        governance = Governance(_governance);
        emit GovernanceUpdated(address(0), _governance);
    }

    /**
     * @dev Returns the address of the current governance contract.
     */
    function getGovernance() public view returns (address) {
        return address(governance);
    }

    /**
     * @dev Updates the currently bridged governance contract.
     */
    function updateGovernanceContract(address _governance) public onlyOwner {
        emit GovernanceUpdated(address(governance), _governance);
        governance = Governance(_governance);
    }

    /**
     * @dev Returns the number of active governance proposals.
     */
    function activeProposals() public view returns (uint256) {
        uint256 _activeProposals = governance.getActiveProposals();
        return _activeProposals;
    }

    /**
     * @dev Throws if there are any active proposals.
     */
    modifier noActiveProposals() {
        require(activeProposals() == 0, "GovernanceToSFC: There are active proposals.");
        _;
    }
}
