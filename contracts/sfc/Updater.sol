// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Ownable} from "../ownership/Ownable.sol";
import {Decimal} from "../common/Decimal.sol";
import {NodeDriverAuth} from "./NodeDriverAuth.sol";
import {ConstantsManager} from "./ConstantsManager.sol";
import {SFC} from "./SFC.sol";
import {SFCI} from "./SFCI.sol";
import {Version} from "../version/Version.sol";

interface GovI {
    function upgrade(address v) external;
}

interface VoteBookI {
    function initialize(address _owner, address _gov, uint256 _maxProposalsPerVoter) external;
}

interface GovVersion {
    function version() external pure returns (bytes4);
}

contract Updater {
    address public sfcFrom;
    address public sfcLib;
    address public sfcConsts;
    address public govTo;
    address public govFrom;
    address public voteBook;
    address public owner;

    error ZeroAddress();
    error SFCAlreadyUpdated();
    error SFCWrongVersion();
    error SFCGovAlreadyUpdated();
    error SFCWrongGovVersion();

    constructor(
        address _sfcFrom,
        address _sfcLib,
        address _sfcConsts,
        address _govTo,
        address _govFrom,
        address _voteBook,
        address _owner
    ) {
        sfcFrom = _sfcFrom;
        sfcLib = _sfcLib;
        sfcConsts = _sfcConsts;
        govTo = _govTo;
        govFrom = _govFrom;
        voteBook = _voteBook;
        owner = _owner;
        address sfcTo = address(0xFC00FACE00000000000000000000000000000000);
        if (
            sfcFrom == address(0) ||
            sfcLib == address(0) ||
            sfcConsts == address(0) ||
            govTo == address(0) ||
            govFrom == address(0) ||
            voteBook == address(0) ||
            owner == address(0)
        ) {
            revert ZeroAddress();
        }
        if (Version(sfcTo).version() != "303") {
            revert SFCAlreadyUpdated();
        }
        if (Version(sfcFrom).version() != "304") {
            revert SFCWrongVersion();
        }
        if (GovVersion(govTo).version() != "0001") {
            revert SFCGovAlreadyUpdated();
        }
        if (GovVersion(govFrom).version() != "0002") {
            revert SFCWrongGovVersion();
        }
    }

    function execute() external {
        address payable sfcTo = payable(address(0xFC00FACE00000000000000000000000000000000));

        ConstantsManager consts = ConstantsManager(sfcConsts);
        consts.initialize();
        consts.updateMinSelfStake(500000 * 1e18);
        consts.updateMaxDelegatedRatio(16 * Decimal.unit());
        consts.updateValidatorCommission((15 * Decimal.unit()) / 100);
        consts.updateBurntFeeShare((20 * Decimal.unit()) / 100);
        consts.updateTreasuryFeeShare((10 * Decimal.unit()) / 100);
        consts.updateWithdrawalPeriodEpochs(3);
        consts.updateWithdrawalPeriodTime(60 * 60 * 24 * 7);
        consts.updateBaseRewardPerSecond(2668658453701531600);
        consts.updateOfflinePenaltyThresholdTime(5 days);
        consts.updateOfflinePenaltyThresholdBlocksNum(1000);
        consts.updateTargetGasPowerPerSecond(2000000);
        consts.updateGasPriceBalancingCounterweight(3600);
        consts.transferOwnership(owner);

        VoteBookI(voteBook).initialize(owner, govTo, 30);

        NodeDriverAuth nodeAuth = NodeDriverAuth(0xD100ae0000000000000000000000000000000000);
        nodeAuth.upgradeCode(sfcTo, sfcFrom);
        SFCI(sfcTo).updateConstsAddress(sfcConsts);
        SFCI(sfcTo).updateVoteBookAddress(voteBook);
        SFC(sfcTo).updateLibAddress(sfcLib);

        nodeAuth.upgradeCode(govTo, govFrom);
        GovI(govTo).upgrade(voteBook);

        Ownable(sfcTo).transferOwnership(owner);
        nodeAuth.transferOwnership(owner);
    }
}
