pragma solidity ^0.5.0;
import "../sfc/ConstantsManager.sol";

contract UnitTestConstantsManager is ConstantsManager {
    function updateMinSelfStake(uint256 v) onlyAnyOwner external {
        minSelfStake = v;
    }

    function updateBaseRewardPerSecond(uint256 v) onlyAnyOwner external {
        baseRewardPerSecond = v;
    }

    function updateGasPriceBalancingCounterweight(uint256 v) onlyOwner external {
        gasPriceBalancingCounterweight = v;
    }

    function updateOfflinePenaltyThresholdTime(uint256 v) onlyAnyOwner external {
        offlinePenaltyThresholdTime = v;
    }

    function updateTargetGasPowerPerSecond(uint256 v) onlyOwner external {
        targetGasPowerPerSecond = v;
    }
}
