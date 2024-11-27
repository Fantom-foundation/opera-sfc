// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

contract FailingReceiver {
    // Fallback function to reject any received Ether
    receive() external payable {
        revert("Forced transfer failure");
    }
}
