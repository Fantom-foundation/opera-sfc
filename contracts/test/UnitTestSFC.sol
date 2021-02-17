// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "../sfc/SFC.sol";

contract UnitTestSFC is SFC {
    uint256 public time;
    bool public allowedNonNodeCalls;

//    function minSelfStake() public pure returns (uint256) {
//        // 0.3175000 FTM
//        return 0.3175000 * 1e18;
//    }

    function rebaseTime() external {
        time = block.timestamp;
    }

    function advanceTime(uint256 diff) external {
        time += diff;
    }

    function _now() internal view override returns (uint256) {
        return time;
    }

    function getTime() external view returns (uint256) {
        return time;
    }

    function getBlockTime() external view returns (uint256) {
        return SFC._now();
    }

    function highestLockupEpoch(address delegator, uint256 validatorID) external view returns (uint256) {
        return _highestLockupEpoch(delegator, validatorID);
    }

    function enableNonNodeCalls() external {
        allowedNonNodeCalls = true;
    }

    function disableNonNodeCalls() external {
        allowedNonNodeCalls = false;
    }

    function isNode(address addr) internal view returns (bool) {
        if (allowedNonNodeCalls) {
            return true;
        }
        return SFC.isNode(addr);
    }
}


