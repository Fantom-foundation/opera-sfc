// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {Decimal} from "../common/Decimal.sol";
import {SFC} from "../sfc/SFC.sol";
import {ISFC} from "../interfaces/ISFC.sol";
import {NodeDriverAuth} from "../sfc/NodeDriverAuth.sol";
import {NodeDriver} from "../sfc/NodeDriver.sol";
import {UnitTestConstantsManager} from "./UnitTestConstantsManager.sol";

contract UnitTestSFC is SFC {
    uint256 internal time;
    bool public allowedNonNodeCalls;

    function rebaseTime() external {
        time = block.timestamp;
    }

    function advanceTime(uint256 diff) external {
        time += diff;
    }

    function getTime() external view returns (uint256) {
        return time;
    }

    function getBlockTime() external view returns (uint256) {
        return block.timestamp;
    }

    function enableNonNodeCalls() external {
        allowedNonNodeCalls = true;
    }

    function disableNonNodeCalls() external {
        allowedNonNodeCalls = false;
    }

    function _now() internal view override returns (uint256) {
        return time;
    }

    function isNode(address addr) internal view override returns (bool) {
        if (allowedNonNodeCalls) {
            return true;
        }
        return SFC.isNode(addr);
    }
}

contract UnitTestNetworkInitializer {
    function initializeAll(
        uint256 sealedEpoch,
        uint256 totalSupply,
        address payable _sfc,
        address _auth,
        address _driver,
        address _evmWriter,
        address _owner
    ) external {
        NodeDriver(_driver).initialize(_auth, _evmWriter);
        NodeDriverAuth(_auth).initialize(_sfc, _driver, _owner);

        UnitTestConstantsManager consts = new UnitTestConstantsManager();
        consts.initialize();
        consts.updateMinSelfStake(0.3175000 * 1e18);
        consts.updateMaxDelegatedRatio(16 * Decimal.unit());
        consts.updateValidatorCommission((15 * Decimal.unit()) / 100);
        consts.updateBurntFeeShare((20 * Decimal.unit()) / 100);
        consts.updateTreasuryFeeShare((10 * Decimal.unit()) / 100);
        consts.updateWithdrawalPeriodEpochs(3);
        consts.updateWithdrawalPeriodTime(60 * 60 * 24 * 7);
        consts.updateBaseRewardPerSecond(6183414351851851852);
        consts.updateOfflinePenaltyThresholdTime(3 days);
        consts.updateOfflinePenaltyThresholdBlocksNum(1000);
        consts.updateTargetGasPowerPerSecond(2000000);
        consts.updateGasPriceBalancingCounterweight(6 * 60 * 60);
        consts.updateAverageUptimeEpochWindow(10);
        consts.updateMinAverageUptime(0); // check disabled by default
        consts.transferOwnership(_owner);

        ISFC(_sfc).initialize(sealedEpoch, totalSupply, _auth, address(consts), _owner);
    }
}
