// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {ISFC} from "../interfaces/ISFC.sol";
import {NodeDriver} from "./NodeDriver.sol";
import {NodeDriverAuth} from "./NodeDriverAuth.sol";
import {ConstantsManager} from "./ConstantsManager.sol";
import {Decimal} from "../common/Decimal.sol";

/**
 * @custom:security-contact security@fantom.foundation
 */
contract NetworkInitializer {
    // Initialize NodeDriverAuth, NodeDriver and SFC in one call to allow fewer genesis transactions
    function initializeAll(
        uint256 sealedEpoch,
        uint256 totalSupply,
        address payable _sfc,
        address _auth,
        address _driver,
        address _evmWriter,
        address _owner
    ) external {
        NodeDriver(_driver).initialize(_auth, _evmWriter, _owner);
        NodeDriverAuth(_auth).initialize(_sfc, _driver, _owner);

        ConstantsManager consts = new ConstantsManager(address(this));
        consts.updateMinSelfStake(500_000 * Decimal.unit());
        consts.updateMaxDelegatedRatio(16 * Decimal.unit());
        consts.updateValidatorCommission((15 * Decimal.unit()) / 100);
        consts.updateBurntFeeShare(0);
        consts.updateTreasuryFeeShare((90 * Decimal.unit()) / 100);
        consts.updateWithdrawalPeriodEpochs(3);
        consts.updateWithdrawalPeriodTime(60 * 60 * 24 * 7);
        consts.updateBaseRewardPerSecond(1_000);
        consts.updateOfflinePenaltyThresholdTime(5 days);
        consts.updateOfflinePenaltyThresholdBlocksNum(1_000);
        consts.updateAverageUptimeEpochWindow(100);
        consts.updateMinAverageUptime(0); // check disabled by default
        consts.transferOwnership(_owner);

        ISFC(_sfc).initialize(sealedEpoch, totalSupply, _auth, address(consts), _owner);
    }
}
