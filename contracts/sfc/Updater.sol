pragma solidity ^0.5.0;

import "./NodeDriver.sol";
import "./SFC.sol";

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

    constructor(address _sfcFrom, address _sfcLib, address _sfcConsts, address _govTo, address _govFrom, address _voteBook, address _owner) public {
        sfcFrom = _sfcFrom;
        sfcLib = _sfcLib;
        sfcConsts = _sfcConsts;
        govTo = _govTo;
        govFrom = _govFrom;
        voteBook = _voteBook;
        owner = _owner;
        address payable sfcTo = 0xFC00FACE00000000000000000000000000000000;
        require(sfcFrom != address(0) && sfcLib != address(0) && sfcConsts != address(0) && govTo != address(0) && govFrom != address(0) && voteBook != address(0) && owner != address(0), "0 address");
        require(Version(sfcTo).version() == "303", "SFC already updated");
        require(Version(sfcFrom).version() == "304", "wrong SFC version");
        require(GovVersion(govTo).version() == "0001", "gov already updated");
        require(GovVersion(govFrom).version() == "0002", "wrong gov version");
    }

    function execute() external {
        address payable sfcTo = 0xFC00FACE00000000000000000000000000000000;

        ConstantsManager consts = ConstantsManager(sfcConsts);
        consts.initialize();
        consts.updateMinSelfStake(500000 * 1e18);
        consts.updateMaxDelegatedRatio(16 * Decimal.unit());
        consts.updateValidatorCommission((15 * Decimal.unit()) / 100);
        consts.updateBurntFeeShare((20 * Decimal.unit()) / 100);
        consts.updateTreasuryFeeShare((10 * Decimal.unit()) / 100);
        consts.updateUnlockedRewardRatio((30 * Decimal.unit()) / 100);
        consts.updateMinLockupDuration(86400 * 14);
        consts.updateMaxLockupDuration(86400 * 365);
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
