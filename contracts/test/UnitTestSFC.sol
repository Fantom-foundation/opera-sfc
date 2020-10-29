pragma solidity ^0.5.0;

import "../sfc/SFC.sol";

contract UnitTestSFC is SFC {
    function minSelfStake() public pure returns (uint256) {
        // 3.175000 FTM
        return 3.175000 * 1e18;
    }

    function _sealEpoch(uint256[] calldata offlineTimes, uint256[] calldata offlineBlocks, uint256[] calldata uptimes, uint256[] calldata originatedTxsFee) external {
        __sealEpoch(offlineTimes, offlineBlocks, uptimes, originatedTxsFee);
    }

    function _sealEpochValidators(uint256[] calldata nextValidatorIDs) external {
        __sealEpochValidators(nextValidatorIDs);
    }

    uint256 public time;

    function rebaseTime() external {
        time = block.timestamp;
    }

    function advanceTime(uint256 diff) external {
        time += diff;
    }

    function _now() internal view returns(uint256) {
        return time;
    }
}
