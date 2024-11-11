// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {ConstantsManager} from "../sfc/ConstantsManager.sol";

contract UnitTestConstantsManager is ConstantsManager {
    constructor(address owner) ConstantsManager(owner) {}

    function updateMinSelfStake(uint256 v) external override onlyOwner {
        minSelfStake = v;
    }

    function updateBaseRewardPerSecond(uint256 v) external override onlyOwner {
        baseRewardPerSecond = v;
    }

    function updateGasPriceBalancingCounterweight(uint256 v) external override onlyOwner {
        gasPriceBalancingCounterweight = v;
    }

    function updateOfflinePenaltyThresholdTime(uint256 v) external override onlyOwner {
        offlinePenaltyThresholdTime = v;
    }

    function updateTargetGasPowerPerSecond(uint256 v) external override onlyOwner {
        targetGasPowerPerSecond = v;
    }
}
