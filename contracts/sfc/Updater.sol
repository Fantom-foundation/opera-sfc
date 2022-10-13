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

contract Updater is Ownable {
    function initialize() external initializer {
        Ownable.initialize(msg.sender);
    }

    function execute(address sfcFrom, address sfcLib, address sfcConsts, address govTo, address govFrom, address voteBook) external onlyOwner {
        address payable sfcTo = 0xFC00FACE00000000000000000000000000000000;
        require(sfcFrom != address(0) && sfcLib != address(0) && sfcConsts != address(0) && govTo != address(0) && govFrom != address(0) && voteBook != address(0), "0 address");
        require(Version(sfcTo).version() == "303", "SFC already updated");
        require(Version(sfcFrom).version() == "304", "wrong SFC version");
        require(GovVersion(govTo).version() == "0001", "gov already updated");
        require(GovVersion(govFrom).version() == "0002", "wrong gov version");

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
        consts.updateOfflinePenaltyThresholdTime(3 days);
        consts.updateOfflinePenaltyThresholdBlocksNum(1000);
        consts.updateTargetGasPowerPerSecond(3500000);
        consts.updateGasPriceBalancingCounterweight(3600);
        consts.transferOwnership(msg.sender);

        VoteBookI(voteBook).initialize(msg.sender, govTo, 30);

        NodeDriverAuth nodeAuth = NodeDriverAuth(0xD100ae0000000000000000000000000000000000);
        nodeAuth.upgradeCode(sfcTo, sfcFrom);
        SFCI(sfcTo).updateConstsAddress(sfcConsts);
        SFCI(sfcTo).updateVoteBookAddress(voteBook);
        SFC(sfcTo).updateLibAddress(sfcLib);

        nodeAuth.upgradeCode(govTo, govFrom);
        GovI(govTo).upgrade(voteBook);

        Ownable(sfcTo).transferOwnership(msg.sender);
        nodeAuth.transferOwnership(msg.sender);
    }

    function transferOwnershipOf(address target, address newOwner) external onlyOwner {
        Ownable(target).transferOwnership(newOwner);
    }

    function call(address target, bytes calldata data) external onlyOwner {
        (bool success, bytes memory result) = target.call(data);
        require(success);
        result;
    }
}
